import SwiftUI
import UIKit

struct CardDatabase {
    private static let cacheKey = "CachedRemoteArtworks"
    
    // Cache for artworks fetched from the cloud, immediately populated on app launch
    static var remoteArtworks: [String: NetworkArtwork] = loadFromCache()
    
    private static func loadFromCache() -> [String: NetworkArtwork] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let decoded = try? JSONDecoder().decode([String: NetworkArtwork].self, from: data) else {
            return [:]
        }
        return decoded
    }
    
    private static func saveToCache(_ dict: [String: NetworkArtwork]) {
        if let encoded = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(encoded, forKey: cacheKey)
        }
    }
    
    static func syncWithCloud() async {
        do {
            let fetched = try await NetworkService.shared.fetchArtworks()
            var dict: [String: NetworkArtwork] = [:]
            for art in fetched {
                dict[art.internalName] = art
            }
            
            DispatchQueue.main.async {
                remoteArtworks = dict
                saveToCache(dict)
                // Automatically prefetch images after updating the cache
                prefetchImages(for: "Capodimonte")
            }
            
            print("Successfully synced \(fetched.count) artworks from cloud API")
        } catch {
            print("Failed to sync artworks: \(error)")
        }
    }
    
    // MARK: - Local Image Caching
    
    private static var artworksDirectoryURL: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let docDir = paths[0].appendingPathComponent("Artworks", isDirectory: true)
        if !FileManager.default.fileExists(atPath: docDir.path) {
            try? FileManager.default.createDirectory(at: docDir, withIntermediateDirectories: true)
        }
        return docDir
    }

    static func localImage(for name: String) -> UIImage? {
        // 1. Fallback to bundle assets if available
        if let img = UIImage(named: name) {
            return img
        }
        
        // 2. Check local pre-fetched directory
        let fileURL = artworksDirectoryURL.appendingPathComponent("\(name).jpg")
        if let data = try? Data(contentsOf: fileURL), let img = UIImage(data: data) {
            return img
        }
        
        return nil
    }

    static func prefetchImages(for location: String) {
        // In this MVP, we just fetch all available artworks.
        let artworks = Array(remoteArtworks.keys)
        Task {
            await withTaskGroup(of: Void.self) { group in
                for name in artworks {
                    group.addTask {
                        if let urlString = remoteArtworks[name]?.imageUrl, let url = URL(string: urlString) {
                            let fileURL = artworksDirectoryURL.appendingPathComponent("\(name).jpg")
                            // Skip if already downloaded
                            if FileManager.default.fileExists(atPath: fileURL.path) { return }
                            
                            if let (data, _) = try? await URLSession.shared.data(from: url) {
                                try? data.write(to: fileURL)
                                print("Prefetched image for \(name) to local disk")
                            }
                        }
                    }
                }
            }
        }
    }
    
    static func artworksFor(location: String) -> [String] {
        return Array(remoteArtworks.keys).sorted()
    }
    
    static var allArtworkNames: [String] {
        return Array(remoteArtworks.keys).sorted()
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
