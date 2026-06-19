//
//  OnboardingComponents.swift
//  Keepsy
//
//  Shared building blocks for the onboarding flow: background, gradient title,
//  primary CTA button, a back header, and the generic search + radio selection
//  step reused by the language and city screens.
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

// MARK: - Gradient Title

struct OnboardingTitle: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.custom("Helvetica-BoldOblique", size: 26))
                .italic()
                .bold()
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: "FF7A00"), Color(hex: "FFB800")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            if let subtitle {
                Text(subtitle)
                    .font(.custom("Helvetica-Oblique", size: 12))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
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

// MARK: - Radio Indicator

struct OnboardingRadio: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    isSelected ? Color(hex: "FF7A00") : Color.gray.opacity(0.5),
                    lineWidth: 2
                )
                .frame(width: 22, height: 22)

            if isSelected {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "FF7A00"), Color(hex: "464646")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 12, height: 12)
            }
        }
    }
}

// MARK: - Generic Selection Step (language & city)

struct OnboardingOption: Identifiable {
    let id: String
    let title: String       // includes flag emoji
    let subtitle: String
}

struct OnboardingSelectionStep: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let searchPrompt: LocalizedStringKey
    let options: [OnboardingOption]
    @Binding var selectedID: String
    let buttonTitle: LocalizedStringKey
    let onBack: () -> Void
    let onConfirm: () -> Void

    @State private var searchText: String = ""

    private var filtered: [OnboardingOption] {
        searchText.isEmpty
            ? options
            : options.filter { $0.title.lowercased().contains(searchText.lowercased()) }
    }

    var body: some View {
        ZStack {
            OnboardingBackground()

            VStack(spacing: 0) {
                OnboardingBackHeader(onBack: onBack)
                    .padding(.bottom, 35)

                OnboardingTitle(title: title, subtitle: subtitle)
                    .padding(.bottom, 28)

                searchBar
                    .padding(.bottom, 24)

                listCard

                Spacer()

                OnboardingPrimaryButton(title: buttonTitle, action: onConfirm)
            }
        }
        .ignoresSafeArea()
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.gray)
                .font(.system(size: 18))

            TextField("", text: $searchText, prompt: Text(searchPrompt).foregroundStyle(.white.opacity(0.5)))
                .foregroundStyle(.white)
                .font(.custom("Helvetica", size: 16))
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 16)
        .frame(height: 55)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.4)))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: [Color(hex: "B1B1B1"), Color(hex: "464646")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
        )
        .padding(.horizontal, 24)
    }

    private var listCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, option in
                Button(action: {
                    HapticManager.shared.triggerSelection()
                    selectedID = option.id
                }) {
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(option.title)
                                .font(.custom("Helvetica-Bold", size: 18))
                                .foregroundStyle(.white)
                            Text(option.subtitle)
                                .font(.custom("Helvetica-Oblique", size: 11))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        Spacer()
                        OnboardingRadio(isSelected: selectedID == option.id)
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 18)
                }

                if idx < filtered.count - 1 {
                    Divider()
                        .background(Color.white.opacity(0.12))
                        .padding(.horizontal, 18)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: "121214").opacity(0.85)))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: "B1B1B1"), lineWidth: 2)
        )
        .padding(.horizontal, 24)
    }
}
