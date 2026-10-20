//
//  KeepsyApp.swift
//  Keepsy
//
//  Created by Camilla Cacace on 13/05/26.
//

import SwiftUI
import FirebaseCore

enum AppBuild {
    static let isInternal = ProcessInfo.processInfo.environment["KEEPSY_INTERNAL_BUILD"] == "1"
}

@main
struct KeepsyApp: App {
    @State private var localization = LocalizationManager.shared

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(localization)
                .environment(\.locale, localization.locale)
        }
    }
}
