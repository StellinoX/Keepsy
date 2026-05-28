import Foundation
import BackgroundAssets

class BackgroundAssetService: NSObject, BADownloadManagerDelegate {
    static let shared = BackgroundAssetService()
    
    private let downloadManager = BADownloadManager.shared
    
    private override init() {
        super.init()
        // Set self as delegate to receive download progress and completion events
        downloadManager.delegate = self
    }
    
    /// Schedules background download for a list of artwork image identifiers.
    /// Uses native BAURLDownload to offload download to the OS level.
    func scheduleDownloads(for artworkNames: [String]) {
        for name in artworkNames {
            // Retrieve URL dynamically from cached CloudKit remote artworks
            guard let urlString = CardDatabase.remoteArtworks[name]?.imageUrl,
                  let url = URL(string: urlString) else {
                print("Skipping background download schedule for \(name): No URL available")
                continue
            }
            
            let request = URLRequest(url: url)
            let download = BAURLDownload(
                identifier: name,
                request: request,
                applicationGroupIdentifier: "group.camillacacace.prova-capodimonte"
            )
            
            do {
                try downloadManager.scheduleDownload(download)
                print("Scheduled background asset download for: \(name)")
            } catch {
                print("Failed to schedule background download for \(name): \(error)")
            }
        }
    }
    
    // MARK: - BADownloadManagerDelegate
    
    func download(_ download: BADownload, didWriteBytes bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        print("Background asset download progress for \(download.identifier): \(Int(progress * 100))%")
    }
    
    func download(_ download: BADownload, finishedWithFileURL fileURL: URL) {
        // Copy downloaded Apple-hosted asset to our local document directory (/Artworks)
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let docDir = paths[0].appendingPathComponent("Artworks", isDirectory: true)
        
        if !FileManager.default.fileExists(atPath: docDir.path) {
            try? FileManager.default.createDirectory(at: docDir, withIntermediateDirectories: true)
        }
        
        let destinationURL = docDir.appendingPathComponent("\(download.identifier).jpg")
        
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: fileURL, to: destinationURL)
            print("Successfully copied background asset \(download.identifier) to sandbox: \(destinationURL.path)")
        } catch {
            print("Failed to copy background asset \(download.identifier): \(error)")
        }
    }
    
    func download(_ download: BADownload, failedWithError error: Error) {
        print("Background download failed for \(download.identifier): \(error)")
    }
}
