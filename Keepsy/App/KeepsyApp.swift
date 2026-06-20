//
//  KeepsyApp.swift
//  Keepsy
//
//  Created by Camilla Cacace on 13/05/26.
//

import SwiftUI
import FirebaseCore

@main
struct KeepsyApp: App {
    @State private var localization = LocalizationManager.shared

    init() {
        FirebaseApp.configure()
        if let idfv = UIDevice.current.identifierForVendor?.uuidString {
            print("🚀 DEVELOPER DEVICE IDFV: \(idfv)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(localization)
                .environment(\.locale, localization.locale)
        }
    }
}
