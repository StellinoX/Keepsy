import SwiftUI

struct ArtworkScanDetailView: View {
    let artworkName: String
    let animationSequence: Int?
    let showsDetails: Bool
    let onDismiss: () -> Void

    @State private var isExpanded = false
    @State private var descriptionScrollPosition = ScrollPosition(edge: .top)

    private var artwork: NetworkArtwork? {
        CardDatabase.remoteArtworks[artworkName]
    }

    private var categoryName: LocalizedStringKey {
        guard let artist = artwork?.artist?.lowercased() else { return "Collection" }

        if artist.contains("degas") || artist.contains("manet") || artist.contains("monet") || artist.contains("renoir") {
            return "Impressionism"
        }
        if artist.contains("caravaggio") || artist.contains("ribera") || artist.contains("giordano") || artist.contains("solimena") {
            return "Baroque"
        }
        if artist.contains("tiziano") || artist.contains("raffaello") || artist.contains("michelangelo") || artist.contains("bellini") || artist.contains("parmigianino") {
            return "Renaissance"
        }
        return "Classical Art"
    }

    private var title: String {
        artwork?.title ?? CardDatabase.cleanedArtworkName(artworkName)
    }

    private var artistAndDate: String {
        [artwork?.artist, artwork?.date]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: "; ")
    }

    var body: some View {
        GeometryReader { geometry in
            let screenHeight = geometry.size.height
            let collapsedHeight = min(max(165, screenHeight * 0.215), screenHeight * 0.4)
            let expandedHeight = screenHeight * 0.5
            let sheetTop = screenHeight - (isExpanded ? expandedHeight : collapsedHeight)
            let surfaceHeight = screenHeight + expandedHeight
            let cardWidth = min(geometry.size.width * 0.67, screenHeight * 0.32)

            ZStack(alignment: .bottom) {
                if showsDetails {
                    Button(action: dismiss) {
                        Color.clear
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close artwork details")
                }

                ScannedArtworkCard(
                    name: artworkName,
                    width: cardWidth,
                    animationSequence: animationSequence
                )
                .rotationEffect(.degrees(-4))
                .scaleEffect(isExpanded ? 0.86 : 1)
                .position(x: geometry.size.width / 2, y: screenHeight * (isExpanded ? 0.38 : 0.455))
                .animation(.spring(response: 0.45, dampingFraction: 0.82), value: isExpanded)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

                if showsDetails {
                    infoSheet(contentHeight: expandedHeight, surfaceHeight: surfaceHeight)
                        .modifier(ArtworkDetailsSheetDrag(isExpanded: $isExpanded, onDismiss: dismiss))
                        .padding(.horizontal, geometry.size.width * 0.032)
                        .position(x: geometry.size.width / 2, y: sheetTop + surfaceHeight / 2)
                        .transition(.offset(y: collapsedHeight))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .transition(.opacity)
    }

    private func infoSheet(contentHeight: CGFloat, surfaceHeight: CGFloat) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 42, topTrailingRadius: 42)

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(ArtworkDetailsSheetDrag.settleAnimation) {
                    isExpanded.toggle()
                }
            } label: {
                Capsule()
                    .fill(.white.opacity(0.16))
                    .frame(width: 26, height: 4)
                    .padding(.top, 14)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44, alignment: .top)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? Text("Collapse artwork details") : Text("Expand artwork details"))

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(categoryName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.14), in: Capsule())
                        .padding(.bottom, 10)

                    Text(title)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .accessibilityAddTraits(.isHeader)

                    if !artistAndDate.isEmpty {
                        Text(artistAndDate)
                            .font(.subheadline.bold().italic())
                            .foregroundStyle(.white.opacity(0.92))
                            .padding(.top, 4)
                    }

                    Group {
                        if let description = artwork?.description, !description.isEmpty {
                            Text(description)
                        } else {
                            Text("No description available for this artwork")
                        }
                    }
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.76))
                    .padding(.top, 16)
                    .accessibilityHidden(!isExpanded)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 29)
                .padding(.bottom, 38)
            }
            .scrollIndicators(.hidden)
            .scrollDisabled(!isExpanded)
            .scrollPosition($descriptionScrollPosition)
            .onChange(of: isExpanded) { _, isExpanded in
                if !isExpanded {
                    withAnimation(ArtworkDetailsSheetDrag.settleAnimation) {
                        descriptionScrollPosition.scrollTo(edge: .top)
                    }
                }
            }
        }
        .frame(height: contentHeight)
        // Keep the panel below the viewport throughout the drag without resizing the scroll view.
        .frame(height: surfaceHeight, alignment: .top)
        .background {
            shape.fill(
                LinearGradient(
                    colors: [Color(hex: "232323"), Color(hex: "151515")],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: surfaceHeight > 0 ? contentHeight / surfaceHeight : 1)
                )
            )
        }
        .overlay {
            shape.strokeBorder(.white.opacity(0.5), lineWidth: 1.5)
                .allowsHitTesting(false)
        }
        .clipShape(shape)
        .shadow(color: .black.opacity(0.45), radius: 20, y: -4)
        .accessibilityAction(.escape, dismiss)
    }

    private func dismiss() {
        HapticManager.shared.triggerImpact(style: .light)
        onDismiss()
    }
}

private struct ScannedArtworkCard: View {
    let name: String
    let width: CGFloat
    let animationSequence: Int?

    var body: some View {
        let outlineColor = Color(hex: "A5D758")
        let badgeSize = width * 0.38
        let startsRevealed = animationSequence == nil

        ScannerCardView(
            name: name,
            width: width,
            height: width * (168.0 / 111.0),
            isRevealed: true
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 23)
                .stroke(outlineColor, lineWidth: 1.5)
                .padding(-10)
                .shadow(color: outlineColor.opacity(0.45), radius: 8)
        }
        .overlay(alignment: .topTrailing) {
            Image("check")
                .resizable()
                .frame(width: badgeSize, height: badgeSize)
                .offset(x: badgeSize / 2 + 3, y: -badgeSize / 2 - 3)
                .keyframeAnimator(initialValue: startsRevealed ? 1.0 : 0.0, trigger: animationSequence) { view, value in
                    view.scaleEffect(value).opacity(value)
                } keyframes: { _ in
                    KeyframeTrack {
                        LinearKeyframe(0.0, duration: 0.7)
                        SpringKeyframe(1.0, duration: 0.35, spring: .init(response: 0.35, dampingRatio: 0.6))
                    }
                }
        }
        .shadow(color: .black.opacity(0.45), radius: 18, y: 10)
        .keyframeAnimator(
            initialValue: startsRevealed ? (scale: 1.0, opacity: 1.0) : (scale: 0.6, opacity: 0.0),
            trigger: animationSequence
        ) { view, value in
            view.scaleEffect(value.scale).opacity(value.opacity)
        } keyframes: { _ in
            KeyframeTrack(\.scale) {
                SpringKeyframe(1.0, duration: 0.5, spring: .init(response: 0.5, dampingRatio: 0.65))
            }
            KeyframeTrack(\.opacity) {
                LinearKeyframe(1.0, duration: 0.15)
            }
        }
    }
}
