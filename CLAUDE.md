# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build

```bash
# Build for device (no simulator needed)
xcodebuild -scheme Keepsy -destination 'generic/platform=iOS' build

# Check errors only
xcodebuild -scheme Keepsy -destination 'generic/platform=iOS' build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

No unit tests exist. Verify changes by running on a physical device.

## Architecture

Keepsy is an iOS app (SwiftUI) where users open card packs of museum artworks and unlock them by scanning the real painting with the camera (ARKit image tracking).

**Data flow:**
1. `NetworkService` fetches artwork metadata from **Firebase Firestore** and downloads images from **AWS S3** to the local `Documents/Artworks/` directory.
2. `CardDatabase` (static struct) caches remote artwork metadata in `UserDefaults` and provides image loading from disk. It also manages all game state in `UserDefaults` (found cards, revealed cards, active pack, duplicates).
3. Views read from `CardDatabase` directly — there are no ViewModels.

**Key state stored in UserDefaults:**
- `activePackCards` — current pack of 5 card names
- `activePackDuplicates` — cards that were already owned when this pack was opened (computed BEFORE `addFoundCards`, critical ordering)
- `FoundCards` — all cards ever found in a pack (pixelated state)
- `RevealedCards` — cards scanned in AR (fully revealed)
- `recentlyCompletedPackCards` — triggers sticker-insert animation in `CollectionAlbumView`
- `currentCity` — active museum ID (e.g. `"capodimonte"`)

**Card lifecycle:**
- Pack opened → `trackDuplicates` (must run BEFORE `addFoundCards`) → `addFoundCards` → AR scan → `addRevealedCard` → `clearActivePackIfNeeded`
- `getDuplicatesInActivePack()` reads from `activePackDuplicates` (saved once at pack open), NOT recalculated live — recalculating would mark all cards as duplicates since `addFoundCards` adds the entire pack to `FoundCards`.

**View routing:** `ContentView` owns `ActiveView` enum (`.opening`, `.arScanner`, `.collection(String)`). Navigation is purely state-driven via `$activeView` binding passed down.

**AR pipeline (`ARArtworkView` → `ARViewContainer`):**
- `ARImageTrackingConfiguration` tracks all pack images simultaneously (`maximumNumberOfTrackedImages = n`)
- Images downloaded to disk → `CardDatabase.arReferenceImage(for:)` builds `ARReferenceImage` with 1024px CGImage (EXIF baked via `kCGImageSourceCreateThumbnailWithTransform`)
- On recognition: `triggerUnlockAnimation` binding fires → `startUnlockAnimation` shows fullscreen card overlay (1.8s) → auto-dismisses → navigate to collection if last card

**Pack opening (`PackOpeningView` → `SceneKitPacketView`):**
- 3D card packet rendered in SceneKit with custom Metal shader for tear mask effect
- `SceneKitPacketView` has `rendersContinuously = false` to avoid 60fps idle drain

**Image loading (`ArtImageView`):**
- Checks `NSCache` → bundle assets → `Documents/Artworks/` disk
- Async load at `.utility` priority; listens for `ArtworkImageDownloaded` notification when S3 download completes in background

**Backend:**
- Firestore collection: `artworks` — fields: `title`, `artist`, `description`, `date`, `technique`, `dimensions`, `inventoryNumber`, `imageFilename`, `imageUrl`
- `imageFilename` = `"{Percorso}.jpg"` (CSV Percorso column); `internalName` = filename without `.jpg`, used as the card's identity key throughout the app
- Images hosted on S3 bucket `keepsy-art-images-rstudio` (us-east-2), publicly readable

## SwiftUI & State Rules

- Use ONLY `@Observable` (Observation framework). No `ObservableObject`, `@StateObject`, or Combine.
- Use `@Environment` for global dependencies, `@Bindable` for bindings from observable models.
- Keep views under 100 lines; extract sub-views immediately when exceeded.
- Use custom `ViewModifier` for shared styling.

## Concurrency Rules

- `async/await` only. No `DispatchQueue` or completion handlers in new code (legacy GCD exists in animation sequences — do not spread further).
- `@MainActor` on any class managing UI state.
- Cross-actor data must conform to `Sendable`.

## Design Tokens

- Gold border: `Color(hex: "F1B40A")`
- Green unlock/checkmark: `Color(hex: "4CD964")`
- Blue CTA: `Color(hex: "007AFF")`
- `Color(hex:)` extension lives at the bottom of `CardDatabase.swift`
- Card aspect ratio: width × 1.5 = height; corner radius = width × 12/111
