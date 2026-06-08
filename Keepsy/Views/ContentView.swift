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
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        showAutoKeptPopup = true
                    }
                }
            }
        }
        .overlay {
            if showAutoKeptPopup {
                ZStack {
                    Color.black.opacity(0.65)
                        .ignoresSafeArea()
                        .transition(.opacity)

                    VStack(spacing: 24) {
                        Text("WE KEPT 'EM")
                            .font(.system(size: 26, weight: .black))
                            .italic()
                            .foregroundColor(Color(hex: "FF7A00"))
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)

                        (
                            Text("You closed the app with ")
                                .font(.system(size: 15, weight: .semibold)).italic()
                            + Text("\(autoKeptCount) \(autoKeptCount == 1 ? "card" : "cards")")
                                .font(.system(size: 15, weight: .black)).italic()
                            + Text(" not yet in your collection.\nDon't worry we ")
                                .font(.system(size: 15, weight: .semibold)).italic()
                            + Text("Kept")
                                .font(.system(size: 15, weight: .black)).italic()
                            + Text(" them for you.")
                                .font(.system(size: 15, weight: .semibold)).italic()
                        )
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 16)

                        Button(action: {
                            HapticManager.shared.triggerImpact(style: .light)
                            withAnimation(.easeInOut(duration: 0.25)) {
                                showAutoKeptPopup = false
                            }
                        }) {
                            Text("OK")
                                .font(.system(size: 18, weight: .black))
                                .italic()
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background(Capsule().fill(Color(hex: "E5E5EA")))
                        }
                        .padding(.horizontal, 8)
                    }
                    .padding(28)
                    .background(
                        RoundedRectangle(cornerRadius: 32)
                            .fill(Color(hex: "1C1C1E"))
                            .overlay(
                                RoundedRectangle(cornerRadius: 32)
                                    .stroke(Color.white.opacity(0.15), lineWidth: 1.5)
                            )
                    )
                    .padding(.horizontal, 28)
                    .shadow(color: Color.black.opacity(0.5), radius: 20, y: 10)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
                .zIndex(999)
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
