import Foundation

/// Notification.Name extensions for typed notifications used throughout the project.
extension Notification.Name {
    /// Notification posted when an artwork image has been downloaded successfully.
    static let artworkImageDownloaded = Notification.Name("ArtworkImageDownloaded")
    
    /// Notification posted when artwork database or card numbers have been updated.
    static let artworkDatabaseUpdated = Notification.Name("ArtworkDatabaseUpdated")
}
