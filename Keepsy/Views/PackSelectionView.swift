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
    @State private var isExiting = false  // fase 1: zoom
    @State private var isDescending = false  // fase 2: scende

    private let renderRadius = 10

    private let W = UIScreen.main.bounds.width
    private let H = UIScreen.main.bounds.height
    private let baseZoom: CGFloat = 2.0
    private var packWidth:  CGFloat { W * 0.90 }
    private var packHeight: CGFloat { packWidth * (350.0 / 230.0) }
    private var spacing:    CGFloat { H / 9.0 }
    private var rulloCenterY: CGFloat { H * 1.10 }
    private var selLiftY:     CGFloat { rulloCenterY - 55 }
    private var selectedY:    CGFloat { H * 0.35 }  // pack ben visibile al centro alto

    private var imageName: String {
        MuseumConfig.shared.museums.first(where: { $0.id == museumId })?.packetImageName ?? "uffizi_pacchetto"
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

            if isOpening {
                Button(action: {
                    HapticManager.shared.triggerImpact(style: .heavy)
                    // Fase 1: zoom in (pack cresce restando in alto)
                    withAnimation(.easeOut(duration: 0.30)) {
                        isExiting = true
                    }
                    // Fase 2: scende fluido al centro (movimento continuo)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                        withAnimation(.easeInOut(duration: 0.40)) {
                            isDescending = true
                        }
                    }
                    // Passa a tearing a fine sequenza
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.62) {
                        onPacketSelected()
                    }
                }) {
                    Text("OPEN")
                        .font(.custom("Helvetica-BoldOblique", size: 20))
                        .foregroundColor(.black)
                        .frame(width: 180, height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 28)
                                .fill(LinearGradient(
                                    colors: [.white, Color(hex: "EAEAEA")],
                                    startPoint: .top, endPoint: .bottom
                                ))
                                .shadow(color: .black.opacity(0.50), radius: 24, y: 8)
                        )
                }
                .position(x: W / 2, y: H * 0.78)
                .transition(.opacity.combined(with: .scale(scale: 0.88)))
                .zIndex(200)
            }

            if !isOpening {
                Button(action: {
                    HapticManager.shared.triggerImpact(style: .light)
                    onClose()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .bold))
                        Text("Back")
                            .font(.system(size: 16, weight: .regular))
                    }
                    .foregroundColor(.white)
                    .frame(width: 85, height: 44)
                    .background(Capsule().fill(Color(hex: "383838")))
                }
                .position(x: 30 + 85 / 2, y: 83 + 44 / 2)
                .zIndex(300)
            }
        }
        .frame(width: W, height: H)
        .ignoresSafeArea()
        .onAppear {
            baseScrollPosition = scrollPosition
            // Pack di mezzo già selezionato all'apertura
            selectedVirtualPos = -3
        }
    }

    // MARK: - Visuale singola bustina

    @ViewBuilder
    private func packVisual(virtualPos: Int) -> some View {
        let diff  = CGFloat(virtualPos) - scrollPosition
        let isSel = selectedVirtualPos == virtualPos

        let scale: CGFloat = {
            // Fase 1 zoom + fase 2 scende: scale resta 1.0 (= tearing full-screen)
            if isExiting { return isSel ? 1.0 : 0.0 }
            if isOpening { return isSel ? 0.65 : 0.0 }
            if isSel     { return max(0.15, 1.0 + min(diff, 0) * 0.07) }
            return max(0.15, 1.0 + diff * 0.07)
        }()

        let opacity: Double = {
            if isSel { return 1.0 }
            if diff <= 0 { return 1.0 }
            if diff >= 1 { return 0.0 }
            return Double(1.0 - diff)  // fade graduale 0→1
        }()

        // Formula CONTINUA: stessa per diff positivo e negativo
        // così l'animazione dei frame intermedi è fluida
        let naturalY: CGFloat = rulloCenterY + diff * spacing

        let yPos: CGFloat = {
            // isExiting: scende alla posizione del tearing screen (~centro-basso)
            if isExiting { return isSel ? H * 0.55 : H * 1.5 }
            if isOpening { return isSel ? selectedY : H * 1.5 }
            if isSel     { return naturalY - 80 }
            return naturalY
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
        .rotationEffect(.degrees(isOpening && !isExiting && isSel ? -4 : 0))  // tilt solo in selezione, rimosso durante uscita
        .scaleEffect(scale * baseZoom)
        .opacity(opacity)
        .position(x: W / 2, y: yPos)
        .animation(.spring(response: 0.55, dampingFraction: 0.82), value: isOpening)
        .animation(.spring(response: 0.50, dampingFraction: 0.82), value: selectedVirtualPos)
        .animation(.easeOut(duration: 0.30), value: isExiting)
        .animation(.easeInOut(duration: 0.40), value: isDescending)
    }

    // MARK: - Tap

    private func handleTap(at tapY: CGFloat) {
        guard !isSpinning else { return }

        let currentScroll = scrollPosition
        let baseInt = Int(currentScroll.rounded())
        var bestVP: Int? = nil
        var bestDist: CGFloat = .infinity

        for offset in -renderRadius...renderRadius {
            let vp   = baseInt + offset
            let diff = CGFloat(vp) - currentScroll

            // Salta pack non visibili (opacity == 0)
            guard diff < 1.0 else { continue }

            let isSel = selectedVirtualPos == vp
            let bustY = rulloCenterY + diff * spacing - (isSel ? 80 : 0)

            // Usa solo la distanza verticale dal centro del pack,
            // senza strip — vince sempre il più vicino al dito
            let d = abs(tapY - bustY)
            if d < bestDist {
                bestDist = d
                bestVP = vp
            }
        }

        // Soglia massima: non selezionare se il tap è troppo lontano da qualsiasi pack
        guard let vp = bestVP, bestDist < spacing * 1.2 else { return }

        HapticManager.shared.triggerImpact(style: .medium)

        if selectedVirtualPos == vp {
            openPacket()
            return
        }

        let targetScroll = CGFloat(vp) + 3
        let totalDelta   = targetScroll - currentScroll
        guard abs(totalDelta) > 0.01 else { return }

        withAnimation(.spring(response: 0.40, dampingFraction: 0.82)) {
            selectedVirtualPos = vp
        }
        isSpinning = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            let totalFrames = max(30, Int(abs(totalDelta) * 15))
            var frame = 0
            let scrollStart = self.scrollPosition

            self.spinTimer?.invalidate()
            self.spinTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { timer in
                frame += 1
                let progress = CGFloat(frame) / CGFloat(totalFrames)
                let eased: CGFloat = progress < 0.5
                    ? 4 * progress * progress * progress
                    : 1 - pow(-2 * progress + 2, 3) / 2

                let newScroll = scrollStart + totalDelta * eased
                self.scrollPosition     = newScroll
                self.baseScrollPosition = newScroll

                if frame >= totalFrames {
                    timer.invalidate()
                    self.scrollPosition     = targetScroll
                    self.baseScrollPosition = targetScroll
                    self.isSpinning = false
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
        withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
            isOpening = true
        }
    }
}
