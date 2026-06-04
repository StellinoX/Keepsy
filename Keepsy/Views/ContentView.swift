//
//  ContentView.swift
//  Keepsy
//
//  Created by Camilla Cacace on 13/05/26.
//

import SwiftUI

struct ContentView: View {
    @State private var activeView: ActiveView = .opening
    
    enum ActiveView: Equatable {
        case opening, arScanner
        case collection(String)
    }
    
    var body: some View {
        Group {
            switch activeView {
            case .opening:
                PackOpeningView(activeView: $activeView)
            case .arScanner:
                ARArtworkView(activeView: $activeView)
            case .collection(let city):
                CollectionAlbumView(museumLocation: city, showCloseButton: true) {
                    activeView = .opening
                }
            }
        }
        .task {
            // Sincronizza i metadati da Firebase Firestore in background all'avvio
            await CardDatabase.syncWithCloud()
            
            // Prefetch/Scarica tutte le immagini delle opere per averle già in locale in background
            await prefetchAllImages()
        }
    }
    
    private func prefetchAllImages() async {
        let museums = ["capodimonte", "uffizi"]
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
