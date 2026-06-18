import SwiftUI
import ARKit
import CoreLocation

struct ARArtworkView: View {
    @Binding var activeView: ContentView.ActiveView
    @State private var detectedArtwork: String = ""
    @State private var isTargetUnlocked: Bool = false
    @State private var diagnosticMessage: String = "Starting ARKit..."
    @State private var selectedTargetCard: String? = nil
    @State private var dragOffset: CGFloat = 0
    @State private var sessionFoundCards: Set<String> = []
    @State private var showQuitDialog: Bool = false
    @State private var devBypassGeofence = false

    @State private var imagesReady: Bool = false
    @State private var downloadProgress: String = "Downloading images..."
    
    // Proximity / Location variables
    @State private var locationManager = LocationManager()
    @State private var carouselOffset: CGFloat = 2.0
    
    // Triumph unlock animation states
    @State private var triggerUnlockAnimation: String? = nil
    @State private var foundCardName: String? = nil
    @State private var isAnimatingUnlock: Bool = false
    @State private var unlockStep: UnlockAnimationStep = .none
    @State private var showCardFoundFlash = false
    @State private var greenFlashOpacity: Double = 0.0
    @State private var catturataScale: CGFloat = 1.5
    @State private var catturataOpacity: Double = 0.0
    @State private var showUnlockCheckmark = false
    @State private var showAutoKeptPopup: Bool = false
    @State private var autoKeptCount: Int = 0

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
    
    var activeMuseum: Museum? {
        let activeMuseumId = UserDefaults.standard.string(forKey: "currentCity") ?? "capodimonte"
        return MuseumConfig.shared.museums.first(where: { $0.id == activeMuseumId })
    }
    
    var isBlocked: Bool {
        guard let museum = activeMuseum else { return false }
        
        if locationManager.authorizationStatus == .denied || locationManager.authorizationStatus == .restricted {
            return true
        }
        
        guard locationManager.lastKnownLocation != nil else {
            return false // not blocked yet, wait for location
        }
        
        return !locationManager.isUserNear(museum: museum)
    }
    
    var distanceToActiveMuseum: CLLocationDistance? {
        guard let museum = activeMuseum else { return nil }
        return locationManager.distanceTo(museum: museum)
    }

    // Pre-composed Text pieces keep the type-checker from solving one giant
    // interpolated literal (caused an "unable to type-check in reasonable time"
    // archive failure on slower CI machines).
    private var congratsSubtitle: Text {
        let p1 = Text("You just ").font(.custom("Helvetica-Oblique", size: 16))
        let kept = Text("Kept").font(.custom("Helvetica-BoldOblique", size: 16))
        let p2 = Text(" an artwork").font(.custom("Helvetica-Oblique", size: 16))
        return Text("\(p1)\(kept)\(p2)")
    }

    private var autoKeptMessage: Text {
        let semibold = Font.system(size: 15, weight: .semibold)
        let black = Font.system(size: 15, weight: .black)
        let countText = "\(autoKeptCount) \(autoKeptCount == 1 ? "card" : "cards")"
        let p1 = Text("You closed the app with ").font(semibold).italic()
        let count = Text(countText).font(black).italic()
        let p2 = Text(" not yet in your collection.\nDon't worry — we ").font(semibold).italic()
        let kept = Text("Kept").font(black).italic()
        let p3 = Text(" them for you.").font(semibold).italic()
        return Text("\(p1)\(count)\(p2)\(kept)\(p3)")
    }

    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height
            let cardWidth: CGFloat = screenWidth * 0.44
            let cardHeight: CGFloat = cardWidth * (168.0 / 111.0)
            let cardCorner = cardWidth * 3.0 / 111.0

