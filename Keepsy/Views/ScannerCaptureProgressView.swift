import SwiftUI

struct ScannerCaptureProgressView: View {
    let progress: Double

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(.black.opacity(0.45))
                Circle().stroke(.white.opacity(0.2), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color(hex: "F1B40A"), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(progress > 0 ? .linear(duration: 0.06) : nil, value: progress)
                Image(systemName: "lock.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 82, height: 82)
            VStack(spacing: 5) {
                Text("Unlocking…")
                    .font(.system(size: 18, weight: .bold))
                Text("Keep the artwork in frame")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.8), radius: 4)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Keep the artwork in frame"))
        .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
    }
}
