//
//  LocalizationManager.swift
//  Keepsy
//
//  Manages the in-app display language. The user picks a language during
//  onboarding (or later); the choice is persisted and applied live — no app
//  restart. SwiftUI `Text` literals re-localize via the `\.locale` environment
//  value injected at the app root, and dynamic `String(localized:)` lookups use
//  the matching `.lproj` bundle exposed here.
//

import SwiftUI

@MainActor
@Observable
final class LocalizationManager {
    static let shared = LocalizationManager()

    /// Languages the app ships translations for. `rawValue` is the locale code.
    enum AppLanguage: String, CaseIterable, Identifiable {
        case english = "en"
        case italian = "it"

        var id: String { rawValue }

        /// Title shown in the language picker, e.g. "English (US)".
        var displayName: String {
            switch self {
            case .english: return "English (US)"
            case .italian: return "Italian"
            }
        }

        /// Endonym shown as the row subtitle, e.g. "Italiano".
        var nativeName: String {
            switch self {
            case .english: return "English"
            case .italian: return "Italiano"
            }
        }

        var flag: String {
            switch self {
            case .english: return "🇺🇸"
            case .italian: return "🇮🇹"
            }
        }
    }

    var language: AppLanguage = .english

    private init() {}

    /// Locale injected into the SwiftUI environment so `Text` literals localize live.
    var locale: Locale { Locale(identifier: language.rawValue) }

    /// The `.lproj` bundle for the selected language. Falls back to the main bundle.
    var bundle: Bundle {
        guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }

    /// Resolves a localized string from the selected-language bundle. Use for
    /// dynamic strings built outside of SwiftUI `Text` (e.g. passed as `String`).
    func string(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: bundle, locale: locale)
    }
}