            ZStack {
                Color.black.ignoresSafeArea()

                // ── CAMERA / GEOLOCATION CHECK ──────────────────────────────
                if isBlocked && !devBypassGeofence {
                    geofenceWarningOverlay(geometry: geometry)
                } else {
                    if imagesReady {
                        ARViewContainer(
                            targetName: selectedTargetCard ?? "",
                            onArtworkDetected: { dbName in
                                guard !isAnimatingUnlock else { return }
                                guard triggerUnlockAnimation == nil else { return }
                                
                                let isAlreadyUnlocked = revealedCards.contains(dbName) ||
                                                        duplicatesInPack.contains(dbName) ||
                                                        sessionFoundCards.contains(dbName)
                                guard !isAlreadyUnlocked else { return }
                                
                                let cleanedName = CardDatabase.cleanedArtworkName(dbName)
                                detectedArtwork = "Unlocked: \(cleanedName)!"
                                isTargetUnlocked = true
                                triggerUnlockAnimation = dbName
                            },
                            onWrongArtworkDetected: { dbName in
                                let cleanedTargetName = CardDatabase.cleanedArtworkName(selectedTargetCard ?? "")
                                detectedArtwork = "Not the selected card! Find \(cleanedTargetName)."
                            },
                            onDiagnosticMessageUpdated: { msg in
                                diagnosticMessage = msg
                            }
                        )
                        .ignoresSafeArea()
                        .blur(radius: isAnimatingUnlock ? 15 : 0)
                    } else if locationManager.lastKnownLocation == nil && locationManager.authorizationStatus != .denied && locationManager.authorizationStatus != .restricted {
                        VStack(spacing: 20) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.5)
                            Text("Verifying museum proximity...")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VStack(spacing: 20) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.5)
                            Text(downloadProgress)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    if isAnimatingUnlock {
                        Color.black.opacity(0.55)
                            .ignoresSafeArea()
                            .transition(.opacity)
                            .zIndex(30)
                    }

                if CardDatabase.hasActivePack(), let activePack = CardDatabase.getActivePack(), !activePack.isEmpty {
                    let displayCards: [String] = activePack

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
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                    }
                    .position(x: 30 + 85/2, y: 83 + 44/2)
                    .opacity(isAnimatingUnlock ? 0.0 : 1.0)
                    .zIndex(60)

                    VStack(spacing: 0) {
                        Spacer()
                            .allowsHitTesting(false)

                        // MARK: - GUEST MODE (DEV ONLY)
                        // TODO: Remove this entire block before production if no longer needed
                        #if DEBUG
                        if !isAnimatingUnlock && !isTargetUnlocked {
                            Button(action: {
                                HapticManager.shared.triggerImpact(style: .medium)
                                if let target = selectedTargetCard {
                                    let isAlreadyUnlocked = revealedCards.contains(target) ||
                                                            duplicatesInPack.contains(target) ||
                                                            sessionFoundCards.contains(target)
                                    if !isAlreadyUnlocked && triggerUnlockAnimation == nil {
                                        let cleanedName = CardDatabase.cleanedArtworkName(target)
                                        detectedArtwork = "Unlocked: \(cleanedName)!"
                                        isTargetUnlocked = true
                                        triggerUnlockAnimation = target
                                    }
                                }
                            }) {
                                Text("Guest Mode")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.35))
                                .frame(width: 80, height: 24)
                                .background(Capsule().fill(Color.white.opacity(0.10)))
                            }
                            .padding(.bottom, 14)
                        }
                        #endif

