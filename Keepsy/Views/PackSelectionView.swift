import SwiftUI

struct PackSelectionView: View {
    let museumId: String
    let onPacketSelected: () -> Void
    let onClose: () -> Void

    @State private var scrollPosition: CGFloat = 0
    @State private var baseScrollPosition: CGFloat = 0
    @State private var isOpening = false
    @State private var selectedVirtualPos: Int? = nil
    @State private var isSpinning = false
    @State private var spinTimer: Timer? = nil

    private let renderRadius = 10

    private let W = UIScreen.mainBounds.width
    private let H = UIScreen.mainBounds.height
    private let baseZoom: CGFloat = 2.0
    private var packWidth:  CGFloat { W * 0.90 }
    private var packHeight: CGFloat { packWidth * (350.0 / 230.0) }
    private var spacing:    CGFloat { H / 9.0 }
    private var rulloCenterY: CGFloat { H * 1.10 }
    private var selLiftY:     CGFloat { rulloCenterY - 55 }
    private var selectedY:    CGFloat { H * 0.35 }

    // Posizione Y raised del tearing: centro schermo meno l'offset raised di PackOpeningView
    private var raisedY: CGFloat { H / 2 - H * 0.15 }

    private let exitScale: CGFloat = 0.8
    private let selLift: CGFloat = 28

    private var imageName: String {
        MuseumConfig.shared.museums.first(where: { $0.id == museumId })?.packetImageName ?? "uffizi_pacchetto"
    }

