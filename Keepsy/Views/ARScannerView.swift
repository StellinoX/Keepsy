import SwiftUI
import ARKit
import simd

struct ARViewContainer: UIViewRepresentable {
    let targetName: String
    let isCaptureEnabled: Bool
    let onScanProgressUpdated: @MainActor (ArtworkScanHold.Progress) -> Void
    let onArtworkDetected: @MainActor (String) -> Bool
    let onDiagnosticMessageUpdated: @MainActor (String) -> Void

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        context.coordinator.attach(to: view)
        guard ARImageTrackingConfiguration.isSupported else {
            onDiagnosticMessageUpdated("Image scanning is unavailable on this device.")
            return view
        }

        context.coordinator.prepareTrackingImages(names: CardDatabase.getActivePack() ?? [])
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

nonisolated private struct TrackedImageSnapshot: Sendable {
    let name: String
    let transform: simd_float4x4
    let physicalSize: CGSize
}

@MainActor
final class ARViewCoordinator: NSObject, ARSessionDelegate {
    var parent: ARViewContainer
    private weak var arView: ARSCNView?
    private var preparationTask: Task<Void, Never>?
    private var trackingImagesByName: [String: Set<ARReferenceImage>] = [:]
    private var activeReferenceNames: Set<String> = []
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

    func prepareTrackingImages(names: [String]) {
        preparationTask?.cancel()
        var orderedNames = names
        if let targetIndex = orderedNames.firstIndex(of: gate.targetName) {
            let target = orderedNames.remove(at: targetIndex)
            orderedNames.insert(target, at: 0)
        }
        preparationTask = Task { [weak self] in
            for name in orderedNames {
                guard !Task.isCancelled else { return }
                let references = await CardDatabase.arReferenceImages(for: name)
                guard !Task.isCancelled, let self, self.isAttached else { return }
                guard !references.isEmpty else { continue }
                self.trackingImagesByName[name] = Set(references)
                if self.gate.targetName == name { self.applyTrackingTarget() }
            }
            guard !Task.isCancelled, let self, self.isAttached else { return }
            self.parent.onDiagnosticMessageUpdated(
                "Scanner ready: \(self.trackingImagesByName.count)/\(names.count) artworks validated."
            )
        }
    }

    func updateTrackingTarget(_ name: String, isCaptureEnabled: Bool) {
        let targetChanged = gate.targetName != name
        let captureChanged = self.isCaptureEnabled != isCaptureEnabled
        guard targetChanged || captureChanged else { return }
        self.isCaptureEnabled = isCaptureEnabled
        if targetChanged {
            gate.select(name)
        } else {
            gate.invalidatePendingDetections()
        }
        publishSelection()
        resetHold()
        if targetChanged { applyTrackingTarget() }
    }

    private func applyTrackingTarget() {
        guard isAttached, !isSuspended else { return }
        let images = trackingImagesByName[gate.targetName] ?? []
        activeReferenceNames = Set(images.compactMap(\.name))
        guard !images.isEmpty else {
            arView?.session.pause()
            return
        }

        let configuration = ARImageTrackingConfiguration()
        configuration.isAutoFocusEnabled = true
        configuration.trackingImages = images
        // A loosely tracked variant should not occupy the only tracking slot.
        configuration.maximumNumberOfTrackedImages = min(images.count, 4)
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
        let trackedImages = frame.anchors.compactMap { anchor -> TrackedImageSnapshot? in
            guard let imageAnchor = anchor as? ARImageAnchor,
                  imageAnchor.isTracked,
                  let name = imageAnchor.referenceImage.name else { return nil }
            return TrackedImageSnapshot(
                name: name,
                transform: imageAnchor.transform,
                physicalSize: imageAnchor.referenceImage.physicalSize
            )
        }
        guard !trackedImages.isEmpty else { return }
        let receivedAt = ProcessInfo.processInfo.systemUptime
        let timestamp = frame.timestamp
        let cameraTransform = frame.camera.transform
        let cameraProjection = frame.camera.projectionMatrix
        Task { @MainActor [weak self] in
            guard let self, selection.id == self.gate.selectionID else { return }
            guard ProcessInfo.processInfo.systemUptime - receivedAt <= ArtworkScanHold.maximumFrameGap else {
                self.resetHold()
                return
            }
            self.processFrame(
                cameraTransform: cameraTransform,
                cameraProjection: cameraProjection,
                images: trackedImages,
                timestamp: timestamp,
                selectionID: selection.id
            )
        }
    }

    private func processFrame(
        cameraTransform: simd_float4x4,
        cameraProjection: simd_float4x4,
        images: [TrackedImageSnapshot],
        timestamp: TimeInterval,
        selectionID: UUID
    ) {
        guard isAttached, !isSuspended, isCaptureEnabled,
              selectionID == gate.selectionID, timestamp > lastFrameTimestamp,
              let arView, arView.bounds.width > 0, arView.bounds.height > 0 else { return }
        lastFrameTimestamp = timestamp
        lastFrameArrival = ProcessInfo.processInfo.systemUptime

        let name = gate.targetName
        guard gate.canTrack(artworkName: name),
              CardDatabase.getFoundCards().contains(name),
              !CardDatabase.getRevealedCards().contains(name),
              !CardDatabase.getDuplicatesInActivePack().contains(name) else { return }

        let viewProjection = cameraProjection * simd_inverse(cameraTransform)
        let isTargetVisible = images.contains { image in
            guard activeReferenceNames.contains(image.name) else { return false }
            let centerSize = CGSize(
                width: max(0.01, image.physicalSize.width * 0.25),
                height: max(0.01, image.physicalSize.height * 0.25)
            )
            return ArtworkScanVisibility.containsArtwork(
                clipTransform: viewProjection * image.transform,
                size: centerSize
            )
        }
        guard isTargetVisible else { return }

        // The carousel can change before SwiftUI updates the camera view.
        var updatedGate = gate
        guard updatedGate.accept(artworkName: name, selectionID: selectionID, time: timestamp),
              parent.onArtworkDetected(name) else { return }
        gate = updatedGate
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
