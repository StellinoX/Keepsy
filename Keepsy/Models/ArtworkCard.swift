import SwiftUI

struct ArtworkCard: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let imageName: String
    
    var imageUrl: URL? {
        if let urlString = CardDatabase.remoteArtworks[name]?.imageUrl {
            return URL(string: urlString)
        }
        return nil
    }
    
    var description: String? {
        return CardDatabase.remoteArtworks[name]?.description
    }
    
    let gradient: LinearGradient
    var isFlipped: Bool = false
    static func == (lhs: ArtworkCard, rhs: ArtworkCard) -> Bool {
        return lhs.name == rhs.name && lhs.isFlipped == rhs.isFlipped
    }
}

enum PackState {
    case selecting
    case tearing
    case opened
}
