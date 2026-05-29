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
            // Se desideri caricare automaticamente tutte le 52 opere e immagini in CloudKit,
            // scommenta la riga qui sotto, avvia l'app sul Simulatore e controlla la console di Xcode!
            // Una volta completato il caricamento, puoi ricommentare questa riga.
            // await CloudKitSeeder.seedDatabase()
        }
    }
}

#Preview {
    ContentView()
}
