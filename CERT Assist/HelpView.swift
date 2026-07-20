//
//  HelpView.swift
//  CERT Assist
//

import SwiftUI

struct HelpView: View {

    @Environment(\.openURL) private var openURL
    @State private var showOnboarding = false

    var body: some View {
        NavigationStack {
            List {
                Section("Learn") {
                    NavigationLink {
                        ManualView()
                    } label: {
                        Label("User Manual", systemImage: "book.fill")
                    }

                    Button {
                        showOnboarding = true
                    } label: {
                        Label("Feature Tour", systemImage: "sparkles")
                            .foregroundStyle(.primary)
                    }
                }

                Section("Support") {
                    Button {
                        if let url = URL(string: "mailto:frank@w6fgc.com?subject=CERT%20Assist%20Feedback") {
                            openURL(url)
                        }
                    } label: {
                        Label("Email Developer", systemImage: "envelope")
                            .foregroundStyle(.primary)
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: "1.0")
                    LabeledContent("Developer", value: "Frank Gadot")
                    LabeledContent("Contact", value: "frank@w6fgc.com")
                }
            }
            .navigationTitle("Help")
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingView {
                    showOnboarding = false
                }
            }
        }
    }
}

// MARK: - Manual View

struct ManualView: View {

    private struct ManualSection {
        let id: String
        let icon: String
        let title: String
        let content: String
    }

    private let sections: [ManualSection] = [
        .init(id: "start", icon: "person.badge.plus", title: "Getting Started",
              content: """
              Check in when your team activation begins:

              1. Open CERT Assist and tap Check In.
              2. Enter your team's server URL (e.g., https://sapphire.certassist.us).
              3. Enter the member PIN provided by your team leader.
              4. Fill in your name, role, and available equipment.
              5. Tap Check In — you appear on the dashboard immediately.

              The server URL and PIN are saved automatically after a successful check-in.
              """),

        .init(id: "status", icon: "person.circle", title: "Your Status",
              content: """
              Keep your status current so your team leader can coordinate effectively:

              • Available — ready to receive assignments
              • Assigned — actively working on a task
              • Unavailable — temporarily unable to respond
              • Injured — medical attention needed
              • Needs Help — urgent assistance required

              Update your status using the segmented control on the Status tab.
              """),

        .init(id: "reports", icon: "exclamationmark.bubble", title: "Submitting Reports",
              content: """
              File an ICS-213 report when you observe something requiring attention:

              1. Go to the Reports tab and tap New Report.
              2. Select the incident type (Tree Down, Flooding, Medical Need, etc.).
              3. Set severity — Low, Medium, High, or Life Safety.
              4. Enter the location and a description of what you observed.
              5. Tap Submit.

              High and Life Safety reports automatically escalate to County EOC. Your team leader can reply — watch the Reports tab for responses.
              """),

        .init(id: "tasks", icon: "checklist", title: "Tasks",
              content: """
              The Tasks tab shows work assigned to you:

              • Open — waiting to start
              • Assigned — in progress
              • Completed — finished
              • Cancelled — no longer needed

              Tap any task to view details, add notes, or mark it complete. Tasks assigned to your sub-team also appear here.
              """),

        .init(id: "map", icon: "map", title: "Map",
              content: """
              The Map tab shows your current GPS location updated in real time.

              Use it to:
              • Confirm your position before reporting an address
              • Navigate to an assigned area
              • Track your movement during a field operation

              Location updates automatically while the app is in the foreground.
              """),

        .init(id: "log", icon: "doc.text", title: "Incident Log",
              content: """
              The Log tab shows a chronological record of all activity during the activation:

              • Member check-ins and check-outs
              • Report submissions and updates
              • Task assignments and completions
              • Status changes

              Use this for documentation and after-action review.
              """),

        .init(id: "contact", icon: "envelope", title: "Contact & Support",
              content: """
              For app questions or feedback:

              Developer: Frank Gadot
              Email: frank@w6fgc.com

              For operational questions during an activation, contact your Team Leader or County EOC directly — not the app developer.
              """),
    ]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // Table of contents card
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Table of Contents")
                            .font(.headline)
                            .padding(.bottom, 6)

                        ForEach(sections, id: \.id) { section in
                            Button {
                                withAnimation {
                                    proxy.scrollTo(section.id, anchor: .top)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: section.icon)
                                        .frame(width: 20)
                                        .foregroundStyle(.blue)
                                    Text(section.title)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 8)
                            }

                            if section.id != sections.last?.id {
                                Divider()
                            }
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding()

                    // Content sections
                    ForEach(sections, id: \.id) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Image(systemName: section.icon)
                                    .foregroundStyle(.blue)
                                Text(section.title)
                                    .font(.title2)
                                    .fontWeight(.bold)
                            }
                            .padding(.top, 4)
                            .id(section.id)

                            Text(section.content)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Divider()
                            .padding(.horizontal)
                    }

                    Spacer(minLength: 40)
                }
            }
            .navigationTitle("User Manual")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    HelpView()
}
