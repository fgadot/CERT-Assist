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
    
    var body: some View {
        Group {
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
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
