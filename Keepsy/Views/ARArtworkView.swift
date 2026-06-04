import SwiftUI
import ARKit

struct ARArtworkView: View {
    @Binding var activeView: ContentView.ActiveView
    @State private var detectedArtwork: String = ""
    @State private var isTargetUnlocked: Bool = false
    @State private var diagnosticMessage: String = "Avvio ARKit..."
    @State private var selectedTargetCard: String? = nil
    @State private var dragOffset: CGFloat = 0
    @State private var sessionFoundCards: Set<String> = []
    @State private var showQuitDialog: Bool = false

    @State private var imagesReady: Bool = false
    @State private var downloadProgress: String = "Scaricamento immagini..."
    
    // Triumph unlock animation states
    @State private var triggerUnlockAnimation: String? = nil
    @State private var foundCardName: String? = nil
    @State private var isAnimatingUnlock: Bool = false
    @State private var unlockStep: UnlockAnimationStep = .none
    @State private var showCardFoundFlash = false
    @State private var greenFlashOpacity: Double = 0.0
    @State private var catturataScale: CGFloat = 1.5
    @State private var catturataOpacity: Double = 0.0

    enum UnlockAnimationStep {
        case none
        case zoomToCenter
    }
    
    var revealedCards: Set<String> {
        return CardDatabase.getRevealedCards()
    }
    
    var duplicatesInPack: Set<String> {
        return CardDatabase.getDuplicatesInActivePack()
    }
    
    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height
            let safeTop = geometry.safeAreaInsets.top
            let cardWidth: CGFloat = screenWidth * 0.44
            let cardHeight: CGFloat = cardWidth * (168.0 / 111.0)
            let cardCorner = cardWidth * 12.0 / 111.0

