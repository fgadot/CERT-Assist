//
//  UpdateRequiredView.swift
//  CERT Assist
//

import SwiftUI

struct UpdateRequiredView: View {

    // Replace with the actual App Store URL once the app is live
    private let appStoreURL = URL(string: "https://apps.apple.com/search?term=CERT+Assist&entity=software")!

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue)

                VStack(spacing: 12) {
                    Text("Update Required")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("A newer version of CERT Assist is required to connect to this server. Please update to continue.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Button {
                    UIApplication.shared.open(appStoreURL)
                } label: {
                    Label("Update on the App Store", systemImage: "arrow.up.right")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 40)

                Spacer()

                Text("Current version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 24)
            }
        }
    }
}

#Preview {
    UpdateRequiredView()
}
