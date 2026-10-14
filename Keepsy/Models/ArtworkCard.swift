import SwiftUI

struct ArtworkCard: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let imageName: String
    
    let title: String
    let description: String?
    let imageUrl: URL?
    
    let gradient: LinearGradient
    var isFlipped: Bool = false
    static func == (lhs: ArtworkCard, rhs: ArtworkCard) -> Bool {
        return lhs.id == rhs.id
    }
}

enum PackState {
    case selecting
    case packSelection
    case tearing
    case opened
}