            ZStack {
                Color.black.ignoresSafeArea()

                // ── CAMERA ──────────────────────────────────────────────────
                if imagesReady {
                    ARViewContainer(
                        targetName: selectedTargetCard ?? "",
                        onArtworkDetected: { dbName in
                            let cleanedName = CardDatabase.cleanedArtworkName(dbName)
                            detectedArtwork = "Sbloccata: \(cleanedName)!"
                            isTargetUnlocked = true
                            if triggerUnlockAnimation == nil {
                                triggerUnlockAnimation = dbName
                            }
                        },
                        onWrongArtworkDetected: { dbName in
                            let cleanedTargetName = CardDatabase.cleanedArtworkName(selectedTargetCard ?? "")
                            detectedArtwork = "Non e' la carta selezionata! Trova \(cleanedTargetName)."
                        },
                        onDiagnosticMessageUpdated: { msg in
                            diagnosticMessage = msg
                        }
                    )
                    .ignoresSafeArea()
                } else {
                    VStack(spacing: 20) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                        Text(downloadProgress)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if CardDatabase.hasActivePack(), let activePack = CardDatabase.getActivePack(), !activePack.isEmpty {
                    let displayCards: [String] = {
                        guard let selected = selectedTargetCard else {
                            return activePack.filter { $0 != foundCardName }
                        }
                        let foundSet = revealedCards.union(duplicatesInPack).union(sessionFoundCards)

                        // Solo le carte NON ancora trovate (esclusa quella in animazione)
                        let notFound = activePack
                            .filter { $0 != foundCardName }
                            .filter { !foundSet.contains($0) }

                        // Metti la selezionata al centro
                        var ordered = notFound.filter { $0 != selected }
                        let centerIndex = ordered.count / 2
                        ordered.insert(selected, at: min(centerIndex, ordered.count))
                        return ordered
                    }()

                    // Carte già trovate (vanno in basso separatamente)
                    let foundCards: [String] = {
                        let foundSet = revealedCards.union(duplicatesInPack).union(sessionFoundCards)
                        return activePack.filter { $0 != foundCardName && $0 != selectedTargetCard && foundSet.contains($0) }
                    }()

                    // Floating Back Button (standard position)
                    Button(action: {
                        HapticManager.shared.triggerImpact(style: .light)
                        if sessionFoundCards.isEmpty {
                            withAnimation(.easeInOut(duration: 0.35)) {
                                activeView = .opening
                            }
                        } else {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showQuitDialog = true
                            }
                        }
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
                    .position(x: 30 + 85/2, y: 83 + 44/2)
                    .zIndex(60)

                    // Centered title Capsule (standard position top) - only shown when unlocked/found
                    if isAnimatingUnlock {
                        Text("✨ OPERA TROVATA! ✨")
                            .font(.system(size: 14, weight: .black))
                            .italic()
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .background(
                                Capsule()
                                    .fill(Color(hex: "4CD964").opacity(0.85))
                            )
                            .position(x: screenWidth / 2, y: 83 + 44/2)
                            .animation(.easeInOut(duration: 0.3), value: isAnimatingUnlock)
                            .zIndex(55)
                    }

                    VStack(spacing: 0) {
                        Spacer()
                            .allowsHitTesting(false)

                        // Server error manual fallback
                        let currentCity = UserDefaults.standard.string(forKey: "currentCity") ?? "capodimonte"
                        let isImageAvailable = CardDatabase.downloadedArtworkNames(for: currentCity).contains(selectedTargetCard ?? "")
                        if !isTargetUnlocked && !isImageAvailable && !isAnimatingUnlock && !displayCards.isEmpty {
                            Button(action: {
                                HapticManager.shared.triggerImpact(style: .medium)
                                if let target = selectedTargetCard { triggerUnlockAnimation = target }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                    Text("Errore server: Sblocca manualmente")
                                        .font(.system(size: 12, weight: .bold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(Color.red.opacity(0.8)))
                            }
                            .padding(.bottom, 12)
                        }

                        if CardDatabase.isActivePackAllDuplicates() {
                            Text("Tutte già nella collezione")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white.opacity(0.7))
                                .padding(.bottom, 12)
                        }

                        // CARD FAN
                        if !displayCards.isEmpty {
                            ZStack(alignment: .bottom) {
                                // Carte già trovate — fisse ai lati, stessa baseline
                                if !isAnimatingUnlock {
                                    ForEach(Array(foundCards.prefix(2).enumerated()), id: \.element) { i, cardName in
                                        let xPos: CGFloat = i == 0 ? -(screenWidth * 0.36) : (screenWidth * 0.36)
                                        ScannerCardView(name: cardName, width: cardWidth * 0.52, height: cardHeight * 0.52)
                                            .overlay(alignment: .topTrailing) {
                                                ZStack {
                                                    Circle().fill(Color(hex: "4CD964")).frame(width: 18, height: 18)
                                                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundColor(.white)
                                                }
                                                .offset(x: 4, y: -4)
                                            }
                                            .opacity(0.65)
                                            .offset(x: xPos, y: 0)
                                            .zIndex(1)
                                            .allowsHitTesting(false)
                                    }
                                }
                                ForEach(Array(displayCards.enumerated()), id: \.element) { index, cardName in
                                    let isSelected = cardName == selectedTargetCard
                                    let selectedIndex = displayCards.firstIndex(of: selectedTargetCard ?? "") ?? 2
                                    let diff = CGFloat(index - selectedIndex)
                                    
                                    // Determina se questa specifica carta si sta sbloccando
                                    let isThisCardUnlocking = isAnimatingUnlock && cardName == foundCardName
                                    
                                    // Spostamento orizzontale in tempo reale basato sul trascinamento del dito (segno + per far scorrere nella direzione del dito)
                                    let visualDiff = isThisCardUnlocking ? 0.0 : diff + (dragOffset / (cardWidth * 0.52))
                                    
                                    let xOffset: CGFloat = {
                                        if isAnimatingUnlock {
                                            if isThisCardUnlocking {
                                                return 0
                                            } else {
                                                // Sposta le altre carte fuori dallo schermo
                                                return diff * cardWidth * 1.8
                                            }
                                        } else {
                                            return visualDiff * cardWidth * 0.52
                                        }
                                    }()
                                    
                                    // Spostamento verticale (curvatura del rullo)
                                    let yOffset: CGFloat = {
                                        if isThisCardUnlocking {
                                            return -screenHeight * 0.28
                                        } else {
                                            return abs(visualDiff) * 16.0
                                        }
                                    }()
                                    
                                    // Scala: se selezionata zooma, altrimenti mantiene la scala fissa del ventaglio
                                    let scale: CGFloat = {
                                        if isThisCardUnlocking {
                                            if unlockStep == .zoomToCenter {
                                                return 1.85
                                            } else {
                                                return 0.6
                                            }
                                        } else {
                                            if isAnimatingUnlock {
                                                return 0.0
                                            } else {
                                                let absDiff = abs(visualDiff)
                                                if absDiff <= 1.0 {
                                                    return 1.15 - (absDiff * (1.15 - 0.78))
                                                } else if absDiff <= 2.0 {
                                                    return 0.78 - ((absDiff - 1.0) * (0.78 - 0.55))
                                                } else {
                                                    return max(0.38, 0.55 - ((absDiff - 2.0) * (0.55 - 0.38)))
                                                }
                                            }
                                        }
                                    }()
                                    
                                    // Opacità dinamica
                                    let opacity: Double = {
                                        if isThisCardUnlocking {
                                            return unlockStep == .zoomToCenter ? 1.0 : 0.0
                                        } else {
                                            if isAnimatingUnlock {
                                                return 0.0
                                            } else {
                                                let absDiff = abs(visualDiff)
                                                if absDiff <= 1.5 {
                                                    return 1.0
                                                } else {
                                                    return Double(max(0.0, 1.0 - (absDiff - 1.5) * 1.0))
                                                }
                                            }
                                        }
                                    }()
                                    
                                    let rotationZ = isThisCardUnlocking ? 0.0 : Double(visualDiff) * 4.0
                                    let rotationY = isThisCardUnlocking ? 0.0 : Double(-visualDiff) * 28.0
 
                                    ScannerCardView(name: cardName, width: cardWidth, height: cardHeight)
                                        .overlay(alignment: .topTrailing) {
                                            if isThisCardUnlocking {
                                                ZStack {
                                                    Circle()
                                                        .fill(Color(hex: "4CD964"))
                                                        .frame(width: 44, height: 44)
                                                        .shadow(color: Color(hex: "4CD964").opacity(0.7), radius: 8)
                                                    Image(systemName: "checkmark")
                                                        .font(.system(size: 22, weight: .bold))
                                                        .foregroundColor(.white)
                                                }
                                                .offset(x: 10, y: -10)
                                            } else if duplicatesInPack.contains(cardName) || revealedCards.contains(cardName) {
                                                ZStack {
                                                    Circle()
                                                        .fill(Color(hex: "4CD964"))
                                                        .frame(width: 28, height: 28)
                                                        .shadow(color: Color(hex: "4CD964").opacity(0.6), radius: 4)
                                                    Image(systemName: "checkmark")
                                                        .font(.system(size: 13, weight: .bold))
                                                        .foregroundColor(.white)
                                                }
                                                .offset(x: 6, y: -6)
                                            }
                                        }
                                        .shadow(
                                            color: isThisCardUnlocking ? Color(hex: "4CD964").opacity(0.7) : (isSelected ? .white.opacity(0.25) : .black.opacity(0.5)),
                                            radius: isThisCardUnlocking ? 28 : (isSelected ? 18 : 6)
                                        )
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            guard !isAnimatingUnlock, opacity > 0 else { return }
                                            HapticManager.shared.triggerImpact(style: .medium)
                                            changeSelection(to: cardName)
                                        }
                                        .allowsHitTesting(!isAnimatingUnlock && opacity > 0)
                                        .rotation3DEffect(
                                            .degrees(rotationY),
                                            axis: (x: 0.0, y: 1.0, z: 0.0),
                                            anchor: .center,
                                            anchorZ: 0.0,
                                            perspective: 0.45
                                        )
                                        .rotationEffect(.degrees(rotationZ))
                                        .scaleEffect(scale, anchor: .bottom)
                                        .offset(x: xOffset, y: yOffset)
                                        .opacity(opacity)
                                        .zIndex(isThisCardUnlocking ? 100 : (isSelected ? 20 : Double(10 - abs(Int(diff)))))
                                        .animation(.spring(response: 0.35, dampingFraction: 0.72), value: isAnimatingUnlock)
                                        .animation(.spring(response: 0.35, dampingFraction: 0.72), value: unlockStep)
                                        .animation(.spring(response: 0.35, dampingFraction: 0.72), value: selectedTargetCard)
                                }
                            }
                            .frame(width: screenWidth, height: cardHeight * 1.25, alignment: .bottom)
                            .simultaneousGesture(
                                DragGesture(minimumDistance: 5, coordinateSpace: .local)
                                    .onChanged { value in
                                        guard !isAnimatingUnlock else { return }
                                        dragOffset = value.translation.width
                                    }
                                    .onEnded { value in
                                        guard !isAnimatingUnlock else { return }
                                        let swipeThreshold: CGFloat = 30
                                        let cardStep = cardWidth * 0.52
                                        
                                        // Invert sign: dragging right (positive translation) moves content right, selecting previous card (negative steps)
                                        let rawSteps = -value.translation.width / cardStep
                                        var steps = Int(rawSteps.rounded())
                                        
                                        if steps == 0 {
                                            if value.predictedEndTranslation.width > swipeThreshold {
                                                steps = -1
                                            } else if value.predictedEndTranslation.width < -swipeThreshold {
                                                steps = 1
                                            }
                                        }
                                        
                                        // Update selection and reset dragOffset atomically in the same animation block to prevent jumps!
                                        withAnimation(.spring(response: 0.42, dampingFraction: 0.76)) {
                                            if steps != 0 {
                                                HapticManager.shared.triggerSelection()
                                                if let current = selectedTargetCard,
                                                   let currentIndex = displayCards.firstIndex(of: current),
                                                   !displayCards.isEmpty {
                                                    let newIndex = (currentIndex + steps % displayCards.count + displayCards.count) % displayCards.count
                                                    selectedTargetCard = displayCards[newIndex]
                                                    isTargetUnlocked = revealedCards.contains(displayCards[newIndex]) || duplicatesInPack.contains(displayCards[newIndex])
                                                    detectedArtwork = isTargetUnlocked ? "" : "Trova l'opera per sbloccarla!"
                                                }
                                            }
                                            dragOffset = 0
                                        }
                                    }
                            )
                        } else {
                            Spacer().frame(height: cardHeight * 1.15)
                        }
                    }
                    .zIndex(50)
                }

                // ── GREEN SCREEN FLASH ────────────────────────────────────────
                Color(hex: "4CD964")
                    .ignoresSafeArea()
                    .opacity(greenFlashOpacity)
                    .blendMode(.screen)
                    .allowsHitTesting(false)
                    .zIndex(55)

                // ── CARD FOUND BURST ──────────────────────────────────────────
                if showCardFoundFlash {
                    CardFoundFlashView { showCardFoundFlash = false }
                        .position(x: screenWidth / 2, y: screenHeight * 0.38)
                        .allowsHitTesting(false)
                        .zIndex(58)
                }

                // ── CATTURATA LABEL FOR UNLOCK ANIMATION ─────────────────────
                if isAnimatingUnlock {
                    VStack(spacing: 6) {
                        Spacer()
                        VStack(spacing: 4) {
                            Text("CATTURATA!")
                                .font(.system(size: 28, weight: .black))
                                .italic()
                                .foregroundColor(.white)
                                .shadow(color: Color(hex: "4CD964").opacity(0.9), radius: 12)
                                .shadow(color: Color(hex: "4CD964").opacity(0.5), radius: 24)
                            if let name = foundCardName {
                                Text(CardDatabase.cleanedArtworkName(name))
                                    .font(.system(size: 13, weight: .semibold))
                                    .italic()
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                        .scaleEffect(catturataScale)
                        .opacity(catturataOpacity)
                        .padding(.bottom, screenHeight * 0.16)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .zIndex(60)
                }

                // ── QUIT EXPERIENCE MODAL DIALOG ─────────────────────────────
                if showQuitDialog {
                    ZStack {
                        // Dimmed background
                        Color.black.opacity(0.65)
                            .ignoresSafeArea()
                            .transition(.opacity)
                        
                        // Dialog Card
                        VStack(spacing: 24) {
                            Text("QUIT EXPERIENCE?")
                                .font(.system(size: 26, weight: .black))
                                .italic()
                                .foregroundColor(Color(hex: "DD611B"))
                                .multilineTextAlignment(.center)
                                .padding(.top, 8)
                            
                            Text("Are you sure you want to quit the experience?\nYour progress **will be saved**")
                                .font(.system(size: 15, weight: .semibold))
                                .italic()
                                .foregroundColor(.white.opacity(0.85))
                                .multilineTextAlignment(.center)
                                .lineSpacing(4)
                                .padding(.horizontal, 16)
                            
                            VStack(spacing: 14) {
                                // DISCARD button
                                Button(action: {
                                    HapticManager.shared.triggerImpact(style: .medium)
                                    withAnimation(.easeInOut(duration: 0.35)) {
                                        showQuitDialog = false
                                    }
                                }) {
                                    Text("DISCARD")
                                        .font(.system(size: 18, weight: .black))
                                        .italic()
                                        .foregroundColor(.black)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 54)
                                        .background(Capsule().fill(Color(hex: "E5E5EA")))
                                }
                                
                                // CONFIRM button
                                Button(action: {
                                    HapticManager.shared.triggerImpact(style: .medium)
                                    
                                    // Salva tutte le carte trovate in questa sessione
                                    for name in sessionFoundCards {
                                        CardDatabase.addRevealedCard(name)
                                    }
                                    
                                    // Trigger animation for the saved cards in Collection view
                                    UserDefaults.standard.set(Array(sessionFoundCards), forKey: "recentlyCompletedPackCards")
                                    CardDatabase.clearActivePackIfNeeded()
                                    
                                    withAnimation(.easeInOut(duration: 0.35)) {
                                        showQuitDialog = false
                                        navigateToCollection()
                                    }
                                }) {
                                    Text("CONFIRM")
                                        .font(.system(size: 18, weight: .black))
                                        .italic()
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 54)
                                        .background(Capsule().fill(Color(hex: "3A3A3C")))
                                }
                            }
                            .padding(.horizontal, 8)
                        }
                        .padding(28)
                        .background(
                            RoundedRectangle(cornerRadius: 32)
                                .fill(Color(hex: "1C1C1E"))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 32)
                                        .stroke(Color.white.opacity(0.15), lineWidth: 1.5)
                                )
                        )
                        .padding(.horizontal, 28)
                        .shadow(color: Color.black.opacity(0.5), radius: 20, y: 10)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                    .zIndex(150)
                }
            }
            .ignoresSafeArea()
        }
        .onAppear {
            if let active = CardDatabase.getActivePack(), !active.isEmpty {
                let dupes = CardDatabase.getDuplicatesInActivePack()
                let revealed = CardDatabase.getRevealedCards()
                
                // Seleziona la prima carta che non è né rivelata né doppia come target iniziale
                if let target = active.first(where: { !revealed.contains($0) && !dupes.contains($0) }) {
                    selectedTargetCard = target
                } else if let target = active.first(where: { !dupes.contains($0) }) {
                    selectedTargetCard = target
                } else {
                    selectedTargetCard = active.first
                }
                isTargetUnlocked = revealed.contains(selectedTargetCard ?? "") || dupes.contains(selectedTargetCard ?? "")

                // Se TUTTE le carte sono già doppie o rivelate: niente da inquadrare,
                // vai in automatico alla collezione dopo un breve momento.
                if CardDatabase.isActivePackAllDuplicates() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        navigateToCollection()
                    }
                }
            }
        }
        .task {
            // Ensure images are on disk before starting ARKit
            let city = UserDefaults.standard.string(forKey: "currentCity") ?? "capodimonte"
            let targetList: [String]
            if CardDatabase.hasActivePack(), let activePack = CardDatabase.getActivePack(), !activePack.isEmpty {
                targetList = activePack
            } else {
                targetList = CardDatabase.artworksFor(location: city)
            }

            let downloaded = CardDatabase.downloadedArtworkNames(for: city)
            let missing = targetList.filter { !downloaded.contains($0) }

            if !missing.isEmpty {
                await MainActor.run {
                    downloadProgress = "Scaricamento \(missing.count) immagini..."
                }
                await CardDatabase.downloadImages(for: missing)
                await MainActor.run {
                    downloadProgress = "Pronto!"
                }
            }

            await MainActor.run {
                imagesReady = true
            }
        }
        .onChange(of: triggerUnlockAnimation) { _, newValue in
            if let cardName = newValue {
                startUnlockAnimation(for: cardName)
            }
        }
    }
    
    func cleanedArtworkName(_ name: String) -> String {
        return CardDatabase.cleanedArtworkName(name)
    }

    private func navigateToCollection() {
        let activeCity = UserDefaults.standard.string(forKey: "currentCity") ?? "capodimonte"
        withAnimation(.easeInOut(duration: 0.35)) {
            activeView = .collection(activeCity)
        }
    }
    
    private func changeSelection(to cardName: String) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            selectedTargetCard = cardName
            isTargetUnlocked = revealedCards.contains(cardName) || duplicatesInPack.contains(cardName)
            // Niente testo "già sbloccata": lo stato è comunicato dalla spunta verde sulla carta.
            detectedArtwork = isTargetUnlocked ? "" : "Trova l'opera per sbloccarla!"
        }
    }
    
    // Scrolling left / right between fanned card hand (revolver infinite wrap-around)
    private func selectNextCard(remainingCards: [String]) {
        guard let current = selectedTargetCard,
              let currentIndex = remainingCards.firstIndex(of: current),
              !remainingCards.isEmpty else { return }
        let nextIndex = (currentIndex + 1) % remainingCards.count
        changeSelection(to: remainingCards[nextIndex])
    }
    
    private func selectPreviousCard(remainingCards: [String]) {
        guard let current = selectedTargetCard,
              let currentIndex = remainingCards.firstIndex(of: current),
              !remainingCards.isEmpty else { return }
        let prevIndex = (currentIndex - 1 + remainingCards.count) % remainingCards.count
        changeSelection(to: remainingCards[prevIndex])
    }
    
    private func startUnlockAnimation(for cardName: String) {
        HapticManager.shared.triggerImpact(style: .rigid)
        SoundManager.shared.playSound(named: "opera_trovata")

        withAnimation(.easeInOut(duration: 0.3)) {
            foundCardName = cardName
            isAnimatingUnlock = true
        }

        sessionFoundCards.insert(cardName)

        withAnimation(.spring(response: 0.5, dampingFraction: 0.65)) {
            unlockStep = .zoomToCenter
        }

        // Green screen flash
        withAnimation(.easeOut(duration: 0.05)) { greenFlashOpacity = 0.35 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeIn(duration: 0.4)) { greenFlashOpacity = 0.0 }
        }

        // Burst di particelle + testo
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            showCardFoundFlash = true
            HapticManager.shared.triggerImpact(style: .heavy)
        }

        // "CATTURATA!" pop in
        catturataScale = 1.5
        catturataOpacity = 0.0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.6)) {
                catturataScale = 1.0
                catturataOpacity = 1.0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.3)) {
                catturataOpacity = 0.0
            }
            withAnimation(.easeInOut(duration: 0.4)) {
                unlockStep = .none
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isAnimatingUnlock = false
                    foundCardName = nil
                }
                triggerUnlockAnimation = nil

                // Controlla se abbiamo completato il pacchetto (tutte le 5 carte trovate/doppie/rivelate)
                if let activePack = CardDatabase.getActivePack(), !activePack.isEmpty {
                    let foundSet = revealedCards.union(duplicatesInPack).union(sessionFoundCards)
                    let allFound = activePack.allSatisfy { foundSet.contains($0) }
                    
                    if allFound {
                        // Salva tutte le carte trovate in questa sessione nel database definitivo
                        for name in sessionFoundCards {
                            CardDatabase.addRevealedCard(name)
                        }
                        
                        // Imposta tutte le carte trovate per l'animazione di inserimento
                        UserDefaults.standard.set(Array(sessionFoundCards), forKey: "recentlyCompletedPackCards")
                        CardDatabase.clearActivePackIfNeeded()
                        
                        navigateToCollection()
                    } else {
                        // Seleziona la prossima carta non ancora trovata
                        let remaining = activePack.filter { !foundSet.contains($0) }
                        if let nextTarget = remaining.first {
                            changeSelection(to: nextTarget)
                        }
                    }
                }
            }
        }
    }

}

