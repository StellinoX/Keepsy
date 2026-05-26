import SwiftUI
import UIKit

struct CardDatabase {
    static let capodimonteArtworks = [
        "A_Boy_Blowing_on_an_Ember_to_Light_a_Candle__Sopl_n_", "Alfonso_II_of_Aragon", 
        "Asdrubale_Bitten_by_a_Crawfish", "Bishop_Bernardo_de__Rossi", "Bust_of_Pope_Paul_III", 
        "Cardinal_Alessandro_Farnese", "Charles_III_at_St_Peter_s", "Dana_", "Flagellation", 
        "Judith_Beheading_Holofernes", "Pope_Paul_III", "Portrait_of_a_Girl",
        "Abduction_Scene", "Allegory_of_the_Night", "Altar_of_St_Louis_of_Toulouse", 
        "Blessing_Christ", "Composite_Head", "Crucifixion", "Giulio_Clovio", 
        "Madonna_Enthroned_with_Saints", "Madonna_and_Child_and_Two_Angels", 
        "Madonna_del_Divino_Amore__Madonna_of_Divine_Love_", "Piet_",
        "Absalom_s_Feast", "Annunciation_to_the_Shepherds", "Christ_Served_by_Angels", 
        "Flowers", "Founding_of_Santa_Maria_Maggiore", "Pope_Clement_VII", 
        "The_Misanthrope", "The_Parable_of_the_Blind_Leading_the_Blind", 
        "View_of_Campo_Santi_Giovanni_e_Paolo", "Vision_of_St_Bruno", "St_Sebastian"
    ]
    
    static func artworksFor(location: String) -> [String] {
        return capodimonteArtworks
    }
    
    static var allArtworkNames: [String] {
        return capodimonteArtworks
    }
    
    static let orangeGradient = LinearGradient(colors: [Color(hex: "DD8812"), Color(hex: "DE611B")], startPoint: .top, endPoint: .bottom)
    static let goldGradient = LinearGradient(colors: [Color(hex: "F2AB49"), Color(hex: "D48F2A")], startPoint: .top, endPoint: .bottom)
    static let silverGradient = LinearGradient(colors: [Color(hex: "C0C0C0"), Color(hex: "8E8E93")], startPoint: .top, endPoint: .bottom)
    static let purpleGradient = LinearGradient(colors: [Color(hex: "6A1B9A"), Color(hex: "4A148C")], startPoint: .top, endPoint: .bottom)
    
    static let allGradients = [orangeGradient, goldGradient, silverGradient, purpleGradient]
    
    // Restituisce un gradiente pseudo-casuale stabile basato sul nome, in modo che 
    // nella collezione la carta abbia sempre lo stesso aspetto.
    static func gradientFor(name: String) -> LinearGradient {
        let hash = abs(name.hashValue)
        return allGradients[hash % allGradients.count]
    }
    
    static func borderGradientFor(name: String) -> LinearGradient {
        return gradientFor(name: name)
    }
    
    static func colorsFor(name: String) -> [UIColor] {
        let hash = abs(name.hashValue)
        let colors = [
            [UIColor(Color(hex: "DD8812")), UIColor(Color(hex: "DE611B"))],
            [UIColor(Color(hex: "F2AB49")), UIColor(Color(hex: "D48F2A"))],
            [UIColor(Color(hex: "C0C0C0")), UIColor(Color(hex: "8E8E93"))],
            [UIColor(Color(hex: "6A1B9A")), UIColor(Color(hex: "4A148C"))]
        ]
        return colors[hash % colors.count]
    }
    
    static func getActivePack() -> [String]? {
        return UserDefaults.standard.stringArray(forKey: "activePackCards")
    }
    
    static func hasActivePack() -> Bool {
        guard let active = getActivePack(), !active.isEmpty else {
            return false
        }
        let revealed = getRevealedCards()
        return !active.allSatisfy { revealed.contains($0) }
    }
    
    static func clearActivePackIfNeeded() {
        if let active = getActivePack(), !active.isEmpty {
            let revealed = getRevealedCards()
            if active.allSatisfy({ revealed.contains($0) }) {
                UserDefaults.standard.removeObject(forKey: "activePackCards")
                UserDefaults.standard.removeObject(forKey: "activePackTearMask")
            }
        }
    }
    
    // Gestione salvataggio carte trovate nei pacchetti (pixelate)
    static func addFoundCards(_ names: [String]) {
        var found = getFoundCards()
        for name in names {
            found.insert(name)
        }
        UserDefaults.standard.set(Array(found), forKey: "FoundCards")
    }
    
    static func getFoundCards() -> Set<String> {
        if let saved = UserDefaults.standard.stringArray(forKey: "FoundCards") {
            return Set(saved)
        }
        return []
    }
    
    // Gestione salvataggio carte riconosciute in AR (chiare)
    static func addRevealedCard(_ name: String) {
        var revealed = getRevealedCards()
        revealed.insert(name)
        UserDefaults.standard.set(Array(revealed), forKey: "RevealedCards")
        
        // Assicuriamoci che se è rivelata, sia anche marcata come trovata
        addFoundCards([name])
    }
    
    static func getRevealedCards() -> Set<String> {
        if let saved = UserDefaults.standard.stringArray(forKey: "RevealedCards") {
            return Set(saved)
        }
        return []
    }
}

// Spostata qui da PackOpeningView per renderla accessibile in tutta l'app
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}
