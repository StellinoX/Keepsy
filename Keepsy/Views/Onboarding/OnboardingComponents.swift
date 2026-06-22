//
//  OnboardingComponents.swift
//  Keepsy
//
//  Shared building blocks for the onboarding flow: background, gradient title,
//  primary CTA button, and a back header.
//

import SwiftUI

// MARK: - Background

struct OnboardingBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "06080B"), Color(hex: "14193B")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            GridBackground()
        }
    }
}

// MARK: - Primary Button

struct OnboardingPrimaryButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: {
            HapticManager.shared.triggerImpact(style: .medium)
            action()
        }) {
            Text(title)
                .font(.custom("Helvetica-BoldOblique", size: 18))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 27)
                        .fill(Color(hex: "D8D8D8"))
                        .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
                )
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 48)
    }
}

// MARK: - Back Header

struct OnboardingBackHeader: View {
    let onBack: () -> Void

    var body: some View {
        HStack {
            Button(action: {
                HapticManager.shared.triggerImpact(style: .light)
                onBack()
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color(hex: "383838")))
            }
            .accessibilityLabel("Back")
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 64)
    }
}

