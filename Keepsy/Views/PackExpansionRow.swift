import SwiftUI

struct CircularProgressView: View {
    let progress: Double
    var percentText: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 3)
                .frame(width: 32, height: 32)

            Circle()
                .trim(from: 0.0, to: CGFloat(progress))
                .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 32, height: 32)
                .rotationEffect(.degrees(-90))

            Text(percentText)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(width: 32, height: 32)
    }
}

struct CompletedBadgeView: View {
    var x: CGFloat = 0
    var y: CGFloat = 0

    var body: some View {
        let ipadScale = (UIDevice.current.userInterfaceIdiom == .pad) ? 1.4 : 1.0
        Image("check")
            .resizable()
            .padding(3 * ipadScale)
            .frame(width: 62 * ipadScale, height: 62 * ipadScale)
            .offset(x: -17 * ipadScale, y: -17 * ipadScale)
    }
}

struct PackExpansionRow: View {
    let museumId: String
    let title: String
    let progress: Double
    let onTap: () -> Void

    var isComplete: Bool { progress >= 1.0 }
    var percentText: String { "\(Int(round(progress * 100)))%" }

    private var subtitle: String {
        switch museumId {
        case "uffizi":      return "Florence, Italy"
        case "prado":       return "Madrid, Spain"
        case "capodimonte": return "Naples, Italy"
        case "moma":        return "New York, NY"
        default:            return ""
        }
    }

    private var fannedPacketsView: some View {
        let imageName = MuseumConfig.shared.museums.first(where: { $0.id == museumId })?.packetImageName ?? "uffizi_pacchetto"
        let ipadScale = (UIDevice.current.userInterfaceIdiom == .pad) ? 1.4 : 1.0
        return ZStack(alignment: .bottom) {
            Image(imageName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 125 * ipadScale, height: 187 * ipadScale)
                .rotationEffect(.degrees(-12))
                .offset(x: -40 * ipadScale, y: 75 * ipadScale)
                .colorMultiply(isComplete ? Color(white: 0.72) : Color.white)

            Image(imageName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 125 * ipadScale, height: 187 * ipadScale)
                .rotationEffect(.degrees(12))
                .offset(x: 40 * ipadScale, y: 75 * ipadScale)
                .colorMultiply(isComplete ? Color(white: 0.72) : Color.white)

            Image(imageName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 125 * ipadScale, height: 187 * ipadScale)
                .offset(x: 0, y: 65 * ipadScale)
                .colorMultiply(isComplete ? Color(white: 0.72) : Color.white)
        }
    }

    private var headerView: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 2) {
                Text(title.uppercased())
                    .font(.custom("Helvetica-BoldOblique", size: 22))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "FF7A00"), Color(hex: "FFB800")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                Text(subtitle)
                    .font(.custom("Helvetica-Oblique", size: 12))
                    .foregroundColor(Color.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 2)

            HStack(alignment: .center) {
                if isComplete {
                    CompletedBadgeView()
                } else {
                    CircularProgressView(progress: progress, percentText: percentText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.6))
            }
        }
    }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .top) {
                fannedPacketsView
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

                headerView
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
            }
            .frame(height: 220)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(hex: "151517"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1.0)
            )
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: Color.black.opacity(0.55), radius: 30, x: 0, y: 15)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(subtitle)\(isComplete ? ", completed" : ", \(percentText) complete")")
        .accessibilityHint("Double-tap to view collection")
    }
}
