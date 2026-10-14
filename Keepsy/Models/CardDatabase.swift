import Foundation
import SwiftUI
import UIKit
import ARKit

struct CardDatabase {
    private static let cacheKey = "CachedRemoteArtworks_v3"
    
    // Cache for artworks fetched from the cloud, immediately populated on app launch.
    // Backing storage is guarded by `dictLock` because it is read from background threads
    // (AR delegate, image loaders) while syncWithCloud writes it. Unprotected concurrent
    // access to a Swift Dictionary traps with EXC_BREAKPOINT (exclusivity violation).
    private static let dictLock = NSLock()
    private static var _remoteArtworks: [String: NetworkArtwork] = loadFromCache()
    private static var _artworksByMuseum: [String: [String]] = loadMuseumMapFromCache()

    static var remoteArtworks: [String: NetworkArtwork] {
        get { dictLock.withLock { _remoteArtworks } }
        set { dictLock.withLock { _remoteArtworks = newValue } }
    }
    static var artworksByMuseum: [String: [String]] {
        get { dictLock.withLock { _artworksByMuseum } }
        set { dictLock.withLock { _artworksByMuseum = newValue } }
    }
    
    private static let mapCacheKey = "CachedMuseumMap_v3"
    private static var lastSyncTime: Date? = nil
    
    private static func loadFromCache() -> [String: NetworkArtwork] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let decoded = try? JSONDecoder().decode([String: NetworkArtwork].self, from: data) else {
            return [:]
        }
        
        // Diagnostic migration: if the cache has old keys like "Giulio_Clovio", clear it
        if decoded.keys.contains("Giulio_Clovio") || decoded.keys.contains("Flagellation") {
            UserDefaults.standard.removeObject(forKey: cacheKey)
            UserDefaults.standard.removeObject(forKey: mapCacheKey)
            
            // Also clean up all active packs to prevent crash/inconsistency
            for museum in MuseumConfig.shared.museums {
                UserDefaults.standard.removeObject(forKey: "activePackCards_\(museum.id)")
                UserDefaults.standard.removeObject(forKey: "activePackTearMask_\(museum.id)")
                UserDefaults.standard.removeObject(forKey: "activePackDuplicates_\(museum.id)")
            }
            UserDefaults.standard.removeObject(forKey: "activePackCards")
            UserDefaults.standard.removeObject(forKey: "activePackTearMask")
            UserDefaults.standard.removeObject(forKey: "activePackDuplicates")
            
            // Clean up old FoundCards/RevealedCards if they contain old keys
            if let found = UserDefaults.standard.stringArray(forKey: "FoundCards"),
               found.contains(where: { $0 == "Giulio_Clovio" || $0 == "Flagellation" }) {
                UserDefaults.standard.removeObject(forKey: "FoundCards")
                UserDefaults.standard.removeObject(forKey: "RevealedCards")
                UserDefaults.standard.removeObject(forKey: "DuplicateCardCounts")
            }
            return [:]
        }
        return decoded.filter { name, artwork in
            ArtworkSafetyPolicy.allows(
                internalName: name,
                remoteApproval: artwork.isAppStoreAllowed
            )
        }
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
    
