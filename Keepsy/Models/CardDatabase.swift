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
        get { dictLock.withLock { _remoteArtworks } }
        set { dictLock.withLock { _remoteArtworks = newValue } }
    }
    static var artworksByMuseum: [String: [String]] {
        get { dictLock.withLock { _artworksByMuseum } }
        set { dictLock.withLock { _artworksByMuseum = newValue } }
    }
    
    private static let mapCacheKey = "CachedMuseumMap"
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
        guard let match = dimensions.firstMatch(of: /(\d+(?:[.,]\d+)?)/) else { return 0.5 }
        let valueStr = String(match.1).replacingOccurrences(of: ",", with: ".")
        guard let cm = Double(valueStr), cm > 5 else { return 0.5 }
        // Convert cm to meters, clamp to sensible museum painting range (0.1–3.0m)
        return CGFloat(min(max(cm / 100.0, 0.1), 3.0))
    }
    
    static func artworksFor(location: String) -> [String] {
        let loc = location.lowercased()
        if let list = artworksByMuseum[loc], !list.isEmpty {
            return list
        }
        if let list = fallbackMuseumMap[loc], !list.isEmpty {
            return list
        }
        let filtered = remoteArtworks.values.filter { $0.museumId?.lowercased() == loc }
        if !filtered.isEmpty {
            return filtered.map { $0.internalName }.sorted()
        }
        return Array(remoteArtworks.keys).sorted()
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
        cleaned = cleaned.replacing(/^\d+\s*-\s*/, with: "")
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
    
    static func getActivePack(for museumId: String? = nil) -> [String]? {
        let city = museumId ?? UserDefaults.standard.string(forKey: "currentCity") ?? "capodimonte"
        return UserDefaults.standard.stringArray(forKey: "activePackCards_\(city)")
            ?? UserDefaults.standard.stringArray(forKey: "activePackCards")
    }
    
    static func hasActivePack(for museumId: String? = nil) -> Bool {
        guard let active = getActivePack(for: museumId), !active.isEmpty else {
            return false
        }
        return true  // Le doppie restano nel pacchetto, non filtrarle
    }
    
    static func clearActivePackIfNeeded(for museumId: String? = nil) {
        let city = museumId ?? UserDefaults.standard.string(forKey: "currentCity") ?? "capodimonte"
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
        let city = museumId ?? UserDefaults.standard.string(forKey: "currentCity") ?? "capodimonte"
        guard getActivePack(for: city) != nil else { return [] }
        return Set(UserDefaults.standard.stringArray(forKey: "activePackDuplicates_\(city)")
                   ?? UserDefaults.standard.stringArray(forKey: "activePackDuplicates") ?? [])
    }
    
    /// True se TUTTE le carte del pacchetto attivo sono già state rivelate (tutte doppie)
    static func isActivePackAllDuplicates(for museumId: String? = nil) -> Bool {
        let city = museumId ?? UserDefaults.standard.string(forKey: "currentCity") ?? "capodimonte"
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

    static let fallbackMuseumMap: [String: [String]] = [
        "uffizi": [
            "andrea-madonna-of-the-harpies",
            "angelico-the-coronation-of-the-virgin",
            "bellini-sacred-allegory",
            "botticelli-calumny-of-apelles",
            "botticelli-fortitude",
            "botticelli-madonna-of-the-magnificat",
            "botticelli-madonna-of-the-pomegranate-madonna-della-melagran",
            "botticelli-pallas-and-the-centaur",
            "botticelli-primavera",
            "botticelli-the-birth-of-venus",
            "bronzino-eleonora-di-toledo-with-her-son-giovanni-de-medici",
            "bronzino-portrait-of-lucrezia-panciatichi",
            "caravaggio-bacchus",
            "caravaggio-head-of-medusa",
            "caravaggio-the-sacrifice-of-isaac",
            "cimabue-the-madonna-in-majesty-maesta",
            "correggio-rest-on-the-flight-into-egypt-with-st-francis",
            "duccio-rucellai-madonna",
            "durer-adoration-of-the-magi",
            "gentile-adoration-of-the-magi",
            "gentileschi-st-catherine-of-alexandria",
            "giotto-ognissanti-madonna-madonna-in-maesta",
            "goes-sts-anthony-and-thomas-with-tommaso-portinari",
            "greco-sts-john-the-evangelist-and-francis",
            "leonardo-adoration-of-the-magi",
            "leonardo-annunciation",
            "lippi-madonna-and-child-with-two-angels",
            "lorenzo-the-coronation-of-the-virgin",
            "mantegna-the-adoration-of-the-magi",
            "michelangelo-the-holy-family-with-the-infant-st-john-the-bap",
            "parmigianino-madonna-dal-collo-lungo-madonna-with-long-neck",
            "perugino-pieta",
            "piero-portrait-of-federico-da-montefeltro",
            "piero-triumph-of-battista-sforza",
            "pollaiuolo-hercules-and-antaeus",
            "pontormo-supper-at-emmaus",
            "raffaello-madonna-del-cardellino",
            "raffaello-pope-leo-x-with-cardinals-giulio-de-medici-and-lui",
            "raffaello-portraits-of-agnolo-and-maddalena-doni",
            "raffaello-self-portrait",
            "rembrandt-self-portrait-as-a-young-man",
            "rubens-self-portrait",
            "simone-annunciation-and-two-saints",
            "tintoretto-self-portrait-with-a-book",
            "tiziano-flora",
            "tiziano-venus-of-urbino",
            "uccello-bernardino-della-ciarda-thrown-off-his-horse",
            "veronese-holy-family-with-st-catherine-and-the-infant-st-joh",
            "verrocchio-the-baptism-of-christ",
            "weyden-entombment-of-christ"
        ],
        "capodimonte": [
            "1 - Q 36 Masaccio_Crocifissione_ph.L.Romano_0779",
            "10 - Girolamo Mazzoli Bedoli_Santa Chiara_ph.Luciano Romano_0620",
            "11 - Tiziano Vecellio_Danae_Capodimonte_ph.L.Romano_0722",
            "12 - Q 365 Annibale Carracci_Ercole al bivio_Capodimonte_ph.L.Romano_2280",
            "13 - Annibale Carracci_Piet\u{00E0}_Capodimonte_ph.L.Romano_2265",
            "14 - Caravaggio_Flagellazione di Cristo_Capodimonte_ph.L.Romano_10780",
            "15 - Guido Reni_Atalanta e Ippomene_ph.L.Romano_70271",
            "16 - Artemisia Gentileschi_Giuditta e Oloferne_ph.L.Romano_12119",
            "17 - Q_622",
            "18 - Francesco Guarino_S. Agata (part.)_ph.L.Romano_10804",
            "19 - Jusepe de Ribera_San Girolamo e l'angelo del Giudizio_10904",
            "2 - Giovanni Bellini_Trasfigurazione_ph.L.Romano_0738",
            "20 - Jusepe de Ribera_Sileno ebbro_ph.l.Romano_10797",
            "21 - Jusepe de Ribera_Apollo e Marsia_1637_ph.L.Romano_10849",
            "22 - Luca Giordano-Apollo e Marsia_Capodimonte_ph.L.Romano_10824",
            "23 - Mattia Preti_San Nicola di Bari_Capodimonte_ph.L.Romano_7315",
            "24 - Mattia Preti_San Sebastiano_10861",
            "25 - Luca Giordano_Madonna del Baldacchino_Capodimonte_ph.L.Romano_7326",
            "26 - Q_294",
            "27 - DSC_4408a",
            "28 - Pierre-Jacques Volaire_Eruzione del Vesuvio dal ponte della Maddalena_ph.L.Romano_3002",
            "29 - Tiziano Vecellio_Ritratto di Paolo III con i nipoti_ph.L.Romano_2131",
            "3 - Colantonio_San Girolamo nello studio_Capodimonte_ph.L.Romano_2359",
            "30 - Q 145 Raffaello Sanzio_Ritratto del cardinale Alessandro Farnese_Capodimonte_ph.L.Romano_3030",
            "31 - Q 191 El Greco_Ritratto di Giulio Clovio-2636",
            "32 - Antonio Joli_Ferdinando IV a cavallo con la corte_ph.L.Romano_Capodimonte_11010",
            "33 - Museo di Capodimonte_Andy Warhol_Vesuvius_ph.L.Romano_0054",
            "34 - 5501 EK Polittico S.Vincenzo Ferrer e storie",
            "35 - Q 60 Andrea Mantegna_Ritratto di Francesco Gonzaga_ph.L.Romano_0767",
            "36 - Q_130",
            "37 - SOTTOCONSEGNA S Domenico Tiziano Vecellio_Annunciazione_Capodimonte_ph.L.Romano_7268",
            "38 - Q_1110",
            "39 - Q699 Finson Annunciazione C033-25",
            "4 - Jacopo de'Barbari attr._Ritratto di Luca Pacioli_ph.L.Romano_3954",
            "40 - Q_375",
            "41 - Q 192 El Greco_El Soplon-2603",
            "42 - Sebastiano del Piombo_Ritratto di Clemente VII_ph.L.Romano_0999",
            "43 - Q_373",
            "44 - Bernardo Cavallino_La Cantatrice_ph.L.Romano_10817",
            "45 - Bernardo Cavallino_Santa Cecilia in estasi_ph.Luciano Romano__6811",
            "46 - Q 106 Correggio_Sposalizio mistico di Santa Caterina_Capodimonte_ph.L.Romano_7235",
            "47 - SOTTOCONSEGNA PALAZZO REALE PR 319 Annibale Carracci_Sposalizio mistico di Santa Caterina_Capodimonte_ph.L.Romano_2297",
            "48 - Mattia Preti_Giuditta e Oloferne_ph.Luciano Romano_8691",
            "49 - Q_309",
            "5 - Lorenzo Lotto_Ritratto  di Bernardo de Rossi_0750",
            "50 - Q_254",
            "51 - Q_263",
            "52 - Q_1719",
            "53 - Q_1086",
            "6 - Q 112 Rosso Fiorentino_Ritratto di giovane seduto con tappeto_ph.Luciano Romano_8414567",
            "7 - Parmigianino_Ritratto di Galeazzo Sanvitale_Capodimonte_ph.L.Romano_10948",
            "8 - Q 108 Parmigianino Antea_ph.L.Romano_10938",
            "9 - Parmigianino_Lucrezia_Capodimonte_ph.L.Romano__3676"
        ]
    ]
}

// `Color(hex:)` now lives in Components/Color+Hex.swift so it can be shared
// across the whole app without duplicating the implementation here.
