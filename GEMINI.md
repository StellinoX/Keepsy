# Keepsy Project Overview

Keepsy is an interactive iOS application built with SwiftUI that gamifies museum visits. Users collect "artwork cards" by opening virtual packs and "unlocking" them through real-world ARKit image tracking of paintings in museums.

## Tech Stack
- **Framework:** SwiftUI (with the modern Observation framework)
- **AR/3D:** ARKit (Image Tracking), SceneKit (3D Pack Opening), Metal (Custom Shaders)
- **Backend:** Firebase Firestore (Metadata), AWS S3 (Images)
- **Persistence:** UserDefaults (Game state, collection progress), local disk storage (Image cache)

## Architecture & Data Flow

### State Management
- **CardDatabase:** A centralized static controller managing all app state and data persistence. It syncs metadata with Firebase, caches it in `UserDefaults`, and provides thread-safe access to artwork information.
- **Navigation:** Purely state-driven via the `ActiveView` enum in `ContentView`.

### Networking & Assets
- **NetworkService:** Fetches artwork metadata from Firestore. It triggers background downloads of high-resolution images from S3 to the device's `Documents/Artworks/` directory.
- **AR Pipeline:** Dynamically builds `ARReferenceImage` objects from local disk images. It uses `CGImageSource` to bake EXIF rotation and downsample images for optimal ARKit performance.

### Gameplay Lifecycle
1. **Pack Opening:** Users open a 3D packet rendered in SceneKit. Cards are assigned and stored in `FoundCards` (pixelated/locked state).
2. **AR Scanning:** Users select a card and point their camera at the real artwork. ARKit matches the image, triggering a "Catch" animation.
3. **Collection:** Unlocked cards move to `RevealedCards` and appear in the `CollectionAlbumView` with full metadata.

## Building and Running

### Prerequisites
- macOS with Xcode 14+
- A physical iOS device (ARKit features require a real camera)
- Firebase configuration (`GoogleService-Info.plist` is present)

### Key Commands
- **Build for Device:**
  ```bash
  xcodebuild -scheme Keepsy -destination 'generic/platform=iOS' build
  ```
- **Check Build Errors:**
  ```bash
  xcodebuild -scheme Keepsy -destination 'generic/platform=iOS' build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
  ```

## Development Conventions

### SwiftUI & State
- **Observation:** Use `@Observable` exclusively. Avoid `ObservableObject` or Combine.
- **Views:** Keep view files concise (aim for < 100 lines). Extract sub-views into separate files in `Keepsy/Components` or `Keepsy/Views`.
- **Styling:** Use the custom `Color(hex:)` extension in `CardDatabase.swift`.

### Concurrency
- Use `async/await` for all asynchronous operations.
- UI state management should be isolated to the `@MainActor`.
- For heavy disk I/O (like image decoding), use `nonisolated` methods to avoid blocking the main thread.

### AR & Graphics
- **AR Images:** Must be valid JPEGs > 10KB. Corrupted or partial downloads are automatically deleted and retried.
- **SceneKit:** Set `rendersContinuously = false` when the 3D pack is not animating to save battery.

## Project Structure
- `Keepsy/App/`: App entry point and Firebase initialization.
- `Keepsy/Models/`: Data models (`NetworkArtwork`) and core logic (`CardDatabase`, `NetworkService`).
- `Keepsy/Views/`: Main feature screens (AR, Collection, Pack Opening).
- `Keepsy/Components/`: Reusable UI elements like `ArtImageView` and `GridBackground`.
- `Keepsy/Services/`: System services like `HapticManager` and `LocationManager`.
