//
//  OnboardingView.swift
//  Keepsy
//
//  First-launch onboarding. Order: feature explainers (collection reward,
//  progress) → language selection → city selection → get started.
//  On completion it persists the chosen starting museum and reports back so
//  ContentView can transition into the main experience.
//

import SwiftUI
import CoreLocation

struct OnboardingView: View {
    var localization: LocalizationManager
    /// Reports the chosen starting museum id when onboarding finishes.
    let onFinish: (String) -> Void

    @State private var step: Int = 0
    @State private var isMovingForward: Bool = true
    @State private var locationManager = LocationManager()
    @State private var selectedMuseumId: String = MuseumConfig.shared.museums.first?.id ?? "capodimonte"

    private let lastStep = 3

    var body: some View {
        ZStack {
            content
                .id(step)
                .transition(.asymmetric(
                    insertion: .move(edge: isMovingForward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: isMovingForward ? .leading : .trailing).combined(with: .opacity)
                ))
        }
        .onAppear {
            if let closest = locationManager.closestMuseum(from: MuseumConfig.shared.museums) {
                selectedMuseumId = closest.id
            }
        }
        .onChange(of: locationManager.lastKnownLocation) { _, newLocation in
            guard newLocation != nil,
                  let closest = locationManager.closestMuseum(from: MuseumConfig.shared.museums) else { return }
            selectedMuseumId = closest.id
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0:
            OnboardingCollectionRewardStep(onContinue: advance)
        case 1:
            OnboardingProgressStep(onBack: back, onContinue: advance)
        case 2:
            OnboardingSelectionStep(
                title: "WHERE SHOULD YOUR\nEXPERIENCE START?",
                subtitle: "Always updating...",
                searchPrompt: "Your city",
                options: cityOptions,
                selectedID: $selectedMuseumId,
                buttonTitle: "CONFIRM",
                onBack: back,
                onConfirm: advance
            )
        default:
            OnboardingGetStartedStep(onBack: back, onStart: finish)
        }
    }

    // MARK: - Options

    private var cityOptions: [OnboardingOption] {
        // One option per city; cities ordered closest-first when a location is known.
        struct City { let museumId: String; let name: String; let flag: String }
        let cities = [
            City(museumId: "capodimonte", name: "Naples", flag: "🇮🇹"),
            City(museumId: "uffizi", name: "Florence", flag: "🇮🇹"),
            City(museumId: "prado", name: "Madrid", flag: "🇪🇸"),
            City(museumId: "moma", name: "New York", flag: "🇺🇸"),
        ]
        let ordered = sortByDistance(cities.map { ($0.museumId, $0.name, $0.flag) })
        return ordered.map { museumId, name, flag in
            let count = MuseumConfig.shared.museums.filter { $0.id == museumId }.count
            return OnboardingOption(
                id: museumId,
                title: "\(name) \(flag)",
                subtitle: localization.string("\(count) Museum")
            )
        }
    }

    private func sortByDistance(_ items: [(String, String, String)]) -> [(String, String, String)] {
        guard let userLoc = locationManager.lastKnownLocation else { return items }
        return items.sorted { a, b in
            guard let m1 = MuseumConfig.shared.museums.first(where: { $0.id == a.0 }) else { return false }
            guard let m2 = MuseumConfig.shared.museums.first(where: { $0.id == b.0 }) else { return true }
            let d1 = userLoc.distance(from: CLLocation(latitude: m1.latitude, longitude: m1.longitude))
            let d2 = userLoc.distance(from: CLLocation(latitude: m2.latitude, longitude: m2.longitude))
            return d1 < d2
        }
    }

    // MARK: - Navigation

    private func advance() {
        isMovingForward = true
        withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
            step = min(lastStep, step + 1)
        }
    }

    private func back() {
        isMovingForward = false
        withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
            step = max(0, step - 1)
        }
    }

    private func finish() {
        UserDefaults.standard.set(selectedMuseumId, forKey: "currentCity")
        UserDefaults.standard.set(selectedMuseumId, forKey: "lastSelectedMuseumId")
        onFinish(selectedMuseumId)
    }
}
