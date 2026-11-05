import SwiftUI
import ARKit
import simd

struct ARViewContainer: UIViewRepresentable {
    let targetName: String
    let isCaptureEnabled: Bool
    let onScanProgressUpdated: @MainActor (ArtworkScanHold.Progress) -> Void
    let onArtworkDetected: @MainActor (String) -> Void
    let onWrongArtworkDetected: @MainActor (String) -> Void
    let onDiagnosticMessageUpdated: @MainActor (String) -> Void

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        context.coordinator.attach(to: view)
        guard ARImageTrackingConfiguration.isSupported else {
            onDiagnosticMessageUpdated("Image scanning is unavailable on this device.")
            return view
        }

        let configuration = ARImageTrackingConfiguration()
        configuration.isAutoFocusEnabled = true
        let city = UserDefaults.standard.string(forKey: "currentCity") ?? "uffizi"
        let downloaded = CardDatabase.downloadedArtworkNames(for: city)
        let names = CardDatabase.getActivePack().flatMap { $0.isEmpty ? nil : $0 }
            ?? Array(downloaded.prefix(20))
        context.coordinator.prepareTrackingImages(names: names, configuration: configuration)
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateTrackingTarget(targetName, isCaptureEnabled: isCaptureEnabled)
    }

    static func dismantleUIView(_ uiView: ARSCNView, coordinator: ARViewCoordinator) {
        coordinator.stop()
    }

    func makeCoordinator() -> ARViewCoordinator {
        ARViewCoordinator(parent: self)
    }
}

/// A single atomic snapshot prevents queued callbacks from a previous selection
/// (including A → B → A) from unlocking the current card.
nonisolated private final class ArtworkScanSelection: Sendable {
    let id: UUID
    init(id: UUID) { self.id = id }
}

nonisolated(unsafe) private var scanSelectionKey: UInt8 = 0

@MainActor
final class ARViewCoordinator: NSObject, ARSessionDelegate {
    var parent: ARViewContainer
    private weak var arView: ARSCNView?
    private var preparationTask: Task<Void, Never>?
    private var trackingImagesByName: [String: Set<ARReferenceImage>] = [:]
    private var configuration: ARImageTrackingConfiguration?
    private var gate: ArtworkScanGate
    private var isAttached = false
    private var isSuspended = false
    private var isCaptureEnabled: Bool
    private var hold = ArtworkScanHold()
    private var reportedProgress: ArtworkScanHold.Progress = .idle
    private var lastFrameTimestamp = -TimeInterval.infinity
    private var lastFrameArrival = -TimeInterval.infinity
    private var frameWatchdog: Task<Void, Never>?

