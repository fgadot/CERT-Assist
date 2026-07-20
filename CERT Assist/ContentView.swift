//
//  ContentView.swift
//  CERT Assist
//
//  Created by frank gadot on 2026.06.09.
//

import SwiftUI

struct ContentView: View {

    @State private var manager = IncidentManager.shared
    @State private var selectedTab = 0

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showSplash = true
    @State private var showOnboarding = false

    var body: some View {
        ZStack {
            mainContent
                .opacity(showSplash ? 0 : 1)

            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                withAnimation(.easeOut(duration: 0.4)) {
                    showSplash = false
                }
                if !hasCompletedOnboarding {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        showOnboarding = true
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView {
                hasCompletedOnboarding = true
                showOnboarding = false
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if !manager.isCheckedIn {
            CheckInView()
        } else {
            TabView(selection: $selectedTab) {
                CheckInView()
                    .tabItem {
                        Label("Status", systemImage: "person.circle.fill")
                    }
                    .tag(0)

                ReportsListView()
                    .tabItem {
                        Label("Reports", systemImage: "exclamationmark.bubble.fill")
                    }
                    .badge(manager.activeReports.count)
                    .tag(1)

                TaskBoardView()
                    .tabItem {
                        Label("Tasks", systemImage: "checklist")
                    }
                    .badge(manager.openTasks.count)
                    .tag(2)

                MapView()
                    .tabItem {
                        Label("Map", systemImage: "map.fill")
                    }
                    .tag(3)

                IncidentLogView()
                    .tabItem {
                        Label("Log", systemImage: "doc.text.fill")
                    }
                    .tag(4)

                HelpView()
                    .tabItem {
                        Label("Help", systemImage: "questionmark.circle.fill")
                    }
                    .tag(5)
            }
        }
    }
}

#Preview {
    ContentView()
}