    static func syncWithCloud(force: Bool = false) async {
        if !force, let lastSync = lastSyncTime, Date().timeIntervalSince(lastSync) < 30 {
            // print("ℹ️ syncWithCloud saltato: sincronizzato di recente (\(Int(Date().timeIntervalSince(lastSync))) secondi fa)")
            return
        }
        
        do {
            var allArtworks: [String: NetworkArtwork] = [:]
            var museumMap: [String: [String]] = [:]
            
            for museum in MuseumConfig.shared.museums {
                let fetched = try await NetworkService.shared.fetchArtworks(for: museum.id)
                let sortedFetched = fetched.sorted { ($0.cardNumber ?? Int.max) < ($1.cardNumber ?? Int.max) }
                var ids: [String] = []
                for art in sortedFetched {
                    allArtworks[art.internalName] = art
                    ids.append(art.internalName)
                }
                museumMap[museum.id] = ids
            }
            
            remoteArtworks = allArtworks
            artworksByMuseum = museumMap
            saveToCache(allArtworks, map: museumMap)
            
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
        if remoteArtworks.isEmpty {
            await syncWithCloud()
        }
        
        let dir = artworksDirectoryURL
        let artworksToDownload = artworks.filter { name in
            guard let art = remoteArtworks[name], !art.imageUrl.isEmpty else { return false }
            let destinationURL = dir.appendingPathComponent("\(name).jpg")
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                let size = (try? FileManager.default.attributesOfItem(atPath: destinationURL.path)[.size] as? Int) ?? 0
                if size > 10000 { return false }
            }
            return true
        }
        
        guard !artworksToDownload.isEmpty else { return }
        
        // Limit concurrency to 3 simultaneous downloads to avoid saturating network
        let maxConcurrentDownloads = 3
        var index = 0
        
        await withTaskGroup(of: Void.self) { group in
            // Start the first batch of workers
            for _ in 0..<min(maxConcurrentDownloads, artworksToDownload.count) {
                let name = artworksToDownload[index]
                index += 1
                group.addTask {
                    await downloadSingleImage(name: name, dir: dir)
                }
            }
            
            // As each download completes, start a new one until all are done
            while await group.next() != nil {
                if index < artworksToDownload.count {
                    let name = artworksToDownload[index]
                    index += 1
                    group.addTask {
                        await downloadSingleImage(name: name, dir: dir)
                    }
                }
            }
        }
    }
    
