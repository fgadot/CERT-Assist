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
                                .foregroundStyle(Color(member.status.color))
                            
                            Text(member.name)
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text(member.role)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            
                            // Status Picker
                            Picker("Status", selection: Binding(
                                get: { member.status },
                                set: { manager.updateMemberStatus($0) }
                            )) {
                                ForEach(MemberStatus.allCases, id: \.self) { status in
                                    Label(status.rawValue, systemImage: status.icon)
                                        .tag(status)
                                }
                            }
                            .pickerStyle(.segmented)
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
                                            .foregroundStyle(Color(otherMember.status.color))
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
                                            .foregroundStyle(Color(otherMember.status.color))
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
    
    let roles = [
        "CERT Member",
        "Team Leader",
        "Medical Specialist",
        "Communications",
        "Search & Rescue",
        "Logistics"
    ]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Your Information") {
                    TextField("Full Name", text: $name)
                    
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
            .navigationTitle("Check In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Check In") {
                        manager.checkIn(
                            name: name,
                            role: role,
                            equipment: Array(selectedEquipment)
                        )
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
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
