import SwiftUI
import UIKit
import ARKit

struct CardDatabase {
    private static let cacheKey = "CachedRemoteArtworks"
    
    // Cache for artworks fetched from the cloud, immediately populated on app launch.
    // Backing storage is guarded by `dictLock` because it is read from background threads
    // (AR delegate, image loaders) while syncWithCloud writes it. Unprotected concurrent
    // access to a Swift Dictionary traps with EXC_BREAKPOINT (exclusivity violation).
    private static let dictLock = NSLock()
    private static var _remoteArtworks: [String: NetworkArtwork] = loadFromCache()
    private static var _artworksByMuseum: [String: [String]] = loadMuseumMapFromCache()

    static var remoteArtworks: [String: NetworkArtwork] {
        get { dictLock.lock(); defer { dictLock.unlock() }; return _remoteArtworks }
        set { dictLock.lock(); _remoteArtworks = newValue; dictLock.unlock() }
    }
    static var artworksByMuseum: [String: [String]] {
        get { dictLock.lock(); defer { dictLock.unlock() }; return _artworksByMuseum }
        set { dictLock.lock(); _artworksByMuseum = newValue; dictLock.unlock() }
    }
    
    private static let mapCacheKey = "CachedMuseumMap"
    private static var lastSyncTime: Date? = nil
    
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
        if let lastSync = lastSyncTime, Date().timeIntervalSince(lastSync) < 30 {
            // print("ℹ️ syncWithCloud saltato: sincronizzato di recente (\(Int(Date().timeIntervalSince(lastSync))) secondi fa)")
            return
        }
        
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
            
            DispatchQueue.main.async {
                remoteArtworks = allArtworks
                artworksByMuseum = museumMap
                saveToCache(allArtworks, map: museumMap)
            }
            
            lastSyncTime = Date()
            // print("Successfully synced all museums from cloud APIs")
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

