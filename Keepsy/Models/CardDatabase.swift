import SwiftUI
import UIKit

struct CardDatabase {
    private static let cacheKey = "CachedRemoteArtworks"
    
    // Cache for artworks fetched from the cloud, immediately populated on app launch
    static var remoteArtworks: [String: NetworkArtwork] = loadFromCache()
    static var artworksByMuseum: [String: [String]] = loadMuseumMapFromCache()
    
    private static let mapCacheKey = "CachedMuseumMap"
    
    private static func loadFromCache() -> [String: NetworkArtwork] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let decoded = try? JSONDecoder().decode([String: NetworkArtwork].self, from: data) else {
            return [:]
        }
        return decoded
    }
    
    private static func loadMuseumMapFromCache() -> [String: [String]] {
        guard let data = UserDefaults.standard.data(forKey: mapCacheKey),
              let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            return [:]
        }
        return decoded
    }
    
    private static func saveToCache(_ dict: [String: NetworkArtwork], map: [String: [String]]) {
        if let encoded = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(encoded, forKey: cacheKey)
        }
        if let encodedMap = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(encodedMap, forKey: mapCacheKey)
        }
    }
    
    static func syncWithCloud() async {
        do {
            var allArtworks: [String: NetworkArtwork] = [:]
            var museumMap: [String: [String]] = [:]
            
            for museum in MuseumConfig.shared.museums {
                let fetched = try await NetworkService.shared.fetchArtworks(for: museum.id)
                var ids: [String] = []
                for art in fetched {
                    allArtworks[art.internalName] = art
                    ids.append(art.internalName)
                }
                museumMap[museum.id] = ids.sorted()
            }
            
            // Run image prefetching silently in the background
            let activeCity = UserDefaults.standard.string(forKey: "currentCity") ?? "capodimonte"
            Task.detached(priority: .background) {
                await prefetchImages(for: activeCity.lowercased())
            }
            
            DispatchQueue.main.async {
                remoteArtworks = allArtworks
                artworksByMuseum = museumMap
                saveToCache(allArtworks, map: museumMap)
            }
            
            print("Successfully synced all museums from cloud APIs")
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

    // Cache in memory for images to prevent lag during animations
    static let imageCache = NSCache<NSString, UIImage>()

    static func localImage(for name: String) -> UIImage? {
        // 0. Check memory cache first
        if let cached = imageCache.object(forKey: name as NSString) {
            return cached
        }
        
        // 1. Fallback to bundle assets if available
        if let img = UIImage(named: name) {
            return img
        }
        
        // 2. Check local pre-fetched directory
        let fileURL = artworksDirectoryURL.appendingPathComponent("\(name).jpg")
        
        // Efficiently downsample image to prevent OOM memory crashes when loading 9MB files
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, options) else { return nil }
        
        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 800
        ] as CFDictionary
        
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) else { return nil }
        let finalImage = UIImage(cgImage: cgImage)
        
        // Save to memory cache
        imageCache.setObject(finalImage, forKey: name as NSString)
        
        return finalImage
    }
    
    // Returns CGImage properly formatted for ARKit (bakes EXIF rotation and scales to a safe 512px)
    static func rawCGImage(for name: String) -> CGImage? {
        // 1. Fallback to bundle assets if available
        if let img = UIImage(named: name), let cgImage = img.cgImage {
            return cgImage
        }
        
        // 2. Check local pre-fetched directory
        let fileURL = artworksDirectoryURL.appendingPathComponent("\(name).jpg")
        
        // Ensure the file is a valid image size (S3 errors are 263 bytes)
        let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
        guard size > 10000 else {
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
        
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, options) else { return nil }
        
        // ARKit requires max ~1000px, so 1024px is perfect for detailed feature matching. EXIF MUST be baked!
        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true, // Crucial: Bakes EXIF rotation!
            kCGImageSourceThumbnailMaxPixelSize: 1024
        ] as CFDictionary
        
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) else {
            // File is corrupted or incomplete — delete it so it gets re-downloaded next time
            try? FileManager.default.removeItem(at: fileURL)
            print("Deleted corrupted image file for: \(name)")
            return nil
        }
        return cgImage
    }

    static func downloadImages(for artworks: [String]) async {
        await withTaskGroup(of: Void.self) { group in
            for name in artworks {
                group.addTask {
                    if let urlString = remoteArtworks[name]?.imageUrl, let url = URL(string: urlString) {
                        let fileURL = artworksDirectoryURL.appendingPathComponent("\(name).jpg")
                        // Skip only if already downloaded AND valid size
                        let existingSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
                        if FileManager.default.fileExists(atPath: fileURL.path) && existingSize > 10000 { return }
                        
                        // Remove any corrupted partial file before re-downloading
                        try? FileManager.default.removeItem(at: fileURL)
                        
                        if let (data, response) = try? await URLSession.shared.data(from: url),
                           let httpResponse = response as? HTTPURLResponse,
                           httpResponse.statusCode == 200,
                           data.count > 10000 {
                            try? data.write(to: fileURL)
                            print("Downloaded image for \(name) (\(data.count) bytes)")
                        } else {
                            print("Failed to download image for \(name) - invalid response or size")
                        }
                    }
                }
            }
        }
    }

    static func prefetchImages(for location: String) async {
        let artworks = artworksByMuseum[location.lowercased()] ?? Array(remoteArtworks.keys)
        
        // Limit concurrency to avoid network timeouts and memory issues (3 at a time)
        let maxConcurrentTasks = 3
        
        await withTaskGroup(of: Void.self) { group in
            var index = 0
            
            // Start initial batch
            while index < min(maxConcurrentTasks, artworks.count) {
                let name = artworks[index]
                if let urlString = remoteArtworks[name]?.imageUrl, let url = URL(string: urlString) {
                    let fileURL = artworksDirectoryURL.appendingPathComponent("\(name).jpg")
                    let existingSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
                    if !FileManager.default.fileExists(atPath: fileURL.path) || existingSize <= 10000 {
                        group.addTask {
                            do {
                                let (tempURL, response) = try await URLSession.shared.download(from: url)
                                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                                    print("Failed prefetch header for \(name)")
                                    return
                                }
                                let size = (try? FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int) ?? 0
                                guard size > 10000 else {
                                    print("Failed prefetch size for \(name)")
                                    return
                                }
                                if FileManager.default.fileExists(atPath: fileURL.path) {
                                    try? FileManager.default.removeItem(at: fileURL)
                                }
                                try FileManager.default.moveItem(at: tempURL, to: fileURL)
                                print("Prefetched image to disk: \(name)")
                            } catch {
                                print("Failed to prefetch \(name): \(error.localizedDescription)")
                            }
                        }
                    }
                }
                index += 1
            }
            
            // Add a new task for each one that completes
            while let _ = await group.next() {
                if index < artworks.count {
                    let name = artworks[index]
                    if let urlString = remoteArtworks[name]?.imageUrl, let url = URL(string: urlString) {
                        let fileURL = artworksDirectoryURL.appendingPathComponent("\(name).jpg")
                        let existingSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
                        if !FileManager.default.fileExists(atPath: fileURL.path) || existingSize <= 10000 {
                            group.addTask {
                                do {
                                    let (tempURL, response) = try await URLSession.shared.download(from: url)
                                    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                                        print("Failed prefetch header for \(name)")
                                        return
                                    }
                                    let size = (try? FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int) ?? 0
                                    guard size > 10000 else {
                                        print("Failed prefetch size for \(name)")
                                        return
                                    }
                                    if FileManager.default.fileExists(atPath: fileURL.path) {
                                        try? FileManager.default.removeItem(at: fileURL)
                                    }
                                    try FileManager.default.moveItem(at: tempURL, to: fileURL)
                                    print("Prefetched image to disk: \(name)")
                                } catch {
                                    print("Failed to prefetch \(name): \(error.localizedDescription)")
                                }
                            }
                        }
                    }
                    index += 1
                }
            }
        }
    }
    
    static func artworksFor(location: String) -> [String] {
        return artworksByMuseum[location.lowercased()] ?? Array(remoteArtworks.keys).sorted()
    }
    
    /// Returns only artworks whose image file is already saved to disk AND is valid (>10KB). Safe to use for ARKit.
    static func downloadedArtworkNames(for location: String) -> [String] {
        let all = artworksFor(location: location)
        let dir = artworksDirectoryURL
        return all.filter { name in
            let path = dir.appendingPathComponent("\(name).jpg").path
            guard FileManager.default.fileExists(atPath: path) else { return false }
            // A valid JPEG is always > 10KB. Anything smaller is a failed/partial download.
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
            return size > 10000
        }
    }
    
    /// Returns the official artwork title from the database, or cleans the raw name as fallback.
    static func cleanedArtworkName(_ name: String) -> String {
        if let artwork = remoteArtworks[name] {
            return artwork.title
        }
        
        var cleaned = name
        if let regexPrefix = try? NSRegularExpression(pattern: "^[0-9]+\\s*-\\s*", options: []) {
            let range = NSRange(location: 0, length: cleaned.utf16.count)
            cleaned = regexPrefix.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
        }
        if let index = cleaned.lowercased().range(of: "_ph.") {
            cleaned = String(cleaned[..<index.lowerBound])
        }
        if let index = cleaned.lowercased().range(of: "_ph_") {
            cleaned = String(cleaned[..<index.lowerBound])
        }
        return cleaned
            .replacingOccurrences(of: "__detail_", with: "")
            .replacingOccurrences(of: "_detail_", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespaces)
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