    private nonisolated var selection: ArtworkScanSelection? {
        get { objc_getAssociatedObject(self, &scanSelectionKey) as? ArtworkScanSelection }
        set { objc_setAssociatedObject(self, &scanSelectionKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }

    init(parent: ARViewContainer) {
        self.parent = parent
        self.gate = ArtworkScanGate(targetName: parent.targetName)
        self.isCaptureEnabled = parent.isCaptureEnabled
        super.init()
        publishSelection()
    }

    func attach(to view: ARSCNView) {
        arView = view
        view.session.delegate = self
        isAttached = true
        NotificationCenter.default.addObserver(self, selector: #selector(suspend),
            name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resume),
            name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    func prepareTrackingImages(names: [String], configuration: ARImageTrackingConfiguration) {
        self.configuration = configuration
        preparationTask?.cancel()
        preparationTask = Task { [weak self] in
            var images: [String: Set<ARReferenceImage>] = [:]
            for name in names {
                guard !Task.isCancelled else { return }
                let references = await CardDatabase.arReferenceImages(for: name)
                if !references.isEmpty { images[name] = Set(references) }
            }
            guard !Task.isCancelled, let self, self.isAttached else { return }
            self.trackingImagesByName = images
            self.applyTrackingTarget()
            self.parent.onDiagnosticMessageUpdated(
                "Scanner ready: \(images.count)/\(names.count) artworks validated."
            )
        }
    }

    func updateTrackingTarget(_ name: String, isCaptureEnabled: Bool) {
        let targetChanged = gate.targetName != name
        guard targetChanged || self.isCaptureEnabled != isCaptureEnabled else { return }
        self.isCaptureEnabled = isCaptureEnabled
        if targetChanged { gate.select(name) }
        gate.invalidatePendingDetections()
        publishSelection()
        resetHold()
        if targetChanged { applyTrackingTarget() }
    }

    private func applyTrackingTarget() {
        guard let configuration, isAttached, !isSuspended else { return }
        let images: Set<ARReferenceImage>
        if gate.targetName.isEmpty {
            images = Set(trackingImagesByName.values.flatMap { $0 })
        } else {
            images = trackingImagesByName[gate.targetName] ?? []
        }
        guard !images.isEmpty else {
            arView?.session.pause()
            parent.onDiagnosticMessageUpdated("No valid reference for the selected artwork.")
            return
        }
        configuration.trackingImages = images
        configuration.maximumNumberOfTrackedImages = gate.targetName.isEmpty
            ? min(trackingImagesByName.count, 4) : 1
        gate.invalidatePendingDetections()
        publishSelection()
        resetHold()
        arView?.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    private func publishSelection() {
        selection = ArtworkScanSelection(id: gate.selectionID)
    }

    @objc private func suspend() {
        isSuspended = true
        gate.invalidatePendingDetections()
        publishSelection()
        resetHold()
        arView?.session.pause()
    }

    @objc private func resume() {
        isSuspended = false
        applyTrackingTarget()
    }

    func stop() {
        isAttached = false
        preparationTask?.cancel()
        preparationTask = nil
        gate.invalidatePendingDetections()
        publishSelection()
        resetHold()
        arView?.session.pause()
        arView?.session.delegate = nil
        NotificationCenter.default.removeObserver(self)
    }

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard let selection else { return }
        let receivedAt = ProcessInfo.processInfo.systemUptime
        // Copy only tracking metadata, without retaining the camera's pixel buffers
        // while waiting for the main actor to update the progress indicator.
        let timestamp = frame.timestamp
        let camera = frame.camera
        let images = frame.anchors.compactMap { $0 as? ARImageAnchor }
        Task { @MainActor [weak self] in
            guard let self, selection.id == self.gate.selectionID else { return }
            guard ProcessInfo.processInfo.systemUptime - receivedAt <= ArtworkScanHold.maximumFrameGap else {
                self.resetHold()
                return
            }
            self.processFrame(camera: camera, images: images, timestamp: timestamp, selectionID: selection.id)
        }
    }

    private func processFrame(camera: ARCamera, images: [ARImageAnchor], timestamp: TimeInterval,
                              selectionID: UUID) {
        guard isAttached, !isSuspended, isCaptureEnabled,
              selectionID == gate.selectionID, timestamp > lastFrameTimestamp,
              let arView, arView.bounds.width > 0, arView.bounds.height > 0 else { return }
        lastFrameTimestamp = timestamp
        if let latestTimestamp = arView.session.currentFrame?.timestamp,
           latestTimestamp - timestamp > ArtworkScanHold.maximumFrameGap {
            resetHold()
            return
        }
        lastFrameArrival = ProcessInfo.processInfo.systemUptime

        let projection = camera.projectionMatrix(for: .portrait,
            viewportSize: arView.bounds.size, zNear: 0.001, zFar: 1_000)
        let viewProjection = projection * simd_inverse(camera.transform)
        let foundNames = CardDatabase.getFoundCards()
        let visibleNames = Set(images.compactMap { image -> String? in
            guard image.isTracked,
                  let name = image.referenceImage.name, foundNames.contains(name),
                  gate.canTrack(artworkName: name),
                  ArtworkScanVisibility.containsArtwork(
                    clipTransform: viewProjection * image.transform,
                    size: image.referenceImage.physicalSize) else { return nil }
            return name
        })
        guard let name = visibleNames.first,
              gate.accept(artworkName: name, selectionID: selectionID, time: timestamp) else { return }
        parent.onArtworkDetected(name)
        parent.onDiagnosticMessageUpdated("Found: \(name)!")
    }

    private func resetHold() {
        hold.reset()
        frameWatchdog?.cancel()
        frameWatchdog = nil
        publishProgress(.idle)
    }

    private func publishProgress(_ progress: ArtworkScanHold.Progress) {
        guard progress.artworkName != reportedProgress.artworkName || progress.isComplete ||
                abs(progress.fraction - reportedProgress.fraction) >= 0.025 else { return }
        reportedProgress = progress
        // Defer state writes when a carousel update resets the hold in updateUIView.
        Task { @MainActor [weak self] in
            guard let self, self.reportedProgress == progress else { return }
            self.parent.onScanProgressUpdated(progress)
        }
    }

    private func startFrameWatchdogIfNeeded() {
        guard frameWatchdog == nil else { return }
        frameWatchdog = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                guard let self else { return }
                if ProcessInfo.processInfo.systemUptime - self.lastFrameArrival > ArtworkScanHold.maximumFrameGap {
                    self.resetHold()
                    return
                }
            }
        }
    }

    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor [weak self] in self?.suspend() }
    }

    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        Task { @MainActor [weak self] in
            guard UIApplication.shared.applicationState == .active else { return }
            self?.resume()
        }
    }
}
