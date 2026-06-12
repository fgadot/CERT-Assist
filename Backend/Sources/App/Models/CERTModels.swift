//
//  CERTModels.swift
//  CERT Field Board - Backend
//

import Foundation
import Vapor

// MARK: - CERT Member

struct CERTMember: Content {
    var id: UUID?
    var name: String
    var role: String
    var icsPosition: String?
    var status: MemberStatus
    var equipment: [String]
    var location: LocationData?
    var lastUpdated: Date
    
    enum MemberStatus: String, Codable {
        case available = "Available"
        case assigned = "Assigned"
        case unavailable = "Unavailable"
        case injured = "Injured"
        case needsHelp = "Needs Help"
    }
}

// ICS Positions for reference
enum ICSPosition: String, Codable, CaseIterable {
    // Command Staff
    case incidentCommander = "Incident Commander"
    case safetyOfficer = "Safety Officer"
    case publicInformationOfficer = "Public Information Officer"
    case liaisonOfficer = "Liaison Officer"
    
    // Operations Section
    case operationsChief = "Operations Section Chief"
    case medicalTriage = "Operations - Medical/Triage"
    case searchRescue = "Operations - Search & Rescue"
    case fireSuppression = "Operations - Fire Suppression"
    case damageAssessment = "Operations - Damage Assessment"
    
    // Planning Section
    case planningChief = "Planning Section Chief"
    case documentation = "Planning - Documentation"
    case resourceTracking = "Planning - Resource Tracking"
    
    // Logistics Section
    case logisticsChief = "Logistics Section Chief"
    case communications = "Logistics - Communications"
    case supplies = "Logistics - Supplies"
    case equipment = "Logistics - Equipment"
    
    // None
    case none = "Not Assigned"
}

// MARK: - Incident Report

struct IncidentReport: Content {
    var id: UUID?
    var type: ReportType
    var location: LocationData
    var severity: Severity
    var status: ReportStatus
    var notes: String
    var reportedBy: UUID
    var reportedAt: Date
    var lastUpdated: Date
    
    enum ReportType: String, Codable {
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
    }
    
    enum Severity: String, Codable {
        case low = "Low"
        case medium = "Medium"
        case high = "High"
        case lifeSafety = "Life Safety"
    }
    
    enum ReportStatus: String, Codable {
        case new = "New"
        case assigned = "Assigned"
        case resolved = "Resolved"
        case escalated = "Escalated"
    }
}

// MARK: - Task

struct CERTTask: Content {
    var id: UUID?
    var title: String
    var description: String
    var assignedTo: [UUID]
    var status: TaskStatus
    var priority: String
    var location: LocationData?
    var relatedReportID: UUID?
    var createdAt: Date
    var completedAt: Date?
    var notes: String
    
    enum TaskStatus: String, Codable {
        case open = "Open"
        case assigned = "Assigned"
        case completed = "Completed"
    }
}

// MARK: - Location

struct LocationData: Codable {
    var latitude: Double
    var longitude: Double
    var address: String?
    var timestamp: Date
}

// MARK: - Incident

struct Incident: Content {
    var id: UUID?
    var name: String
    var startDate: Date
    var endDate: Date?
    var isActive: Bool
}

// MARK: - Response Models

struct CheckInResponse: Content {
    var success: Bool
    var message: String
    var memberID: UUID?
}

struct DashboardData: Content {
    var incident: Incident?
    var members: [CERTMember]
    var reports: [IncidentReport]
    var tasks: [CERTTask]
    var lastUpdate: Date
}