// MARK: - CardFoundFlashView — green burst when card is captured

struct CardFoundFlashView: View {
    var onComplete: () -> Void

    @State private var ring1Scale: CGFloat = 0.1
    @State private var ring1Opacity: Double = 1.0
    @State private var ring2Scale: CGFloat = 0.1
    @State private var ring2Opacity: Double = 0.75
    @State private var ring3Scale: CGFloat = 0.1
    @State private var ring3Opacity: Double = 0.5
    @State private var sparkOpacity: Double = 0.0
    @State private var sparkRadius: CGFloat = 0.2
    @State private var radialScale: CGFloat = 0.4
    @State private var radialOpacity: Double = 1.0

    private let colors: [Color] = [
        Color(hex: "4CD964"), Color.white,
        Color(hex: "2EBD4A"), Color(hex: "AAFFBB"),
    ]

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [Color.white.opacity(0.85), Color(hex: "4CD964").opacity(0.55), Color.clear],
                center: .center, startRadius: 0, endRadius: 60
            )
            .scaleEffect(radialScale)
            .opacity(radialOpacity)
            .blendMode(.screen)

            Circle()
                .stroke(LinearGradient(colors: [Color.white, Color(hex: "4CD964")], startPoint: .top, endPoint: .bottom), lineWidth: 4)
                .frame(width: 70, height: 70)
                .scaleEffect(ring1Scale).opacity(ring1Opacity)
                .blur(radius: 2).blendMode(.screen)

            Circle()
                .stroke(Color(hex: "4CD964").opacity(0.65), lineWidth: 3)
                .frame(width: 140, height: 140)
                .scaleEffect(ring2Scale).opacity(ring2Opacity)
                .blur(radius: 4).blendMode(.screen)

            Circle()
                .stroke(Color(hex: "4CD964").opacity(0.35), lineWidth: 2)
                .frame(width: 220, height: 220)
                .scaleEffect(ring3Scale).opacity(ring3Opacity)
                .blur(radius: 7).blendMode(.screen)

            ZStack {
                ForEach(0..<12, id: \.self) { i in
                    let angle = Double(i) * (.pi * 2.0 / 12.0)
                    let size = CGFloat(4) + CGFloat(i % 3) * 2.0
                    let rad = 110.0 * Double(sparkRadius)
                    Circle()
                        .fill(colors[i % colors.count])
                        .frame(width: size, height: size)
                        .offset(x: CGFloat(cos(angle) * rad), y: CGFloat(sin(angle) * rad))
                }
            }
            .opacity(sparkOpacity).blur(radius: 1).blendMode(.screen)
        }
        .onAppear { run() }
    }

    func run() {
        withAnimation(.easeOut(duration: 0.15)) { radialScale = 2.8; radialOpacity = 0.0 }
        withAnimation(.easeOut(duration: 0.22)) { ring1Scale = 4.0; ring1Opacity = 0.0 }
        withAnimation(.easeOut(duration: 0.3).delay(0.04)) { ring2Scale = 3.4; ring2Opacity = 0.0 }
        withAnimation(.easeOut(duration: 0.4).delay(0.08)) { ring3Scale = 2.8; ring3Opacity = 0.0 }
        withAnimation(.easeOut(duration: 0.3)) { sparkOpacity = 1.0; sparkRadius = 1.0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.easeOut(duration: 0.2)) { sparkOpacity = 0.0 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { onComplete() }
    }
}

