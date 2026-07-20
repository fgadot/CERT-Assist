//
//  SplashView.swift
//  CERT Assist
//

import SwiftUI

struct SplashView: View {

    @State private var opacity = 0.0
    @State private var scale = 0.85

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.039, green: 0.059, blue: 0.118), Color(red: 0.059, green: 0.106, blue: 0.208)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Image(systemName: "shield.fill")
                    .font(.system(size: 96))
                    .foregroundStyle(Color(red: 0.224, green: 0.710, blue: 0.290))
                    .padding(.bottom, 24)

                Text("CERT Assist")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(.white)

                Text("Community Emergency Response Team")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.top, 6)

                Spacer()

                VStack(spacing: 5) {
                    Text("Developed by Frank Gadot")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.65))
                    Text("frank@w6fgc.com")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.bottom, 48)
            }
            .scaleEffect(scale)
            .opacity(opacity)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.65)) {
                opacity = 1.0
                scale = 1.0
            }
        }
    }
}

#Preview {
    SplashView()
}
