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
    }
}

#Preview {
    ContentView()
}