struct ScannerCardView: View {
    let name: String
    let width: CGFloat
    let height: CGFloat
    
    var body: some View {
        let isRevealed = CardDatabase.getRevealedCards().contains(name)
        let index = CardDatabase.allArtworkNames.firstIndex(of: name)
        let goldBorder = LinearGradient(
            colors: [
                Color(hex: "F5E480"), Color(hex: "F1B40A"),
                Color(hex: "9A6F00"), Color(hex: "F1B40A"), Color(hex: "F5E480")
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        
        ArtworkCardFrontView(
            name: name,
            title: CardDatabase.remoteArtworks[name]?.title ?? CardDatabase.cleanedArtworkName(name),
            cardIndex: index,
            width: width,
            height: height,
            isRevealed: isRevealed,
            goldBorder: goldBorder
        )
    }
}

// MARK: - RadialRayBeamView: Shiny gold/green rotating ray beams behind fanned cards
struct RadialRayBeamView: View {
    let color: Color
    @State private var rotation: Double = 0.0
    
    init(color: Color = Color(hex: "FFD700")) {
        self.color = color
    }
    
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.6), color.opacity(0.2), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 250
                    )
                )
                .frame(width: 500, height: 500)
            
            ForEach(0..<12, id: \.self) { i in
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, color.opacity(0.35), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 8, height: 600)
                    .rotationEffect(.degrees(Double(i) * 30.0 + rotation))
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 8.0).repeatForever(autoreverses: false)) {
                rotation = 360.0
            }
        }
    }
}