    private static func downloadSingleImage(name: String, dir: URL) async {
        guard let art = remoteArtworks[name] else { return }
        let urlString = art.imageUrl
        guard let url = URL(string: urlString) else { return }
        let destinationURL = dir.appendingPathComponent("\(name).jpg")
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            try data.write(to: destinationURL, options: .atomic)
            print("✅ Downloaded \(name) during AR preparation")
            
            // Post notification on main thread so UI updates immediately
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .artworkImageDownloaded,
                    object: nil,
                    userInfo: ["internalName": name]
                )
            }
        } catch {
            print("❌ Failed download for \(name) during AR preparation: \(error.localizedDescription)")
        }
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
        guard let match = dimensions.firstMatch(of: /(\d+(?:[.,]\d+)?)/) else { return 0.5 }
        let valueStr = String(match.1).replacingOccurrences(of: ",", with: ".")
        guard let cm = Double(valueStr), cm > 5 else { return 0.5 }
        // Convert cm to meters, clamp to sensible museum painting range (0.1–3.0m)
        return CGFloat(min(max(cm / 100.0, 0.1), 3.0))
    }
    
    static func artworksFor(location: String) -> [String] {
        let loc = location.lowercased()
        if let list = artworksByMuseum[loc], !list.isEmpty {
            return list.filter { ArtworkSafetyPolicy.allows(internalName: $0) }
        }
        if let list = fallbackMuseumMap[loc], !list.isEmpty {
            return list.filter { ArtworkSafetyPolicy.allows(internalName: $0) }
        }
        let filtered = remoteArtworks.values.filter {
            $0.museumId?.lowercased() == loc
                && ArtworkSafetyPolicy.allows(internalName: $0.internalName)
        }
        if !filtered.isEmpty {
            return filtered.sorted { ($0.cardNumber ?? Int.max) < ($1.cardNumber ?? Int.max) }.map { $0.internalName }
        }
        return Array(remoteArtworks.keys).sorted()
    }

    /// Zero-based display position in the current filtered museum library.
    /// Card views add one when formatting, matching the album's 01, 02, 03… labels.
    static func cardIndex(for name: String) -> Int? {
        if let museumId = remoteArtworks[name]?.museumId,
           let index = artworksFor(location: museumId).firstIndex(of: name) {
            return index
        }

        for museum in MuseumConfig.shared.museums {
            if let index = artworksFor(location: museum.id).firstIndex(of: name) {
                return index
            }
        }

        if let number = remoteArtworks[name]?.cardNumber {
            return max(0, number - 1)
        }

        return nil
    }

    /// 1-based card number (01, 02, 03...)
    static func cardNumber(for name: String) -> Int? {
        if let number = remoteArtworks[name]?.cardNumber {
            return number
        }
        if let index = cardIndex(for: name) {
            return index + 1
        }
        return nil
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
        if name == "vale" {
            return "Vale"
        }
        if let artwork = remoteArtworks[name] {
            return artwork.title
        }
        
        var cleaned = name
        cleaned = cleaned.replacing(/^\\d+\\s*-\\s*/, with: "")
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
    
    static func getActivePack(for museumId: String? = nil) -> [String]? {
        let city = museumId ?? UserDefaults.standard.string(forKey: "currentCity") ?? "uffizi"
        let cards = UserDefaults.standard.stringArray(forKey: "activePackCards_\(city)")
            ?? UserDefaults.standard.stringArray(forKey: "activePackCards")
        return cards?.filter { ArtworkSafetyPolicy.allows(internalName: $0) }
    }
    
    static func hasActivePack(for museumId: String? = nil) -> Bool {
        guard let active = getActivePack(for: museumId), !active.isEmpty else {
            return false
        }
        return true  // Le doppie restano nel pacchetto, non filtrarle
    }
    
    static func clearActivePackIfNeeded(for museumId: String? = nil) {
        let city = museumId ?? UserDefaults.standard.string(forKey: "currentCity") ?? "uffizi"
        if let active = getActivePack(for: city), !active.isEmpty {
            let revealed = getRevealedCards()
            let dupes = Set(UserDefaults.standard.stringArray(forKey: "activePackDuplicates_\(city)")
                            ?? UserDefaults.standard.stringArray(forKey: "activePackDuplicates") ?? [])
            if active.allSatisfy({ revealed.contains($0) || dupes.contains($0) }) {
                UserDefaults.standard.removeObject(forKey: "activePackCards_\(city)")
                UserDefaults.standard.removeObject(forKey: "activePackTearMask_\(city)")
                UserDefaults.standard.removeObject(forKey: "activePackDuplicates_\(city)")
                
                // Clean up legacy keys too
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
    static func getDuplicatesInActivePack(for museumId: String? = nil) -> Set<String> {
        let city = museumId ?? UserDefaults.standard.string(forKey: "currentCity") ?? "uffizi"
        guard getActivePack(for: city) != nil else { return [] }
        return Set(UserDefaults.standard.stringArray(forKey: "activePackDuplicates_\(city)")
                   ?? UserDefaults.standard.stringArray(forKey: "activePackDuplicates") ?? [])
    }
    
    /// True se TUTTE le carte del pacchetto attivo sono già state rivelate (tutte doppie)
    static func isActivePackAllDuplicates(for museumId: String? = nil) -> Bool {
        let city = museumId ?? UserDefaults.standard.string(forKey: "currentCity") ?? "uffizi"
        guard let pack = getActivePack(for: city), !pack.isEmpty else { return false }
        let revealed = getRevealedCards()
        let dupes = Set(UserDefaults.standard.stringArray(forKey: "activePackDuplicates_\(city)")
                        ?? UserDefaults.standard.stringArray(forKey: "activePackDuplicates") ?? [])
        return pack.allSatisfy { revealed.contains($0) || dupes.contains($0) }
    }
    
    // Gestione salvataggio carte trovate nei pacchetti (pixelate)
    static func addFoundCards(_ names: [String]) {
        var found = getFoundCards()
        for name in names {
            if ArtworkSafetyPolicy.allows(internalName: name) {
                found.insert(name)
            }
        }
        UserDefaults.standard.set(Array(found), forKey: "FoundCards")
    }
    
    static func getFoundCards() -> Set<String> {
        if let saved = UserDefaults.standard.stringArray(forKey: "FoundCards") {
            return Set(saved.filter { ArtworkSafetyPolicy.allows(internalName: $0) })
        }
        return []
    }
    
    // Gestione salvataggio carte riconosciute in AR (chiare)
    static func addRevealedCard(_ name: String) {
        guard ArtworkSafetyPolicy.allows(internalName: name) else { return }
        var revealed = getRevealedCards()
        revealed.insert(name)
        UserDefaults.standard.set(Array(revealed), forKey: "RevealedCards")
        
        // Assicuriamoci che se è rivelata, sia anche marcata come trovata
        addFoundCards([name])
    }
    
    static func getRevealedCards() -> Set<String> {
        if let saved = UserDefaults.standard.stringArray(forKey: "RevealedCards") {
            return Set(saved.filter { ArtworkSafetyPolicy.allows(internalName: $0) })
        }
        return []
    }

    static let fallbackMuseumMap: [String: [String]] = [
        "uffizi": [
            "botticelli-primavera",
            "botticelli-pallas-and-the-centaur",
            "botticelli-madonna-of-the-magnificat",
            "botticelli-madonna-of-the-pomegranate-madonna-della-melagran",
            "botticelli-calumny-of-apelles",
            "botticelli-fortitude",
            "leonardo-annunciation",
            "leonardo-adoration-of-the-magi",
            "verrocchio-the-baptism-of-christ",
            "michelangelo-the-holy-family-with-the-infant-st-john-the-bap",
            "raffaello-madonna-del-cardellino",
            "raffaello-portraits-of-agnolo-and-maddalena-doni",
            "raffaello-self-portrait",
            "raffaello-pope-leo-x-with-cardinals-giulio-de-medici-and-lui",
            "caravaggio-bacchus",
            "piero-portrait-of-federico-da-montefeltro",
            "piero-triumph-of-battista-sforza",
            "giotto-ognissanti-madonna-madonna-in-maesta",
            "cimabue-the-madonna-in-majesty-maesta",
            "duccio-rucellai-madonna",
            "simone-annunciation-and-two-saints",
            "gentile-adoration-of-the-magi",
            "uccello-bernardino-della-ciarda-thrown-off-his-horse",
            "goes-sts-anthony-and-thomas-with-tommaso-portinari",
            "parmigianino-madonna-dal-collo-lungo-madonna-with-long-neck",
            "bronzino-eleonora-di-toledo-with-her-son-giovanni-de-medici",
            "bronzino-portrait-of-lucrezia-panciatichi",
            "andrea-madonna-of-the-harpies",
            "angelico-the-coronation-of-the-virgin",
            "lippi-madonna-and-child-with-two-angels",
            "weyden-entombment-of-christ",
            "durer-adoration-of-the-magi",
            "rembrandt-self-portrait-as-a-young-man",
            "rubens-self-portrait",
            "gentileschi-st-catherine-of-alexandria",
            "greco-sts-john-the-evangelist-and-francis",
            "mantegna-the-adoration-of-the-magi",
            "correggio-rest-on-the-flight-into-egypt-with-st-francis",
            "lorenzo-the-coronation-of-the-virgin",
            "pontormo-supper-at-emmaus",
            "veronese-holy-family-with-st-catherine-and-the-infant-st-joh",
            "tintoretto-self-portrait-with-a-book",
            "perugino-pieta",
            "bellini-sacred-allegory"
        ],
        "prado": [
            "prado-velazquez-las-meninas-or-the-family-of-philip-iv",
            "prado-weyden-deposition",
            "prado-tiziano-emperor-charles-v-at-muhlberg",
            "prado-velazquez-the-surrender-of-breda-las-lanzas",
            "prado-greco-nobleman-with-his-hand-on-his-chest",
            "prado-rubens-the-rape-of-europa",
            "prado-durer-self-portrait-at-26",
            "prado-velazquez-the-triumph-of-bacchus-los-borrachos-the-tope",
            "prado-rubens-the-holy-family-with-st-anne",
            "prado-velazquez-the-fable-of-arachne-las-hilanderas",
            "prado-velazquez-philip-iv-in-armour",
            "prado-goya-y-lucientes-the-second-of-may-1808-the-charge-of-t",
            "prado-greco-the-trinity",
            "prado-greco-the-annunciation",
            "prado-murillo-immaculate-conception",
            "prado-goya-y-lucientes-witches-in-the-air",
            "prado-tiziano-portrait-of-isabella-of-portugal",
            "prado-bosch-triptych-of-haywain",
            "prado-angelico-the-annunciation",
            "prado-bosch-the-cure-of-folly-extraction-of-the-stone-of-madn",
            "prado-goya-y-lucientes-the-parasol",
            "prado-tintoretto-christ-washing-the-feet-of-his-disciples",
            "prado-velazquez-aesop",
            "prado-velazquez-menippus",
            "prado-velazquez-the-forge-of-vulcan",
            "prado-rubens-the-cardinal-infante",
            "prado-antonello-the-dead-christ-supported-by-an-angel",
            "prado-rubens-garden-of-love",
            "prado-ribera-jacob-s-dream",
            "prado-greco-the-pentecost",
            "prado-velazquez-philip-iv-on-horseback",
            "prado-rubens-duke-of-lerma",
            "prado-bosch-the-temptation-of-st-anthony",
            "prado-velazquez-prince-baltasar-carlos-as-a-hunter",
            "prado-velazquez-the-buffoon-pablo-de-valladolid",
            "prado-goya-y-lucientes-fight-with-a-young-bull",
            "prado-velazquez-mercury-and-argus",
            "prado-velazquez-cardinal-infante-don-fernando-as-a-hunter",
            "prado-gentileschi-birth-of-st-john-the-baptist",
            "prado-cecco-guardian-angel-with-sts-ursula-and-thomas"
        ],
        "moma": [
            "moma-gogh-starry-night",
            "moma-rousseau-the-sleeping-gypsy",
            "moma-cezanne-bather",
            "moma-seurat-evening-honfleur",
            "moma-toulouse-lautrec-la-goulue-arriving-at-the-moulin-rouge",
            "moma-gogh-the-olive-trees",
            "moma-gauguin-still-life-with-three-puppies",
            "moma-klimt-hope-ii",
            "moma-signac-portrait-of-felix-feneon",
            "moma-degas-at-the-milliner-s",
            "moma-gauguin-washerwomen",
            "moma-picasso-woman-by-a-window",
            "moma-picasso-woman-in-an-armchair",
            "moma-picasso-maya-in-a-sailor-suit",
            "moma-picasso-bather-and-cabin",
            "moma-picasso-still-life-with-fruit-dish-nature-morte-au-comp",
            "moma-mondrian-composition-in-red-blue-and-yellow",
            "moma-mondrian-composition-with-red-and-blue",
            "moma-mondrian-composition-with-color-planes-5",
            "moma-mondrian-tableau-i-lozenge-with-four-lines-and-gray",
            "moma-matisse-the-rose-marble-table",
            "moma-matisse-the-back-i",
            "moma-matisse-jeannette-v",
            "moma-hopper-gas",
            "moma-hopper-night-windows",
            "moma-ensor-tribulations-of-st-anthony",
            "moma-klee-castle-garden",
            "moma-klee-actor-s-mask",
            "moma-klee-equals-infinity",
            "moma-klee-pastorale-rhythms",
            "moma-klee-in-the-grass",
            "moma-puvis-de-chavannes-the-shepherd-s-song",
            "moma-toulouse-lautrec-lily-grenier",
            "moma-cezanne-turning-road-at-montgeroult",
            "moma-picasso-portrait-of-francoise-with-long-neck-i-portrait",
            "moma-picasso-head-of-a-woman-no-1-portrait-of-dora-maar-tete",
            "moma-matisse-large-odalisque-in-striped-pantaloons-grande-od",
            "moma-picasso-the-circus-le-cirque",
            "moma-picasso-man-and-woman-homme-et-femme",
            "moma-picasso-ines-and-her-child-ines-et-son-enfant",
            "moma-picasso-owl-glass-and-flower",
            "moma-matisse-harbor-at-collioure-port-de-collioure",
            "moma-picasso-black-figure-figure-noire",
            "moma-matisse-venus-in-a-shell-i",
            "moma-picasso-bearded-faun",
            "moma-matisse-torso-leaning-on-arms-torse-reposant-sur-les-br",
            "moma-picasso-nocturnal-dance-with-an-owl-danse-nocturne-avec"
        ]
    ]
}

// `Color(hex:)` now lives in Components/Color+Hex.swift so it can be shared
// across the whole app without duplicating the implementation here.
