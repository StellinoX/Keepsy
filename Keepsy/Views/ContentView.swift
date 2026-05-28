//
//  ContentView.swift
//  Keepsy
//
//  Created by Camilla Cacace on 13/05/26.
//

import SwiftUI

struct ContentView: View {
    @State private var activeView: ActiveView = .opening
    
    enum ActiveView {
        case opening, arScanner
    }
    
    var body: some View {
        Group {
            switch activeView {
            case .opening:
                PackOpeningView(activeView: $activeView)
            case .arScanner:
                ARArtworkView(activeView: $activeView)
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