// MARK: - ARViewContainer: Dynamic multi-image target scanner pipeline
struct ARViewContainer: UIViewRepresentable {
    let targetName: String
    let onArtworkDetected: @MainActor (String) -> Void
    let onWrongArtworkDetected: @MainActor (String) -> Void
    let onDiagnosticMessageUpdated: @MainActor (String) -> Void
    
    func makeUIView(context: Context) -> ARSCNView {
        let arView = ARSCNView(frame: .zero)
        arView.delegate = context.coordinator
        context.coordinator.arView = arView
        
        // Pause session when resigning active to prevent background GPU access errors
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(ARViewCoordinator.handleWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        // Resume session when becoming active
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(ARViewCoordinator.handleDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
        guard ARImageTrackingConfiguration.isSupported else {
            print("ARImageTrackingConfiguration is not supported on this device/simulator.")
            return arView
        }
        
        let configuration = ARImageTrackingConfiguration()
        let activeCity = UserDefaults.standard.string(forKey: "currentCity") ?? "capodimonte"
        let downloaded = CardDatabase.downloadedArtworkNames(for: activeCity)
        let totalKnown = CardDatabase.artworksFor(location: activeCity).count
        
        var targetArtworks: [String] = []
        if CardDatabase.hasActivePack(), let activePack = CardDatabase.getActivePack(), !activePack.isEmpty {
            targetArtworks = activePack.filter { downloaded.contains($0) }
        } else {
            targetArtworks = Array(downloaded.prefix(20))
        }
        
        guard !targetArtworks.isEmpty else {
            onDiagnosticMessageUpdated("Nessuna foto scaricata! (\(totalKnown) totali sul server). Apri prima la collezione.")
            arView.session.run(configuration)
            return arView
        }
        
        // Carica le immagini di tracciamento asincronicamente e avvia la sessione UNA SOLA VOLTA
        Task(priority: .userInitiated) { @MainActor in
            var dynamicImages = Set<ARReferenceImage>()

            for name in targetArtworks {
                if let refImage = await CardDatabase.arReferenceImage(for: name) {
                    CardDatabase.validateARImage(refImage, name: name)
                    dynamicImages.insert(refImage)
                }
            }

            if !dynamicImages.isEmpty {
                configuration.trackingImages = dynamicImages
                configuration.maximumNumberOfTrackedImages = 1
                onDiagnosticMessageUpdated("✅ ARKit pronto: \(dynamicImages.count)/\(totalKnown) foto caricate.")
            } else if let fallbackImages = ARReferenceImage.referenceImages(inGroupNamed: "AR Resources", bundle: nil) {
                configuration.trackingImages = fallbackImages
                configuration.maximumNumberOfTrackedImages = 1
                onDiagnosticMessageUpdated("Uso \(fallbackImages.count) foto base da Xcode.")
            } else {
                onDiagnosticMessageUpdated("❌ Nessuna foto trovata nel telefono!")
            }
            
            // Avvia la sessione AR una sola volta per evitare freeze della fotocamera
            arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        }
        
        return arView
    }
    
    func updateUIView(_ uiView: ARSCNView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.targetName = targetName  // keep plain copy in sync (main thread)
        
        // Se l'opera selezionata è già presente nella sessione AR attiva, sbloccala subito
        if let currentFrame = uiView.session.currentFrame {
            for anchor in currentFrame.anchors {
                if let imageAnchor = anchor as? ARImageAnchor,
                   let name = imageAnchor.referenceImage.name,
                   name == targetName {
                    onArtworkDetected(name)
                    onDiagnosticMessageUpdated("Trovato: \(name)!")
                }
            }
        }
    }
    
    static func dismantleUIView(_ uiView: ARSCNView, coordinator: ARViewCoordinator) {
        uiView.session.pause()
    }
    
    func makeCoordinator() -> ARViewCoordinator {
        ARViewCoordinator(parent: self)
    }
}

// Private association key for targetName
nonisolated(unsafe) private var targetNameKey: UInt8 = 0

// MARK: - ARViewCoordinator: Standalone, thread-safe ARSCNView delegate
class ARViewCoordinator: NSObject, ARSCNViewDelegate {
    var parent: ARViewContainer
    
    weak var arView: ARSCNView?
    private let updateQueue = DispatchQueue(label: "ar.update.queue", qos: .userInitiated)

    init(parent: ARViewContainer) {
        self.parent = parent
        super.init()
        self.targetName = parent.targetName
    }
    
    // Thread-safe targetName using atomic Objective-C Associated Objects
    nonisolated var targetName: String {
        get {
            objc_getAssociatedObject(self, &targetNameKey) as? String ?? ""
        }
        set {
            objc_setAssociatedObject(self, &targetNameKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc func handleWillResignActive() {
        arView?.session.pause()
    }
    
    @objc func handleDidBecomeActive() {
        if let configuration = arView?.session.configuration {
            arView?.session.run(configuration)
        }
    }

    nonisolated func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard let imageAnchor = anchor as? ARImageAnchor else { return }
        let rawName = imageAnchor.referenceImage.name ?? "Sconosciuta"
        // Read coordinator's plain-String copy (now synchronized via thread-safe lock getter)
        let capturedTargetName = targetName

        updateQueue.async {
            let dbName = rawName
            DispatchQueue.main.async {
                let foundCards = CardDatabase.getFoundCards()
                if capturedTargetName.isEmpty {
                    if foundCards.contains(dbName) {
                        self.parent.onArtworkDetected(dbName)
                    }
                } else if dbName == capturedTargetName {
                    self.parent.onArtworkDetected(dbName)
                } else {
                    self.parent.onWrongArtworkDetected(dbName)
                }
                self.parent.onDiagnosticMessageUpdated("Trovato: \(dbName)!")
            }
        }
    }

    nonisolated func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let imageAnchor = anchor as? ARImageAnchor else { return }
        let rawName = imageAnchor.referenceImage.name ?? "Sconosciuta"
        let capturedTargetName = targetName

        updateQueue.async {
            let dbName = rawName
            DispatchQueue.main.async {
                if dbName == capturedTargetName {
                    self.parent.onArtworkDetected(dbName)
                    self.parent.onDiagnosticMessageUpdated("Trovato: \(dbName)!")
                }
            }
        }
    }
}
