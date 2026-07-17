//
//  Models.swift
//  CERT Assist
//
//  Created by frank gadot on 2026.06.09.
//

import Foundation
import CoreLocation
import SwiftUI

// MARK: - Member

struct CERTMember: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var role: String
    var status: MemberStatus
    var location: LocationData?
    var equipment: [Equipment]
    var lastUpdated: Date
    
    init(
        id: UUID = UUID(),
        name: String,
        role: String,
        status: MemberStatus = .unavailable,
        location: LocationData? = nil,
        equipment: [Equipment] = [],
        lastUpdated: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.status = status
        self.location = location
        self.equipment = equipment
        self.lastUpdated = lastUpdated
    }
}

enum MemberStatus: String, Codable, CaseIterable {
    case available = "Available"
    case assigned = "Assigned"
    case unavailable = "Unavailable"
    case injured = "Injured"
    case needsHelp = "Needs Help"
    
    var icon: String {
        switch self {
        case .available: return "checkmark.circle.fill"
        case .assigned: return "figure.walk"
        case .unavailable: return "xmark.circle"
        case .injured: return "cross.case.fill"
        case .needsHelp: return "exclamationmark.triangle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .available: return .green
        case .assigned: return .blue
        case .unavailable: return .gray
        case .injured: return .red
        case .needsHelp: return .orange
        }
    }
}

enum Equipment: String, Codable, CaseIterable {
    case radio = "Radio"
    case firstAidKit = "First Aid Kit"
    case aed = "AED"
    case chainsaw = "Chainsaw"
    case generator = "Generator"
    case vehicle = "Vehicle"
    case golfCart = "Golf Cart"
    case fireExtinguisher = "Fire Extinguisher"
    case searchAndRescueGear = "SAR Gear"
    
    var icon: String {
        switch self {
        case .radio: return "antenna.radiowaves.left.and.right"
        case .firstAidKit: return "cross.case"
        case .aed: return "waveform.path.ecg"
        case .chainsaw: return "hurricane"
        case .generator: return "bolt.fill"
        case .vehicle: return "car.fill"
        case .golfCart: return "figure.golf"
        case .fireExtinguisher: return "flame"
        case .searchAndRescueGear: return "backpack.fill"
        }
    }
}

// MARK: - Report

struct IncidentReport: Identifiable, Codable, Hashable {
    let id: UUID
    var type: ReportType
    var location: LocationData
    var severity: Severity
    var status: ReportStatus
    var notes: String
    var photoData: Data?
    var reportedBy: UUID // Member ID
    var reportedAt: Date
    var lastUpdated: Date
    
    init(
        id: UUID = UUID(),
        type: ReportType,
        location: LocationData,
        severity: Severity,
        status: ReportStatus = .new,
        notes: String = "",
        photoData: Data? = nil,
        reportedBy: UUID,
        reportedAt: Date = Date(),
        lastUpdated: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.location = location
        self.severity = severity
        self.status = status
        self.notes = notes
        self.photoData = photoData
        self.reportedBy = reportedBy
        self.reportedAt = reportedAt
        self.lastUpdated = lastUpdated
    }
}

enum ReportType: String, Codable, CaseIterable {
    case treeDown = "Tree Down"
    case flooding = "Flooding"
    case powerLineDown = "Power Line Down"
    case medicalNeed = "Medical Need"
    case blockedRoad = "Blocked Road"
    case fireSmoke = "Fire/Smoke"
    case gasSmell = "Gas Smell"
    case welfareCheck = "Welfare Check"
    case structureDamage = "Structure Damage"
    case needsEmergencyServices = "Needs 911"
    case other = "Other"
    
    var icon: String {
        switch self {
        case .treeDown: return "leaf.fill"
        case .flooding: return "drop.fill"
        case .powerLineDown: return "bolt.slash.fill"
        case .medicalNeed: return "cross.circle.fill"
        case .blockedRoad: return "road.lanes"
        case .fireSmoke: return "flame.fill"
        case .gasSmell: return "smoke.fill"
        case .welfareCheck: return "house.fill"
        case .structureDamage: return "house.slash.fill"
        case .needsEmergencyServices: return "phone.fill"
        case .other: return "exclamationmark.circle.fill"
        }
    }
}

enum Severity: String, Codable, CaseIterable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case lifeSafety = "Life Safety"
    
    var color: Color {
        switch self {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .orange
        case .lifeSafety: return .red
        }
    }
    
    var icon: String {
        switch self {
        case .low: return "exclamationmark"
        case .medium: return "exclamationmark.2"
        case .high: return "exclamationmark.3"
        case .lifeSafety: return "exclamationmark.triangle.fill"
        }
    }
}

enum ReportStatus: String, Codable, CaseIterable {
    case new = "New"
    case assigned = "Assigned"
    case resolved = "Resolved"
    case escalated = "Escalated"
    
    var icon: String {
        switch self {
        case .new: return "circle.fill"
        case .assigned: return "arrow.forward.circle.fill"
        case .resolved: return "checkmark.circle.fill"
        case .escalated: return "arrow.up.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .new: return .blue
        case .assigned: return .orange
        case .resolved: return .green
        case .escalated: return .red
        }
    }
}

// MARK: - Task

struct Task: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var description: String
    var assignedTo: [UUID] // Member IDs
    var status: TaskStatus
    var priority: Severity
    var location: LocationData?
    var relatedReportID: UUID?
    var createdAt: Date
    var completedAt: Date?
    var notes: String
    
    init(
        id: UUID = UUID(),
        title: String,
        description: String,
        assignedTo: [UUID] = [],
        status: TaskStatus = .open,
        priority: Severity = .medium,
        location: LocationData? = nil,
        relatedReportID: UUID? = nil,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.assignedTo = assignedTo
        self.status = status
        self.priority = priority
        self.location = location
        self.relatedReportID = relatedReportID
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.notes = notes
    }
}

enum TaskStatus: String, Codable, CaseIterable {
    case open = "Open"
    case assigned = "Assigned"
    case completed = "Completed"
    case cancelled = "Cancelled"

    // Used for the status picker — excludes cancelled (set via Cancel button)
    static let activeStatuses: [TaskStatus] = [.open, .assigned, .completed]

    var icon: String {
        switch self {
        case .open: return "circle"
        case .assigned: return "arrow.forward.circle"
        case .completed: return "checkmark.circle.fill"
        case .cancelled: return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .open: return .red
        case .assigned: return .orange
        case .completed: return .green
        case .cancelled: return .gray
        }
    }
}

// MARK: - Location

struct LocationData: Codable, Hashable {
    var latitude: Double
    var longitude: Double
    var address: String?
    var timestamp: Date
    
    init(latitude: Double, longitude: Double, address: String? = nil, timestamp: Date = Date()) {
        self.latitude = latitude
        self.longitude = longitude
        self.address = address
        self.timestamp = timestamp
    }
    
    init(coordinate: CLLocationCoordinate2D, address: String? = nil) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.address = address
        self.timestamp = Date()
    }
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - Incident

struct Incident: Identifiable, Codable {
    let id: UUID
    var name: String
    var startDate: Date
    var endDate: Date?
    var isActive: Bool
    
    init(
        id: UUID = UUID(),
        name: String,
        startDate: Date = Date(),
        endDate: Date? = nil,
        isActive: Bool = true
    ) {
        self.id = id
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.isActive = isActive
    }
}
