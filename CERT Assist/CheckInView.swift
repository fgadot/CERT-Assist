//
//  CheckInView.swift
//  CERT Assist
//
//  Created by frank gadot on 2026.06.09.
//

import SwiftUI

struct CheckInView: View {

    @State private var manager = IncidentManager.shared
    @State private var showingCheckIn = false
    @State private var pendingStatus: MemberStatus? = nil
    @State private var showStatusConfirmation = false

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
                            manager.checkOut()
                        } label: {
                            Label("Check Out", systemImage: "rectangle.portrait.and.arrow.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
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
                    Image(systemName: "person.badge.shield.checkmark.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.blue)

                    Text("CERT Field Board")
                        .font(.largeTitle)
                        .fontWeight(.bold)

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
                .navigationTitle("Check In")
                .sheet(isPresented: $showingCheckIn) {
                    CheckInSheet()
                }
            }
        }
    }
}

struct CheckInSheet: View {

    @Environment(\.dismiss) private var dismiss
    @State private var manager = IncidentManager.shared

    @State private var name = ""
    @State private var role = "CERT Member"
    @State private var selectedEquipment: Set<Equipment> = []

    // Connection — pre-populated from last saved values
    @AppStorage("certServerURL") private var savedServerURL = ""
    @AppStorage("certMemberPIN") private var savedMemberPIN = ""
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
            // Custom navigation bar — avoids SwiftUI toolbar overload ambiguity
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .disabled(manager.isCheckingIn)

                Spacer()

                Text("Check In")
                    .font(.headline)

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
                            savedMemberPIN = memberPIN
                            dismiss()
                        }
                    }
                }
                .fontWeight(.semibold)
                .disabled(!canCheckIn)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(.systemGroupedBackground))
            .overlay(alignment: .bottom) {
                Divider()
            }

            Form {
                Section {
                    TextField("https://sapphire.certassist.us", text: $serverURL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    SecureField("Member PIN", text: $memberPIN)
                        .keyboardType(.default)
                } header: {
                    Text("Server Connection")
                } footer: {
                    Text("Your team leader will provide the server URL and PIN.")
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
            serverURL = savedServerURL
            memberPIN = savedMemberPIN
        }
        .alert("Check-In Failed", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(manager.checkInError ?? "Unknown error")
        }
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
