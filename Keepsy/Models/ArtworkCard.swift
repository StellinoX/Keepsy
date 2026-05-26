import SwiftUI

struct ArtworkCard: Identifiable {
    let id = UUID()
    let name: String
    let imageName: String
    var imageUrl: URL? = nil
    var description: String? = nil
    let gradient: LinearGradient
    var isFlipped: Bool = false
}

enum PackState {
    case selecting
    case tearing
    case opened
}
