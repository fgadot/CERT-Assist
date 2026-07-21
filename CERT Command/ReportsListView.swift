//
//  ReportsListView.swift
//  CERT Command
//
//  Created by frank gadot on 2026.06.09.
//

import SwiftUI
import CoreLocation

struct ReportsListView: View {
    
    @State private var manager = IncidentManager.shared
    @State private var showingNewReport = false
    @State private var selectedReport: IncidentReport?
    
    var body: some View {
        NavigationStack {
            List {
                if manager.reports.isEmpty {
                    ContentUnavailableView(
                        "No Reports Yet",
                        systemImage: "exclamationmark.bubble",
                        description: Text("Create a report when you observe damage or someone needs help")
                    )
                } else {
                    ForEach(manager.reports.sorted(by: { $0.reportedAt > $1.reportedAt })) { report in
                        Button {
                            selectedReport = report
                        } label: {
                            ReportRow(report: report)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Reports")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewReport = true
                    } label: {
                        Label("New Report", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewReport) {
                NewReportSheet()
            }
            .sheet(item: $selectedReport) { report in
                ReportDetailSheet(report: report)
            }
        }
    }
}

struct ReportRow: View {
    
    let report: IncidentReport
    @State private var manager = IncidentManager.shared
    
    var reporterName: String {
        manager.members.first(where: { $0.id == report.reportedBy })?.name ?? "Unknown"
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Type Icon
            Image(systemName: report.type.icon)
                .font(.title2)
                .foregroundStyle(report.severity.color)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(report.type.rawValue)
                    .font(.headline)
                
                if let address = report.location.address {
                    Text(address)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                HStack(spacing: 8) {
                    Label(report.severity.rawValue, systemImage: report.severity.icon)
                        .font(.caption)
                        .foregroundStyle(report.severity.color)
                    
                    Text("•")
                        .foregroundStyle(.secondary)
                    
                    Label(report.status.rawValue, systemImage: report.status.icon)
                        .font(.caption)
                        .foregroundStyle(report.status.color)
                    
                    Text("•")
                        .foregroundStyle(.secondary)
                    
                    Text(report.reportedAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

struct NewReportSheet: View {
    
    @Environment(\.dismiss) private var dismiss
    @State private var manager = IncidentManager.shared
    @State private var locationManager = LocationManager.shared
    
    @State private var reportType: ReportType = .other
    @State private var severity: Severity = .low
    @State private var notes = ""
    @State private var useCurrentLocation = true
    
    var body: some View {
        NavigationStack {
            Form {
                Section("What happened?") {
                    Picker("Type", selection: $reportType) {
                        ForEach(ReportType.allCases, id: \.self) { type in
                            Label(type.rawValue, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                    
                    Picker("Severity", selection: $severity) {
                        ForEach(Severity.allCases, id: \.self) { sev in
                            Label(sev.rawValue, systemImage: sev.icon)
                                .tag(sev)
                        }
                    }
                }
                
                Section("Details") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                Section("Location") {
                    Toggle("Use Current Location", isOn: $useCurrentLocation)
                    
                    if let location = locationManager.currentLocation {
                        HStack {
                            Image(systemName: "location.fill")
                                .foregroundStyle(.blue)
                            Text(String(format: "%.4f, %.4f", location.coordinate.latitude, location.coordinate.longitude))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Location unavailable")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("New Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        submitReport()
                        dismiss()
                    }
                    .disabled(!canSubmit)
                }
            }
        }
    }
    
    var canSubmit: Bool {
        if useCurrentLocation {
            return locationManager.currentLocation != nil && manager.currentMember != nil
        }
        return manager.currentMember != nil
    }
    
    func submitReport() {
        guard let member = manager.currentMember else { return }
        
        let location: LocationData
        if useCurrentLocation, let currentLoc = locationManager.currentLocation {
            location = LocationData(coordinate: currentLoc.coordinate)
        } else {
            // Fallback to a default location
            location = LocationData(latitude: 0, longitude: 0, address: "Unknown")
        }
        
        let report = IncidentReport(
            type: reportType,
            location: location,
            severity: severity,
            notes: notes,
            reportedBy: member.id
        )
        
        manager.addReport(report)
    }
}

struct ReportDetailSheet: View {
    
    @Environment(\.dismiss) private var dismiss
    @State private var manager = IncidentManager.shared
    @State private var report: IncidentReport
    
    init(report: IncidentReport) {
        self.report = report
    }
    
    var reporterName: String {
        manager.members.first(where: { $0.id == report.reportedBy })?.name ?? "Unknown"
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: report.type.icon)
                            .font(.title)
                            .foregroundStyle(report.severity.color)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(report.type.rawValue)
                                .font(.headline)
                            Text(reporterName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Section("Status") {
                    Picker("Status", selection: $report.status) {
                        ForEach(ReportStatus.allCases, id: \.self) { status in
                            Label(status.rawValue, systemImage: status.icon)
                                .tag(status)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: report.status) {
                        manager.updateReport(report)
                    }
                    
                    Picker("Severity", selection: $report.severity) {
                        ForEach(Severity.allCases, id: \.self) { sev in
                            Label(sev.rawValue, systemImage: sev.icon)
                                .tag(sev)
                        }
                    }
                    .onChange(of: report.severity) {
                        manager.updateReport(report)
                    }
                }
                
                if !report.notes.isEmpty {
                    Section("Notes") {
                        Text(report.notes)
                    }
                }
                
                Section("Location") {
                    if let address = report.location.address {
                        Text(address)
                    }
                    Text(String(format: "%.4f, %.4f", report.location.latitude, report.location.longitude))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Section("Timeline") {
                    LabeledContent("Reported") {
                        Text(report.reportedAt, style: .relative) + Text(" ago")
                    }
                    
                    LabeledContent("Last Updated") {
                        Text(report.lastUpdated, style: .relative) + Text(" ago")
                    }
                }
                
                Section {
                    Button("Create Task from Report") {
                        createTask()
                        dismiss()
                    }
                    
                    Button("Delete Report", role: .destructive) {
                        manager.deleteReport(report)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Report Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    func createTask() {
        let task = Task(
            title: "Respond to \(report.type.rawValue)",
            description: report.notes,
            status: .open,
            priority: report.severity,
            location: report.location,
            relatedReportID: report.id
        )
        manager.addTask(task)
    }
}

#Preview {
    ReportsListView()
}
