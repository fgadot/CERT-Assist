//
//  OnboardingView.swift
//  CERT Assist
//

import SwiftUI

private struct OnboardingSlide {
    let icon: String
    let iconColor: Color
    let title: String
    let body: String
}

private let certGreen = Color(red: 0.224, green: 0.710, blue: 0.290)

private let slides: [OnboardingSlide] = [
    .init(icon: "shield.fill",
          iconColor: certGreen,
          title: "Welcome to CERT Assist",
          body: "Coordinate with your CERT team during emergency activations — directly from your iPhone."),
    .init(icon: "network",
          iconColor: certGreen,
          title: "Connect to Your Team",
          body: "Enter your team's server URL and the member PIN provided by your team leader. Both are saved automatically after your first check-in."),
    .init(icon: "person.badge.shield.checkmark.fill",
          iconColor: certGreen,
          title: "Check In",
          body: "Check in with your name, role, and available equipment. Your team leader sees you appear on the dashboard in real time."),
    .init(icon: "exclamationmark.bubble.fill",
          iconColor: .red,
          title: "Submit Reports",
          body: "File ICS-213 incident reports from the field. High-severity reports automatically escalate to County EOC. Watch for replies from your team leader."),
    .init(icon: "checklist",
          iconColor: certGreen,
          title: "Tasks & Map",
          body: "View and complete tasks assigned to you. Use the map to confirm your GPS position and navigate to assigned locations."),
    .init(icon: "checkmark.seal.fill",
          iconColor: certGreen,
          title: "You're All Set",
          body: "Ask your team leader for your server URL and member PIN before activation. Tap Get Started to begin."),
]

struct OnboardingView: View {

    let onComplete: () -> Void

    @State private var current = 0

    var isLast: Bool { current == slides.count - 1 }

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $current) {
                ForEach(Array(slides.enumerated()), id: \.offset) { index, slide in
                    slideView(slide)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            // Skip button — top right
            HStack {
                Spacer()
                if !isLast {
                    Button("Skip") {
                        onComplete()
                    }
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.top, 60)
                }
            }
        }
        .overlay(alignment: .bottom) {
            Button(isLast ? "Get Started" : "Next") {
                if isLast {
                    onComplete()
                } else {
                    withAnimation {
                        current += 1
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 64)
        }
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private func slideView(_ slide: OnboardingSlide) -> some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: slide.icon)
                .font(.system(size: 88))
                .foregroundStyle(slide.iconColor)

            VStack(spacing: 12) {
                Text(slide.title)
                    .font(.title)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text(slide.body)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 32)
            }

            Spacer()
            Spacer()
        }
        .padding()
    }
}

#Preview {
    OnboardingView(onComplete: {})
}
