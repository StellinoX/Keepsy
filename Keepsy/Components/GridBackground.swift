import SwiftUI

struct GridBackground: View {
    var body: some View {
        GeometryReader { geo in
            Path { path in
                // Vertical lines (horizontal step: 68, starting offset: 28.5)
                let startX: CGFloat = 28.5
                let stepX: CGFloat = 68
                var x = startX
                while x <= geo.size.width + stepX {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: geo.size.height))
                    x += stepX
                }
                
                // Horizontal lines (vertical step: 118, starting offset: 25.08)
                let startY: CGFloat = 25.08
                let stepY: CGFloat = 118
                var y = startY
                while y <= geo.size.height + stepY {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geo.size.width, y: y))
                    y += stepY
                }
            }
            .stroke(Color.blue.opacity(0.08), lineWidth: 1)
        }
    }
}