    // Nonisolated helper for heavy disk I/O and JPEG decoding
    nonisolated static func loadLocalImageFromDisk(for name: String) -> UIImage? {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let docDir = paths[0].appendingPathComponent("Artworks", isDirectory: true)
        let fileURL = docDir.appendingPathComponent("\(name).jpg")
        
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            return nil
        }
        
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, options) else { return nil }
        
        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 800
        ] as CFDictionary
        
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    static func localImage(for name: String) -> UIImage? {
        // 0. Check memory cache first
        if let cached = imageCache.object(forKey: name as NSString) {
            return cached
        }
        
        // 1. Fallback to bundle assets if available
        if let img = UIImage(named: name) {
            return img
        }
        
        // 2. Check local pre-fetched directory (blocks current thread)
        if let finalImage = loadLocalImageFromDisk(for: name) {
            imageCache.setObject(finalImage, forKey: name as NSString)
            return finalImage
        }
        
        return nil
    }
    
    static func localImageAsync(for name: String) async -> UIImage? {
        if let cached = imageCache.object(forKey: name as NSString) {
            return cached
        }
        
        let bundleImg = await MainActor.run { UIImage(named: name) }
        if let img = bundleImg {
            return img
        }
        
        if let finalImage = loadLocalImageFromDisk(for: name) {
            imageCache.setObject(finalImage, forKey: name as NSString)
            return finalImage
        }
        
        return nil
    }
    
    // Returns CGImage properly formatted for ARKit (bakes EXIF rotation and scales to a safe 512px)
    static func rawCGImage(for name: String) async -> CGImage? {
        // 1. Fallback to bundle assets if available
        let bundleImage = await MainActor.run { UIImage(named: name)?.cgImage }
        if let cgImage = bundleImage {
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
        await syncWithCloud()
    }

    static func prefetchImages(for location: String) async {
        // All artwork images are already downloaded and cached during syncWithCloud() at launch
    }
    
    // Cache per le immagini ARKit, così ARArtworkView si carica all'istante dopo la prima volta
    static let arImageCache = NSCache<NSString, ARReferenceImage>()
    
    static func arReferenceImage(for name: String) async -> ARReferenceImage? {
        if let cached = arImageCache.object(forKey: name as NSString) {
            return cached
        }

        guard let cgImage = await rawCGImage(for: name) else { return nil }

        // physicalWidthMeters reads remoteArtworks, now guarded by dictLock — safe from any thread.
        let physicalWidth = physicalWidthMeters(for: name)
        let refImage = ARReferenceImage(cgImage, orientation: .up, physicalWidth: physicalWidth)
        refImage.name = name

        arImageCache.setObject(refImage, forKey: name as NSString)
        return refImage
    }
    
    /// Safely performs ARReferenceImage validation in a nonisolated context,
    /// preventing compiler-inserted `@MainActor` queue assertions on background callbacks.
    nonisolated static func validateARImage(_ refImage: ARReferenceImage, name: String) {
        refImage.validate { error in
            if let error = error {
                print("⚠️ ARKit Validation Error for \(name): \(error.localizedDescription)")
            }
        }
    }

    // Parses "Misure senza cornice: 83x65x5,5 cm" → 0.83m.
    // Falls back to 0.5m (reasonable average for museum paintings) if unparseable.
    private static func physicalWidthMeters(for name: String) -> CGFloat {
        guard let dimensions = remoteArtworks[name]?.dimensions, !dimensions.isEmpty else {
            return 0.5
        }
        // Find first integer/decimal number in the string
        let pattern = #"(\d+(?:[.,]\d+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: dimensions, range: NSRange(dimensions.startIndex..., in: dimensions)),
              let range = Range(match.range(at: 1), in: dimensions) else {
            return 0.5
        }
        let valueStr = dimensions[range].replacingOccurrences(of: ",", with: ".")
        guard let cm = Double(valueStr), cm > 5 else { return 0.5 }
        // Convert cm to meters, clamp to sensible museum painting range (0.1–3.0m)
        return CGFloat(min(max(cm / 100.0, 0.1), 3.0))
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
        return true  // Le doppie restano nel pacchetto, non filtrarle
    }
    
    static func clearActivePackIfNeeded() {
        if let active = getActivePack(), !active.isEmpty {
            let revealed = getRevealedCards()
            let dupes = Set(UserDefaults.standard.stringArray(forKey: "activePackDuplicates") ?? [])
            if active.allSatisfy({ revealed.contains($0) || dupes.contains($0) }) {
                UserDefaults.standard.removeObject(forKey: "activePackCards")
                UserDefaults.standard.removeObject(forKey: "activePackTearMask")
                UserDefaults.standard.removeObject(forKey: "activePackDuplicates")
            }
        }
    }
    
    // MARK: - Duplicate Card Tracking
    
    /// Incrementa il contatore doppie per le carte già possedute quando viene aperto un pacchetto.
    /// Restituisce l'array delle carte che erano doppie.
    @discardableResult
    static func trackDuplicates(in packCards: [String]) -> [String] {
        let revealed = getRevealedCards()
        let found = getFoundCards()
        let alreadyOwned = packCards.filter { revealed.contains($0) || found.contains($0) }
        
        if !alreadyOwned.isEmpty {
            var counts = getDuplicateCounts()
            for name in alreadyOwned {
                counts[name, default: 0] += 1
            }
            saveDuplicateCounts(counts)
        }
        
        return alreadyOwned
    }
    
    /// Restituisce il dizionario [nomeCard: numeroDoppie]
    static func getDuplicateCounts() -> [String: Int] {
        guard let data = UserDefaults.standard.data(forKey: "DuplicateCardCounts"),
              let decoded = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return [:]
        }
        return decoded
    }
    
    private static func saveDuplicateCounts(_ counts: [String: Int]) {
        if let encoded = try? JSONEncoder().encode(counts) {
            UserDefaults.standard.set(encoded, forKey: "DuplicateCardCounts")
        }
    }
    
    /// Restituisce le carte del pacchetto attivo che erano doppie all'apertura.
    /// Legge la lista salvata UNA volta in trackDuplicates (prima di addFoundCards),
    /// NON ricalcola live — altrimenti tutte risultano doppie (addFoundCards aggiunge tutto il pack).
    static func getDuplicatesInActivePack() -> Set<String> {
        guard getActivePack() != nil else { return [] }
        return Set(UserDefaults.standard.stringArray(forKey: "activePackDuplicates") ?? [])
    }
    
    /// True se TUTTE le carte del pacchetto attivo sono già state rivelate (tutte doppie)
    static func isActivePackAllDuplicates() -> Bool {
        guard let pack = getActivePack(), !pack.isEmpty else { return false }
        let revealed = getRevealedCards()
        let dupes = Set(UserDefaults.standard.stringArray(forKey: "activePackDuplicates") ?? [])
        return pack.allSatisfy { revealed.contains($0) || dupes.contains($0) }
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
