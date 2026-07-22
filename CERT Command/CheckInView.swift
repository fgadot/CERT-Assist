//
//  CheckInView.swift
//  CERT Command
//
//  Created by frank gadot on 2026.06.09.
//

import SwiftUI

struct CheckInView: View {

    @State private var manager = IncidentManager.shared
    @State private var locationManager = LocationManager.shared
    @State private var showingCheckIn = false
    @State private var pendingStatus: MemberStatus? = nil
    @State private var showStatusConfirmation = false
    @State private var isPushingLocation = false
    @State private var showCheckOutConfirmation = false

    var body: some View {
        NavigationStack {
            if let member = manager.currentMember {
                // Already checked in
                ScrollView {
                    VStack(spacing: 24) {
                        // Member Status Card
                        VStack(spacing: 16) {
                            Image(systemName: member.status.icon)
                                .font(.system(size: 60))
                                .foregroundStyle(member.status.color)

                            Text(member.name)
                                .font(.title2)
                                .fontWeight(.bold)

                            Text(member.role)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            if let teamName = member.subTeamName {
                                Text(teamName)
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 5)
                                    .background(subTeamBadgeColor(member.subTeamColor))
                                    .clipShape(Capsule())
                            }

                            // Status grid — 2×2, tap to activate, tap again to deactivate (with confirmation)
                            let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)
                            LazyVGrid(columns: columns, spacing: 10) {
                                ForEach(MemberStatus.actionCases, id: \.self) { status in
                                    Button {
                                        pendingStatus = status
                                        showStatusConfirmation = true
                                    } label: {
                                        VStack(spacing: 5) {
                                            Image(systemName: status.icon)
                                                .font(.title3)
                                            Text(status.rawValue)
                                                .font(.caption)
                                                .fontWeight(.medium)
                                                .minimumScaleFactor(0.8)
                                                .lineLimit(1)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(
                                            member.status == status
                                                ? status.color
                                                : Color(.tertiarySystemBackground)
                                        )
                                        .foregroundStyle(
                                            member.status == status ? .white : status.color
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        // Equipment
                        if !member.equipment.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Equipment")
                                    .font(.headline)

                                FlowLayout(spacing: 8) {
                                    ForEach(member.equipment, id: \.self) { equipment in
                                        Label(equipment.rawValue, systemImage: equipment.icon)
                                            .font(.caption)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(Color(.tertiarySystemBackground))
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        // Location Sharing
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("Location Sharing", systemImage: "location.fill")
                                    .font(.headline)
                                Spacer()
                                Picker("", selection: Binding(
                                    get: { manager.locationTrackingMode },
                                    set: { manager.locationTrackingMode = $0 }
                                )) {
                                    Text("Auto").tag(IncidentManager.LocationTrackingMode.automatic)
                                    Text("Manual").tag(IncidentManager.LocationTrackingMode.manual)
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 130)
                            }

                            if manager.locationTrackingMode == .automatic {
                                Label("Updating every 30 seconds", systemImage: "arrow.clockwise")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    if let ts = member.location?.timestamp {
                                        Label("Last update: \(ts.formatted(.relative(presentation: .named)))",
                                              systemImage: "clock")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Label("Location not shared yet", systemImage: "location.slash")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Button {
                                        isPushingLocation = true
                                        Swift.Task {
                                            await manager.pushCurrentLocation()
                                            isPushingLocation = false
                                        }
                                    } label: {
                                        Label(isPushingLocation ? "Updating…" : "Share My Location Now",
                                              systemImage: "location.fill")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(isPushingLocation || locationManager.currentLocation == nil)
                                }
                            }
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        // Team Members
                        if manager.members.count > 1 {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Team Members (\(manager.members.count))")
                                    .font(.headline)

                                ForEach(manager.members) { otherMember in
                                    HStack {
                                        Image(systemName: otherMember.status.icon)
                                            .foregroundStyle(otherMember.status.color)
                                            .frame(width: 24)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(otherMember.name)
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                            Text(otherMember.role)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        Text(otherMember.status.rawValue)
                                            .font(.caption)
                                            .foregroundStyle(otherMember.status.color)
                                    }
                                    .padding(.vertical, 4)

                                    if otherMember.id != manager.members.last?.id {
                                        Divider()
                                    }
                                }
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        // Check Out Button
                        Button(role: .destructive) {
                            showCheckOutConfirmation = true
                        } label: {
                            Label("Check Out", systemImage: "rectangle.portrait.and.arrow.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .confirmationDialog("Check Out", isPresented: $showCheckOutConfirmation) {
                            Button("Check Out", role: .destructive) {
                                manager.checkOut()
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("End your session and check out?")
                        }
                    }
                    .padding()
                }
                .navigationTitle("My Status")
                .alert("Confirm Status", isPresented: $showStatusConfirmation, presenting: pendingStatus) { status in
                    Button(member.status == status ? "Disable" : "Enable",
                           role: member.status == status ? .destructive : nil) {
                        manager.updateMemberStatus(member.status == status ? .available : status)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: { status in
                    Text(member.status == status
                         ? "Disable \(status.rawValue.uppercased()) status?"
                         : "Enable \(status.rawValue.uppercased()) status?")
                }
            } else {
                // Not checked in yet
                VStack(spacing: 24) {
                    Text("Check In")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 16)

                    Image(systemName: "person.badge.shield.checkmark.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.blue)

                    Text("CERT Field Board")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Check in to activate your CERT status and begin coordinating with your team")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button {
                        showingCheckIn = true
                    } label: {
                        Label("Check In", systemImage: "person.badge.plus")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.horizontal, 40)
                }
                .navigationTitle("")
                .sheet(isPresented: $showingCheckIn) {
                    CheckInSheet()
                }
            }
        }
        .alert("Checked Out by Team Leader", isPresented: Binding(
            get: { manager.remoteCheckoutMessage != nil },
            set: { if !$0 { manager.remoteCheckoutMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                manager.remoteCheckoutMessage = nil
            }
        } message: {
            Text(manager.remoteCheckoutMessage ?? "")
        }
    }
}

struct CheckInSheet: View {

    @Environment(\.dismiss) private var dismiss
    @State private var manager = IncidentManager.shared

    @State private var name = ""
    @State private var role = "CERT Member"
    @State private var selectedEquipment: Set<Equipment> = []
    @State private var showHelp = false

    // Connection — pre-populated from last saved values
    @AppStorage("certServerURL") private var savedServerURL = ""
    @State private var serverURL = ""
    @State private var memberPIN = ""

    @State private var showError = false

    let roles = [
        "CERT Member",
        "Team Leader",
        "Medical Specialist",
        "Communications",
        "Search & Rescue",
        "Logistics"
    ]

    var canCheckIn: Bool {
        !name.isEmpty && !serverURL.isEmpty && !memberPIN.isEmpty && !manager.isCheckingIn
    }

    var body: some View {
        VStack(spacing: 0) {
            // Custom navigation bar — ZStack keeps title truly centered regardless of button widths
            ZStack {
                Text("Check In")
                    .font(.headline)
                    .frame(maxWidth: .infinity)

                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(manager.isCheckingIn)

                    Button {
                        showHelp = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .padding(.leading, 8)

                    Spacer()

                    Button(manager.isCheckingIn ? "Checking In…" : "Check In") {
                        Swift.Task {
                            await manager.checkIn(
                                name: name,
                                role: role,
                                equipment: Array(selectedEquipment),
                                serverURL: serverURL,
                                memberPIN: memberPIN
                            )
                            if manager.checkInError != nil {
                                showError = true
                            } else {
                                savedServerURL = serverURL
                                KeychainHelper.set(memberPIN, forKey: "certMemberPIN")
                                dismiss()
                            }
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!canCheckIn)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(.systemGroupedBackground))
            .overlay(alignment: .bottom) {
                Divider()
            }

            Form {
                Section {
                    TextField("server", text: $serverURL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: serverURL) { _, newValue in
                            let lower = newValue.lowercased()
                            if lower != newValue { serverURL = lower }
                        }
                    SecureField("PIN", text: $memberPIN)
                        .keyboardType(.default)
                } header: {
                    Text("Server Connection")
                } footer: {
                    Text("Your team leader will provide the server address and PIN.")
                }

                Section("Your Information") {
                    TextField("Full Name", text: $name)
                        .autocorrectionDisabled()

                    Picker("Role", selection: $role) {
                        ForEach(roles, id: \.self) { role in
                            Text(role)
                        }
                    }
                }

                Section("Equipment Available") {
                    ForEach(Equipment.allCases, id: \.self) { equipment in
                        Toggle(isOn: Binding(
                            get: { selectedEquipment.contains(equipment) },
                            set: { isSelected in
                                if isSelected {
                                    selectedEquipment.insert(equipment)
                                } else {
                                    selectedEquipment.remove(equipment)
                                }
                            }
                        )) {
                            Label(equipment.rawValue, systemImage: equipment.icon)
                        }
                    }
                }
            }
        }
        .onAppear {
            var url = savedServerURL
            if url.hasPrefix("https://") { url = String(url.dropFirst(8)) }
            else if url.hasPrefix("http://") { url = String(url.dropFirst(7)) }
            serverURL = url.lowercased()
            memberPIN = KeychainHelper.get("certMemberPIN") ?? ""
        }
        .alert("Check-In Failed", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(manager.checkInError ?? "Unknown error")
        }
        .sheet(isPresented: $showHelp) {
            HelpView()
        }
    }
}

private func subTeamBadgeColor(_ colorName: String?) -> Color {
    switch colorName?.lowercased() {
    case "red":    return Color(red: 0.863, green: 0.208, blue: 0.271)
    case "blue":   return Color(red: 0.051, green: 0.431, blue: 0.992)
    case "green":  return Color(red: 0.098, green: 0.529, blue: 0.329)
    case "yellow": return Color(red: 1.000, green: 0.753, blue: 0.027)
    case "purple": return Color(red: 0.435, green: 0.259, blue: 0.757)
    case "orange": return Color(red: 0.992, green: 0.494, blue: 0.078)
    case "teal":   return Color(red: 0.125, green: 0.788, blue: 0.592)
    case "pink":   return Color(red: 0.839, green: 0.200, blue: 0.518)
    default:       return Color(.systemGray)
    }
}

// Simple flow layout for equipment tags
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.frames[index].minX,
                                     y: bounds.minY + result.frames[index].minY),
                         proposal: .unspecified)
        }
    }

    struct FlowResult {
        var frames: [CGRect] = []
        var size: CGSize = .zero

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if currentX + size.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }

                frames.append(CGRect(origin: CGPoint(x: currentX, y: currentY), size: size))

                currentX += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }

            self.size = CGSize(width: maxWidth, height: currentY + lineHeight)
        }
    }
}

#Preview {
    CheckInView()
}
