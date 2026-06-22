//
//  OnboardingView.swift
//  Keepsy
//
//  First-launch onboarding. Order: get started → collection reward → progress.
//  Starting museum is auto-detected from location (no manual picker). On
//  completion it persists the chosen starting museum and reports back so
//  ContentView can transition into the main experience.
//

import SwiftUI
import CoreLocation

struct OnboardingView: View {
    /// Reports the chosen starting museum id when onboarding finishes.
    let onFinish: (String) -> Void

    @State private var step: Int = 0
    @State private var isMovingForward: Bool = true
    @State private var locationManager = LocationManager()
    @State private var selectedMuseumId: String = MuseumConfig.shared.museums.first?.id ?? "capodimonte"

    private let lastStep = 2

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
            OnboardingGetStartedStep(onStart: advance)
        case 1:
            OnboardingCollectionRewardStep(onBack: back, onContinue: advance)
        default:
            OnboardingProgressStep(onBack: back, onContinue: finish)
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