                        if CardDatabase.isActivePackAllDuplicates() {
                            Text("All already collected")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.7))
                                .padding(.bottom, 12)
                        }

                        // CARD FAN (Scrollable Carousel with Fixed Selection Alignment)
                        if !displayCards.isEmpty {
                            ZStack(alignment: .bottom) {
                                ForEach(Array(displayCards.enumerated()), id: \.element) { index, cardName in
                                    // Determina se questa specifica carta si sta sbloccando
                                    let isThisCardUnlocking = isAnimatingUnlock && cardName == foundCardName
                                    
                                    // Calculate diff relative to carouselOffset and dragOffset
                                    let currentCarouselOffset = isThisCardUnlocking ? CGFloat(index) : (carouselOffset - (dragOffset / (cardWidth * 0.52)))
                                    let diff = CGFloat(index) - currentCarouselOffset
                                    
                                    // Scrollable horizontal X position
                                    // Scrollable horizontal X position
                                    let xOffset: CGFloat = {
                                        if isThisCardUnlocking {
                                            return 0
                                        } else if isAnimatingUnlock {
                                            return diff * cardWidth * 1.8
                                        } else {
                                            // Carte laterali spostate orizzontalmente, quella centrale ferma
                                            return diff * cardWidth * 0.38
                                        }
                                    }()

                                    let yOffset: CGFloat = {
                                        if isThisCardUnlocking {
                                            return -screenHeight * 0.28
                                        } else {
                                            let distance = abs(diff)
                                            return distance * cardHeight * 0.06
                                        }
                                    }()

                                    // Scala: centrale più grande, laterali leggermente più piccole
                                    let scale: CGFloat = {
                                        if isThisCardUnlocking {
                                            return unlockStep == .zoomToCenter ? 1.85 : 0.6
                                        } else if isAnimatingUnlock {
                                            return 0.0
                                        } else {
                                            let distance = abs(diff)
                                            if distance <= 1.0 {
                                                let t = 1.0 - distance
                                                let smoothT = t * t * (3 - 2 * t)
                                                return 0.80 + (smoothT * 0.20) // 0.80 → 1.0
                                            } else {
                                                return max(0.65, 0.80 - (distance - 1.0) * 0.08)
                                            }
                                        }
                                    }()

                                    // Opacità dinamica
                                    let opacity: Double = {
                                        if isThisCardUnlocking {
                                            return unlockStep == .zoomToCenter ? 1.0 : 0.0
                                        } else {
                                            if isAnimatingUnlock { return 0.0 }
                                            let absDiff = abs(diff)
                                            if absDiff <= 1.5 { return 1.0 }
                                            return Double(max(0.0, 1.0 - (absDiff - 1.5) * 1.0))
                                        }
                                    }()

                                    // NIENTE rotationZ né rotationY — carte sempre frontali
                                    let isUnlocked = duplicatesInPack.contains(cardName) || revealedCards.contains(cardName) || sessionFoundCards.contains(cardName)
                                    let showGreenBorder = isThisCardUnlocking || isUnlocked
                                    let cardScale = cardWidth / 111.0
 
                                    ScannerCardView(name: cardName, width: cardWidth, height: cardHeight)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: cardCorner)
                                                .stroke(Color(hex: "6DB832"), lineWidth: showGreenBorder ? (isThisCardUnlocking ? 1.5 : 1.0) : 0)
                                                .padding(-6)
                                                .shadow(color: Color(hex: "6DB832").opacity(showGreenBorder ? 0.85 : 0), radius: 10, x: 0, y: 0)
                                        )
                                        .overlay(alignment: .topTrailing) {
                                            if isThisCardUnlocking {
                                                if showUnlockCheckmark {
                                                    Image("check")
                                                        .resizable()
                                                        .padding(4.5 * cardScale)
                                                        .frame(width: 50 * cardScale, height: 50 * cardScale)
                                                        .offset(x: 20 * cardScale, y: -25 * cardScale)
                                                        .transition(.scale.combined(with: .opacity))
                                                }
                                            } else if isUnlocked {
                                                Image("check")
                                                    .resizable()
                                                    .padding(5 * cardScale)
                                                    .frame(width: 55 * cardScale, height: 55 * cardScale)
                                                    .offset(x: 20 * cardScale, y: -20 * cardScale)
                                            }
                                        }
                                        .shadow(
                                            color: isThisCardUnlocking ? Color(hex: "4CD964").opacity(0.7) : (selectedTargetCard == cardName ? .white.opacity(0.25) : .black.opacity(0.5)),
                                            radius: isThisCardUnlocking ? 28 : (selectedTargetCard == cardName ? 18 : 6)
                                        )
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            guard !isAnimatingUnlock, opacity > 0 else { return }
                                            HapticManager.shared.triggerImpact(style: .medium)
                                            
                                            // Tapping changes target selection and smoothly moves the carousel to center this card!
                                            let targetIndex = displayCards.firstIndex(of: cardName) ?? 0
                                            withAnimation(.spring(response: 0.38, dampingFraction: 0.75)) {
                                                selectedTargetCard = cardName
                                                carouselOffset = CGFloat(targetIndex)
                                                isTargetUnlocked = revealedCards.contains(cardName) || duplicatesInPack.contains(cardName) || sessionFoundCards.contains(cardName)
                                                detectedArtwork = isTargetUnlocked ? "" : "Find the artwork to unlock it!"
                                            }
                                        }
                                        .allowsHitTesting(!isAnimatingUnlock && opacity > 0)
                                        .scaleEffect(scale, anchor: .bottom)
                                        .offset(x: xOffset, y: yOffset)
                                        .opacity(opacity)
                                        .zIndex(isThisCardUnlocking ? 100 : Double(20 - abs(diff)))
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
                                        
                                        // Update active selection to the one closest to the center dynamically during drag
                                        let cardStep = cardWidth * 0.28
                                        let dragSteps = -value.translation.width / cardStep
                                        let activeOffset = max(0.0, min(CGFloat(displayCards.count - 1), carouselOffset + dragSteps))
                                        let newIndex = Int(activeOffset.rounded())
                                        if newIndex >= 0 && newIndex < displayCards.count {
                                            let newCard = displayCards[newIndex]
                                            if selectedTargetCard != newCard {
                                                HapticManager.shared.triggerSelection()
                                                selectedTargetCard = newCard
                                                isTargetUnlocked = revealedCards.contains(newCard) || duplicatesInPack.contains(newCard) || sessionFoundCards.contains(newCard)
                                                detectedArtwork = isTargetUnlocked ? "" : "Find the artwork to unlock it!"
                                            }
                                        }
                                    }
                                    .onEnded { value in
                                        guard !isAnimatingUnlock else { return }
                                        let cardStep = cardWidth * 0.52
                                        
                                        // Calculate drag steps
                                        let dragSteps = -value.translation.width / cardStep
                                        var steps = Int(dragSteps.rounded())
                                        
                                        let swipeThreshold: CGFloat = 30
                                        if steps == 0 {
                                            if value.predictedEndTranslation.width > swipeThreshold {
                                                steps = -1
                                            } else if value.predictedEndTranslation.width < -swipeThreshold {
                                                steps = 1
                                            }
                                        }
                                        
                                        withAnimation(.spring(response: 0.42, dampingFraction: 0.76)) {
                                            if steps != 0 {
                                                HapticManager.shared.triggerSelection()
                                                let newOffset = max(0.0, min(CGFloat(displayCards.count - 1), carouselOffset + CGFloat(steps)))
                                                carouselOffset = newOffset
                                                
                                                // Automatically select the centered card on scroll
                                                let newIndex = Int(newOffset.rounded())
                                                if newIndex >= 0 && newIndex < displayCards.count {
                                                    selectedTargetCard = displayCards[newIndex]
                                                    isTargetUnlocked = revealedCards.contains(displayCards[newIndex]) || duplicatesInPack.contains(displayCards[newIndex]) || sessionFoundCards.contains(displayCards[newIndex])
                                                    detectedArtwork = isTargetUnlocked ? "" : "Find the artwork to unlock it!"
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
                    .zIndex(isAnimatingUnlock ? 70 : 50)
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
                        VStack(spacing: 8) {
                            Text("CONGRATS!")
                                .font(.custom("Helvetica-BoldOblique", size: 36))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color(hex: "FF7A00"), Color(hex: "FFB800")],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 2)

                            congratsSubtitle
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
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
                                .foregroundStyle(Color(hex: "DD611B"))
                                .multilineTextAlignment(.center)
                                .padding(.top, 8)
                            
                            Text("Are you sure you want to quit the experience?\nYour progress **will be saved**")
                                .font(.system(size: 15, weight: .semibold))
                                .italic()
                                .foregroundStyle(.white.opacity(0.85))
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
                                        .foregroundStyle(.black)
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
                                        .foregroundStyle(.white)
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
                } // End of else block for !isBlocked

                // ── AUTO-KEPT POPUP ──────────────────────────────────────────
                if showAutoKeptPopup {
                    ZStack {
                        Color.black.opacity(0.65)
                            .ignoresSafeArea()
                            .transition(.opacity)

                        VStack(spacing: 24) {
                            Text("WE KEPT 'EM")
                                .font(.system(size: 26, weight: .black))
                                .italic()
                                .foregroundStyle(Color(hex: "FF7A00"))
                                .multilineTextAlignment(.center)
                                .padding(.top, 8)

                            autoKeptMessage
                            .foregroundStyle(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .padding(.horizontal, 16)

                            Button(action: {
                                HapticManager.shared.triggerImpact(style: .light)
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    showAutoKeptPopup = false
                                }
                            }) {
                                Text("NICE, THANKS")
                                    .font(.system(size: 18, weight: .black))
                                    .italic()
                                    .foregroundStyle(.black)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 54)
                                    .background(Capsule().fill(Color(hex: "E5E5EA")))
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
                    .zIndex(160)
                }
            }
            .ignoresSafeArea()
        }
        .onAppear {
            locationManager.startHighAccuracyTracking()

            // Rimosso popup da qui perché viene mostrato in ContentView

            if let active = CardDatabase.getActivePack(), !active.isEmpty {
                let dupes = CardDatabase.getDuplicatesInActivePack()
                let revealed = CardDatabase.getRevealedCards()
                
                // Seleziona la prima carta che non è né rivelata né doppia come target iniziale
                let initialTarget: String
                if let target = active.first(where: { !revealed.contains($0) && !dupes.contains($0) }) {
                    initialTarget = target
                } else if let target = active.first(where: { !dupes.contains($0) }) {
                    initialTarget = target
                } else {
                    initialTarget = active.first ?? ""
                }
                selectedTargetCard = initialTarget
                isTargetUnlocked = revealed.contains(initialTarget) || dupes.contains(initialTarget)
                
                if let idx = active.firstIndex(of: initialTarget) {
                    carouselOffset = CGFloat(idx)
                }

                // Se TUTTE le carte sono già doppie o rivelate: niente da inquadrare,
                // vai in automatico alla collezione dopo un breve momento.
                if CardDatabase.isActivePackAllDuplicates() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        navigateToCollection()
                    }
                }
            }
        }
        .onDisappear {
            locationManager.stopTracking()
        }
        .task {
            // Wait up to 1.5 seconds for location to resolve
            for _ in 0..<15 {
                if locationManager.lastKnownLocation != nil || locationManager.authorizationStatus == .denied || locationManager.authorizationStatus == .restricted {
                    break
                }
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            }
            
            // Now check if blocked
            if !isBlocked || devBypassGeofence {
                await checkAndDownloadImages()
            }
        }
        .onChange(of: triggerUnlockAnimation) { _, newValue in
            if let cardName = newValue {
                startUnlockAnimation(for: cardName)
            }
        }
        .onChange(of: devBypassGeofence) { _, newValue in
            if newValue {
                Task {
                    await checkAndDownloadImages()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            autoSaveSessionCards()
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
            detectedArtwork = isTargetUnlocked ? "" : "Find the artwork to unlock it!"
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

        showUnlockCheckmark = false

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

        // Delay showing the checkmark to match Frame 3 transition
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                showUnlockCheckmark = true
            }
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
                    showUnlockCheckmark = false
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
                            if let idx = activePack.firstIndex(of: nextTarget) {
                                carouselOffset = CGFloat(idx)
                            }
                        }
                    }
                }
            }
        }
    }

    private func checkAndDownloadImages() async {
        // If blocked, don't download yet
        if isBlocked && !devBypassGeofence && locationManager.lastKnownLocation != nil {
            return
        }
        
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
                imagesReady = false
                downloadProgress = "Downloading \(missing.count) images..."
            }
            await CardDatabase.downloadImages(for: missing)
            await MainActor.run {
                downloadProgress = "Ready!"
            }
        }

        await MainActor.run {
            imagesReady = true
        }
    }

    private func autoSaveSessionCards() {
        guard !sessionFoundCards.isEmpty else { return }
        let count = sessionFoundCards.count
        for name in sessionFoundCards {
            CardDatabase.addRevealedCard(name)
        }
        // Rimossa l'impostazione di recentlyCompletedPackCards per non triggerare l'animazione nella collezione
        CardDatabase.clearActivePackIfNeeded()
        sessionFoundCards.removeAll()
        UserDefaults.standard.set(count, forKey: "autoKeptCardsCount")
    }

    private func geofenceWarningOverlay(geometry: GeometryProxy) -> some View {
        let screenWidth = geometry.size.width
        let screenHeight = geometry.size.height
        let safeTop = geometry.safeAreaInsets.top
        
        return ZStack(alignment: .bottom) {
            // Dark background base
            LinearGradient(
                colors: [Color(hex: "06080B"), Color(hex: "0D111F")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            // Grid lines overlay
            GridBackground()
                .opacity(0.3)
            
            // Subtle orange bottom glow
            VStack {
                Spacer()
                LinearGradient(
                    colors: [Color(hex: "DD611B").opacity(0.15), Color.clear],
                    startPoint: .bottom,
                    endPoint: .top
                )
                .frame(height: screenHeight * 0.25)
            }
            .ignoresSafeArea()
            
            // Bottom Overlapping Museum Packets (larger, zoomed in, and lower down)
            ZStack(alignment: .bottom) {
                // Background packet
                Image(activeMuseum?.packetImageName ?? "capodimonte_pacchetto")
                    .resizable()
                    .scaledToFit()
                    .frame(width: screenWidth * 0.70)
                    .rotationEffect(.degrees(-8))
                    .offset(x: -screenWidth * 0.18, y: screenHeight * 0.14)
                    .opacity(0.65)
                
                // Foreground packet
                Image(activeMuseum?.packetImageName ?? "capodimonte_pacchetto")
                    .resizable()
                    .scaledToFit()
                    .frame(width: screenWidth * 0.80)
                    .rotationEffect(.degrees(5))
                    .offset(x: screenWidth * 0.14, y: screenHeight * 0.10)
            }
            .frame(width: screenWidth, height: screenHeight * 0.40, alignment: .bottom)
            .ignoresSafeArea(edges: .bottom)
            
            // Main UI content overlay
            VStack(alignment: .leading, spacing: 0) {
                // Header Row (Back button)
                HStack {
                    Button(action: {
                        HapticManager.shared.triggerImpact(style: .light)
                        withAnimation(.easeInOut(duration: 0.35)) {
                            activeView = .opening
                        }
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color(hex: "383838")))
                    }
                    
                    Spacer()
                }
                .padding(.top, safeTop + 12)
                .padding(.horizontal, 24)
                
                Spacer().frame(height: screenHeight * 0.08)
                
                // OOOPS... Badge
                Text("OOOPS...")
                    .font(.custom("Helvetica-BoldOblique", size: 11))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color(hex: "6CD01B")) // Neon green
                            .shadow(color: Color(hex: "6CD01B").opacity(0.4), radius: 6)
                    )
                    .padding(.horizontal, 24)
                
                Spacer().frame(height: 20)
                
                // Title
                Text("LOOKS LIKE YOU’RE\nNOT AT THE MUSEUM\n(YET)")
                    .font(.custom("Helvetica-BoldOblique", size: 26))
                    .lineSpacing(4)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "FF7A00"), Color(hex: "FFB800")],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .padding(.horizontal, 24)
                
                Spacer().frame(height: 24)
                
                // Subtitle / Description
                if locationManager.authorizationStatus == .denied || locationManager.authorizationStatus == .restricted {
                    Text("Location services are required to verify you are at the museum. Please enable location permissions in Settings.")
                        .font(.custom("Helvetica", size: 12))
                        .lineSpacing(2)
                        .foregroundStyle(.white.opacity(0.65))
                        .padding(.horizontal, 24)
                } else {
                    Text("Remember! Keepsy lets you find and collect artworks whenever you're **inside** the museum. Plan your visit and Keep'em all!")
                        .font(.custom("Helvetica", size: 14))
                        .lineSpacing(2)
                        .foregroundStyle(.white.opacity(0.65))
                        .padding(.horizontal, 24)
                }
                
                // MARK: - GUEST MODE (DEV ONLY)
                // TODO: Remove this entire block before production if no longer needed
                #if DEBUG
                Spacer().frame(height: 16)
                Button(action: {
                    HapticManager.shared.triggerImpact(style: .light)
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                        devBypassGeofence = true
                    }
                }) {
                    Text("Guest Mode")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(width: 110, height: 32)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                }
                .frame(maxWidth: .infinity, alignment: .center)
                #endif
                
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
            DispatchQueue.main.async {
                onDiagnosticMessageUpdated("No images downloaded! (\(totalKnown) total on server). Open the collection first.")
            }
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
                onDiagnosticMessageUpdated("✅ ARKit ready: \(dynamicImages.count)/\(totalKnown) images loaded.")
            } else if let fallbackImages = ARReferenceImage.referenceImages(inGroupNamed: "AR Resources", bundle: nil) {
                configuration.trackingImages = fallbackImages
                configuration.maximumNumberOfTrackedImages = 1
                onDiagnosticMessageUpdated("Using \(fallbackImages.count) base images from Xcode.")
            } else {
                onDiagnosticMessageUpdated("❌ No images found on the device!")
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
                    DispatchQueue.main.async {
                        onArtworkDetected(name)
                        onDiagnosticMessageUpdated("Found: \(name)!")
                    }
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
                self.parent.onDiagnosticMessageUpdated("Found: \(dbName)!")
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
                    self.parent.onDiagnosticMessageUpdated("Found: \(dbName)!")
                }
            }
        }
    }
}
