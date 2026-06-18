import Foundation

/// Notification.Name extensions for typed notifications used throughout the project.
extension Notification.Name {
    /// Notification posted when an artwork image has been downloaded successfully.
    static let artworkImageDownloaded = Notification.Name("ArtworkImageDownloaded")
    
    /// Notification posted when user authentication status changes.
    static let userAuthenticationStatusChanged = Notification.Name("UserAuthenticationStatusChanged")
    
    /// Notification posted when a new message is received.
    static let newMessageReceived = Notification.Name("NewMessageReceived")
    
    /// Notification posted when data synchronization completes.
    static let dataSyncCompleted = Notification.Name("DataSyncCompleted")
}
