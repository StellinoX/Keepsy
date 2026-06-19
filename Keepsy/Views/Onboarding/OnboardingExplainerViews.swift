//
//  OnboardingExplainerViews.swift
//  Keepsy
//
//  The three illustrative onboarding screens: collection reward, progress
//  tracking, and the final "get started" call to action.
//

import SwiftUI

// MARK: - Collection Reward

struct OnboardingCollectionRewardStep: View {
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            OnboardingBackground()
            
            VStack(spacing: 0) {
                Image("modal")
                    .resizable()
                    .scaledToFit()
                    .padding(.horizontal, 16)
                
                Text("COMPLETE ANY COLLECTION\nFOR A SPECIAL REWARD!")
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
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 24)
                    .padding(.top, 28) // Pushed slightly lower under the image
                
                Spacer()

                OnboardingPrimaryButton(title: "CONTINUE", action: onContinue)
            }
            
            OnboardingBackHeader(onBack: onBack)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Progress Tracking

struct OnboardingProgressStep: View {
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            OnboardingBackground()
            
            VStack(spacing: 0) {
                Spacer() // Centers the group vertically by pushing it down from the top
                
                Image("collections")
                    .resizable()
                    .scaledToFit()
                    .padding(.horizontal, 16)
                
                Text("KEEP TRACK OF\nYOUR PROGRESS!")
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
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 24)
                    .padding(.top, 28) // Spacing under the image
                
                Spacer()

                OnboardingPrimaryButton(title: "I'M READY", action: onContinue)
            }
            
            OnboardingBackHeader(onBack: onBack)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Get Started

struct OnboardingGetStartedStep: View {
    let onBack: () -> Void
    let onStart: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            OnboardingBackground()
            
            VStack(spacing: 0) {
                Image("Cards+Icon")
                    .resizable()
                    .scaledToFit()
                
                Text("READY TO ENHANCE YOUR\nMUSEUM EXPERIENCE?")
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
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 24)
                    .padding(.top, 28) // Spacing under the image
                
                Spacer()

                OnboardingPrimaryButton(title: "GET STARTED", action: onStart)
            }
            
            OnboardingBackHeader(onBack: onBack)
        }
        .ignoresSafeArea()
    }
}
