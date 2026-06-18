//
//  ContentView.swift
//  Keepsy
//
//  Created by Camilla Cacace on 13/05/26.
//

import SwiftUI

struct ContentView: View {
    @State private var activeView: ActiveView = .opening
    @State private var showAutoKeptPopup: Bool = false
    @State private var autoKeptCount: Int = 0
    
    enum ActiveView: Equatable {
        case opening, arScanner
        case collection(String)
    }
    
    var body: some View {
        ZStack {
            switch activeView {
            case .opening:
                PackOpeningView(activeView: $activeView)
                    .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .leading)))
            case .arScanner:
                ARArtworkView(activeView: $activeView)
                    .transition(.opacity)
            case .collection(let city):
                CollectionAlbumView(museumLocation: city, showCloseButton: true) {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        activeView = .opening
                    }
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
            }
        }
        .onAppear {
            let autoCount = UserDefaults.standard.integer(forKey: "autoKeptCardsCount")
            if autoCount > 0 {
                autoKeptCount = autoCount
                UserDefaults.standard.removeObject(forKey: "autoKeptCardsCount")
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.8))
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        showAutoKeptPopup = true
                    }
                }
            }
        }
        .task {
            // Sincronizza i metadati da Firebase Firestore in background all'avvio
            await CardDatabase.syncWithCloud()
            
            // Prefetch/Scarica tutte le immagini delle opere per averle già in locale in background
            await prefetchAllImages()
        }
        .alert("We Kept 'Em", isPresented: $showAutoKeptPopup) {
            Button("OK", role: .cancel) { HapticManager.shared.triggerImpact(style: .light) }
        } message: {
            Text("You closed the app with \(autoKeptCount) \(autoKeptCount == 1 ? "card" : "cards") not yet in your collection. Don't worry — we Kept them for you.")
        }
    }
    
    private func prefetchAllImages() async {
        let museums = MuseumConfig.shared.museums.map { $0.id }
        var allMissing: [String] = []
        
        for museum in museums {
            let artworks = CardDatabase.artworksFor(location: museum)
            let downloaded = CardDatabase.downloadedArtworkNames(for: museum)
            let missing = artworks.filter { !downloaded.contains($0) }
            allMissing.append(contentsOf: missing)
        }
        
        if !allMissing.isEmpty {
            await CardDatabase.downloadImages(for: allMissing)
        }
    }
}

#Preview {
    ContentView()
}
