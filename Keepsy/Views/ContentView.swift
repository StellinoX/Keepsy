//
//  ContentView.swift
//  Keepsy
//
//  Created by Camilla Cacace on 13/05/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            PackOpeningView()
                .tabItem {
                    Label("Apri Pacchetti", systemImage: "bag.fill")
                }
            
            ARArtworkView()
                .tabItem {
                    Label("Scanner AR", systemImage: "camera.viewfinder")
                }
        }
        .accentColor(.orange)
    }
}

#Preview {
    ContentView()
}
