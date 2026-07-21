//
//  IncidentLogView.swift
//  CERT Command
//
//  Created by frank gadot on 2026.06.09.
//

import SwiftUI
import UniformTypeIdentifiers

struct IncidentLogView: View {
    
    @State private var manager = IncidentManager.shared
    @State private var showingExportOptions = false
    @State private var exportedText = ""
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let incident = manager.currentIncident {
                        // Incident Header
                        VStack(alignment: .leading, spacing: 8) {
                            Text(incident.name)
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            HStack {
                                Label("Started", systemImage: "clock")
                                    .font(.caption)
                                Text(incident.startDate, style: .date)
                                    .font(.caption)
                                Text(incident.startDate, style: .time)
                                    .font(.caption)
                            }
                            .foregroundStyle(.secondary)
                            
                            if let endDate = incident.endDate {
                                HStack {
                                    Label("Ended", systemImage: "clock.fill")
                                        .font(.caption)
                                    Text(endDate, style: .date)
                                        .font(.caption)
                                    Text(endDate, style: .time)
                                        .font(.caption)
                                }
                                .foregroundStyle(.secondary)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    // Statistics
                    HStack(spacing: 12) {
                        StatCard(
                            title: "Members",
                            value: "\(manager.members.count)",
                            icon: "person.3.fill",
                            color: .blue
                        )
                        
                        StatCard(
                            title: "Reports",
                            value: "\(manager.reports.count)",
                            icon: "exclamationmark.bubble.fill",
                            color: .orange
                        )
                        
                        StatCard(
                            title: "Tasks",
                            value: "\(manager.tasks.count)",
                            icon: "checklist",
                            color: .green
                        )
                    }
                    
                    // Timeline
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Timeline")
                            .font(.headline)
                        
                        if timelineEvents.isEmpty {
                            Text("No events yet")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                        } else {
                            ForEach(timelineEvents) { event in
                                TimelineEventRow(event: event)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding()
            }
            .navigationTitle("Incident Log")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        exportLog()
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .sheet(isPresented: $showingExportOptions) {
                ExportSheet(text: exportedText)
            }
        }
    }
    
    var timelineEvents: [TimelineEvent] {
        var events: [TimelineEvent] = []
        
        // Add reports
        for report in manager.reports {
            events.append(TimelineEvent(
                date: report.reportedAt,
                type: .report,
                title: report.type.rawValue,
                description: report.notes
            ))
        }
        
        // Add tasks
        for task in manager.tasks {
            events.append(TimelineEvent(
                date: task.createdAt,
                type: .taskCreated,
                title: task.title,
                description: task.description
            ))
            
            if let completedAt = task.completedAt {
                events.append(TimelineEvent(
                    date: completedAt,
                    type: .taskCompleted,
                    title: task.title,
                    description: ""
                ))
            }
        }
        
        // Add member check-ins
        for member in manager.members {
            events.append(TimelineEvent(
                date: member.lastUpdated,
                type: .memberCheckIn,
                title: "\(member.name) checked in",
                description: member.role
            ))
        }
        
        return events.sorted { $0.date > $1.date }
    }
    
    func exportLog() {
        var text = ""
        
        if let incident = manager.currentIncident {
            text += "CERT Field Board - Incident Log\n"
            text += "================================\n\n"
            text += "Incident: \(incident.name)\n"
            text += "Start: \(incident.startDate.formatted(date: .long, time: .standard))\n"
            
            if let endDate = incident.endDate {
                text += "End: \(endDate.formatted(date: .long, time: .standard))\n"
            }
            text += "\n"
        }
        
        text += "Summary\n"
        text += "-------\n"
        text += "Members: \(manager.members.count)\n"
        text += "Reports: \(manager.reports.count)\n"
        text += "Tasks: \(manager.tasks.count)\n\n"
        
        text += "Members\n"
        text += "-------\n"
        for member in manager.members {
            text += "• \(member.name) (\(member.role)) - \(member.status.rawValue)\n"
        }
        text += "\n"
        
        text += "Reports\n"
        text += "-------\n"
        for report in manager.reports.sorted(by: { $0.reportedAt < $1.reportedAt }) {
            text += "[\(report.reportedAt.formatted(date: .numeric, time: .shortened))] "
            text += "\(report.type.rawValue) - \(report.severity.rawValue)\n"
            if !report.notes.isEmpty {
                text += "  Notes: \(report.notes)\n"
            }
            text += "  Status: \(report.status.rawValue)\n\n"
        }
        
        text += "Tasks\n"
        text += "-----\n"
        for task in manager.tasks.sorted(by: { $0.createdAt < $1.createdAt }) {
            text += "[\(task.createdAt.formatted(date: .numeric, time: .shortened))] "
            text += "\(task.title) - \(task.status.rawValue)\n"
            if !task.description.isEmpty {
                text += "  \(task.description)\n"
            }
            text += "\n"
        }
        
        exportedText = text
        showingExportOptions = true
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            
            Text(value)
                .font(.title)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct TimelineEvent: Identifiable {
    let id = UUID()
    let date: Date
    let type: EventType
    let title: String
    let description: String
    
    enum EventType {
        case report
        case taskCreated
        case taskCompleted
        case memberCheckIn
        
        var icon: String {
            switch self {
            case .report: return "exclamationmark.bubble.fill"
            case .taskCreated: return "plus.circle.fill"
            case .taskCompleted: return "checkmark.circle.fill"
            case .memberCheckIn: return "person.badge.plus"
            }
        }
        
        var color: Color {
            switch self {
            case .report: return .orange
            case .taskCreated: return .blue
            case .taskCompleted: return .green
            case .memberCheckIn: return .purple
            }
        }
    }
}

struct TimelineEventRow: View {
    let event: TimelineEvent
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: event.type.icon)
                .foregroundStyle(event.type.color)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                if !event.description.isEmpty {
                    Text(event.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Text(event.date, style: .relative) + Text(" ago")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct ExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    let text: String
    
    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .padding()
            }
            .navigationTitle("Export Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: text) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}

#Preview {
    IncidentLogView()
}