    private func topOffset(forDiff diff: CGFloat) -> CGFloat {
        let s = max(0.15, 1.0 + diff * 0.07)
        return packHeight * baseZoom * s * 0.225
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "06080B"), Color(hex: "14193B")],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            GridBackground().opacity(0.4)

            let baseInt = Int(scrollPosition.rounded())
            ZStack {
                ForEach(sortedOffsets(baseInt: baseInt), id: \.self) { offset in
                    let virtualPos = baseInt + offset
                    packVisual(virtualPos: virtualPos)
                }
            }
            .frame(width: W, height: H)
            .allowsHitTesting(false)

            Color.clear
                .contentShape(Rectangle())
                .frame(width: W, height: H)
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { v in
                            guard !isOpening, !isSpinning else { return }
                            if abs(v.translation.height) > 6 {
                                scrollPosition = baseScrollPosition - v.translation.height / spacing
                            }
                        }
                        .onEnded { v in
                            guard !isOpening, !isSpinning else { return }
                            let drag = abs(v.translation.height)
                            if drag < 8 {
                                handleTap(at: v.startLocation.y)
                            } else {
                                snapScroll(velocity: v.predictedEndTranslation.height, drag: drag)
                            }
                        }
                )

            // Museum name + city header with blur
            if !isOpening {
                VStack(spacing: 4) {
                    if let museum = MuseumConfig.shared.museums.first(where: { $0.id == museumId }) {
                        Text(museum.name.uppercased())
                            .font(.system(size: 36, weight: .black, design: .default).italic())
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(hex: "E36D13"), Color(hex: "FEBB0B")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        Text(museum.city)
                            .font(.system(size: 16, weight: .regular, design: .default).italic())
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
                .background(
                    Ellipse()
                        .fill(Color(hex: "E36D13").opacity(0.25))
                        .frame(width: 220, height: 70)
                        .blur(radius: 35)
                        .offset(y: -5)
                )
                .position(x: W / 2, y: 100)
                .zIndex(300)
            }
        }
        .frame(width: W, height: H)
        .ignoresSafeArea()
        .onAppear {
            baseScrollPosition = scrollPosition
            selectedVirtualPos = Int(scrollPosition.rounded()) - 3
        }
    }

    // MARK: - Visuale singola bustina

    @ViewBuilder
    private func packVisual(virtualPos: Int) -> some View {
        let diff  = CGFloat(virtualPos) - scrollPosition
        let isSel = selectedVirtualPos == virtualPos

        let scale: CGFloat = {
            if isOpening && isSel { return 1.0 }   // mantiene scala naturale (baseZoom applicato sotto)
            if isOpening          { return 0.0 }
            return max(0.15, 1.0 + diff * 0.07)
        }()

        let opacity: Double = {
            if isSel { return 1.0 }
            if diff <= 0 { return 1.0 }
            if diff >= 1 { return 0.0 }
            return Double(1.0 - diff)
        }()

        let naturalY: CGFloat = rulloCenterY + diff * spacing

        let yPos: CGFloat = {
            if isOpening && isSel {
                // Muove il pack esattamente alla posizione raised del tearing
                return raisedY
            }
            if isOpening { return H * 1.5 }
            return isSel ? naturalY - selLift : naturalY
        }()

        let brightness: CGFloat = {
            if isSel { return 1.0 }
            return max(0.18, 0.58 - abs(diff) * 0.11)
        }()

        SceneKitPacketView(
            interactive: false,
            isTorn: false,
            museumId: museumId,
            packetImageName: imageName
        )
        .frame(width: packWidth, height: packHeight)
        .colorMultiply(Color(white: brightness))
        .shadow(
            color: isSel ? Color(hex: "FF7A00").opacity(0.55) : Color.black.opacity(0.65),
            radius: isSel ? 36 : 6,
            y: isSel ? 18 : 2
        )
        .scaleEffect(scale * baseZoom)
        .opacity(opacity)
        .position(x: W / 2, y: yPos)
        .animation(.spring(response: 0.48, dampingFraction: 0.82), value: isOpening)
        .animation(.spring(response: 0.50, dampingFraction: 0.82), value: selectedVirtualPos)
    }

    // MARK: - Tap

    private func handleTap(at tapY: CGFloat) {
        guard !isSpinning else { return }
        let scroll = scrollPosition
        let baseInt = Int(scroll.rounded())

        var best: (vp: Int, dist: CGFloat)? = nil
        for offset in -renderRadius...renderRadius {
            let vp   = baseInt + offset
            let diff = CGFloat(vp) - scroll
            guard diff < 1.0, diff > -CGFloat(renderRadius) else { continue }
            let lift: CGFloat = (vp == selectedVirtualPos) ? selLift : 0
            let topY = rulloCenterY + diff * spacing - topOffset(forDiff: diff) - lift
            let d = abs(tapY - topY)
            if best == nil || d < best!.dist { best = (vp, d) }
        }
        guard let pick = best else { return }
        HapticManager.shared.triggerImpact(style: .medium)
        if pick.vp == selectedVirtualPos { openPacket() }
        else { selectAndScroll(to: pick.vp, currentScroll: scroll) }
    }

    // MARK: - selectAndScroll

    private func selectAndScroll(to vp: Int, currentScroll: CGFloat) {
        let targetScroll = CGFloat(vp) + 3
        let totalDelta   = targetScroll - currentScroll
        guard abs(totalDelta) > 0.01 else { return }

        withAnimation(.spring(response: 0.40, dampingFraction: 0.82)) {
            selectedVirtualPos = vp
        }
        isSpinning = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            let totalFrames = max(30, Int(abs(totalDelta) * 15))
            nonisolated(unsafe) var frame = 0
            let scrollStart = self.scrollPosition

            self.spinTimer?.invalidate()
            self.spinTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { _ in
                MainActor.assumeIsolated {
                    frame += 1
                    let progress = CGFloat(frame) / CGFloat(totalFrames)
                    let eased: CGFloat = progress < 0.5
                        ? 4 * progress * progress * progress
                        : 1 - pow(-2 * progress + 2, 3) / 2

                    let newScroll = scrollStart + totalDelta * eased
                    self.scrollPosition     = newScroll
                    self.baseScrollPosition = newScroll

                    if frame >= totalFrames {
                        self.spinTimer?.invalidate()
                        self.scrollPosition     = targetScroll
                        self.baseScrollPosition = targetScroll
                        self.isSpinning = false
                    }
                }
            }
        }
    }

    // MARK: - Snap scroll

    private func snapScroll(velocity: CGFloat, drag: CGFloat) {
        var target = scrollPosition.rounded()
        if drag < spacing * 0.4, abs(velocity) > 180 {
            target = velocity < 0
                ? floor(scrollPosition) + 1
                : ceil(scrollPosition) - 1
        }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            scrollPosition     = target
            baseScrollPosition = target
            selectedVirtualPos = Int(target) - 3
        }
    }

    // MARK: - Ordine rendering

    private func sortedOffsets(baseInt: Int) -> [Int] {
        Array(-renderRadius...renderRadius).sorted { a, b in
            let dA = CGFloat(baseInt + a) - scrollPosition
            let dB = CGFloat(baseInt + b) - scrollPosition
            return dA < dB
        }
    }

    // MARK: - Apertura

    private func openPacket() {
        guard selectedVirtualPos != nil else { return }
        HapticManager.shared.triggerImpact(style: .medium)
        // Alza il pack nel rullo, poi (dopo che la spring si è stabilizzata) passa al tearing
        withAnimation(.spring(response: 0.48, dampingFraction: 0.82)) {
            isOpening = true
        }
        // Delay > response spring così il pack è effettivamente FERMO a raisedY:
        // il swap rullo→tearing avviene su un pack statico → niente scatto.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            onPacketSelected()
        }
    }
}
