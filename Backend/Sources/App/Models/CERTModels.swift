//
//  CERTModels.swift
//  CERT Field Board - Backend
//

import Foundation
import Vapor

// MARK: - Sub-Team

struct SubTeam: Content {
    var id: UUID?
    var color: TeamColor
    var memberIDs: [UUID]
    var assignedTaskId: UUID?
    var createdAt: Date?
    var lastUpdated: Date?

    enum TeamColor: String, Codable, CaseIterable {
        case red = "Red"
        case blue = "Blue"
        case green = "Green"
        case yellow = "Yellow"
        case purple = "Purple"
        case orange = "Orange"
        case teal = "Teal"
        case pink = "Pink"

        var hexColor: String {
            switch self {
            case .red: return "#dc3545"
            case .blue: return "#0d6efd"
            case .green: return "#198754"
            case .yellow: return "#ffc107"
            case .purple: return "#6f42c1"
            case .orange: return "#fd7e14"
            case .teal: return "#20c997"
            case .pink: return "#d63384"
            }
        }
    }
}

// MARK: - CERT Member

struct CERTMember: Content {
    var id: UUID?
    var name: String
    var role: String
    var icsPosition: String?
    var status: MemberStatus
    var equipment: [String]
    var location: LocationData?
    var subTeamId: UUID?
    var lastUpdated: Date
    var lentToTeam: String?       // team ID of the team that borrowed this member
    var lentRequestId: String?    // transfer request UUID — needed for recall
    var deviceToken: String?      // stable per-device identifier for session resumption

    enum MemberStatus: String, Codable {
        case available   = "Available"
        case onTask      = "On Task"
        case unavailable = "Unavailable"
        case needHelp    = "Need Help"
        case injured     = "Injured"
    }
}

// ICS Positions for reference
enum ICSPosition: String, Codable, CaseIterable {
    case incidentCommander = "Incident Commander"
    case safetyOfficer = "Safety Officer"
    case publicInformationOfficer = "Public Information Officer"
    case liaisonOfficer = "Liaison Officer"
    case operationsChief = "Operations Section Chief"
    case medicalTriage = "Operations - Medical/Triage"
    case searchRescue = "Operations - Search & Rescue"
    case fireSuppression = "Operations - Fire Suppression"
    case damageAssessment = "Operations - Damage Assessment"
    case planningChief = "Planning Section Chief"
    case documentation = "Planning - Documentation"
    case resourceTracking = "Planning - Resource Tracking"
    case logisticsChief = "Logistics Section Chief"
    case communications = "Logistics - Communications"
    case supplies = "Logistics - Supplies"
    case equipment = "Logistics - Equipment"
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
    var subTeamId: UUID?
    var acknowledgedByCounty: Bool?   // nil = false; set by county ack message
    var acknowledgedAt: Date?
    var escalatedToCounty: Bool?      // nil = auto (High/LS go up); true = forced up; false = suppressed
    var reportedAt: Date
    var lastUpdated: Date
    // ICS-213 General Message fields
    var subject: String?
    var fromName: String?
    var fromPosition: String?
    var toName: String?
    var replyText: String?
    var repliedByName: String?
    var repliedAt: Date?

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
    var assignedSubTeamId: UUID?
    var status: TaskStatus
    var priority: String
    var location: LocationData?
    var relatedReportId: UUID?
    var createdAt: Date?
    var completedAt: Date?
    var notes: String

    enum TaskStatus: String, Codable {
        case open = "Open"
        case assigned = "Assigned"
        case completed = "Completed"
        case cancelled = "Cancelled"
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
    var checkedOutByLeader: Bool?
}

struct MeResponse: Content {
    var checkedOutByLeader: Bool
    var subTeamName: String?
    var subTeamColor: String?
    var assignedTasks: [CERTTask]?
}

struct DashboardData: Content {
    var incident: Incident?
    var members: [CERTMember]
    var reports: [IncidentReport]
    var tasks: [CERTTask]
    var subTeams: [SubTeam]
    var loanableMembers: [UUID]
    var countyInbox: [CountyMessage]   // recent alert/info messages received from county
    var isActivated: Bool
    var lastUpdate: Date
}

// MARK: - County Integration

struct TeamSummary: Content {
    var teamID: String
    var teamName: String
    var isActivated: Bool
    var location: String?
    var endpoint: String?
    var memberCount: Int
    var activeMemberCount: Int
    var reportCounts: ReportSeverityCounts
    var unacknowledgedPriority: Int
    var openTaskCount: Int
    var lastContact: Date

    struct ReportSeverityCounts: Content {
        var lifeSafety: Int
        var high: Int
        var medium: Int
        var low: Int
    }
}

struct CountyMessage: Content {
    var id: UUID
    var type: MessageType
    var targetTeamId: String
    var reportId: UUID?
    var text: String
    var timestamp: Date
    var confirmed: Bool

    enum MessageType: String, Codable {
        case acknowledgment
        case alert
        case info
        case transferRequest        // owning team: someone is requesting your member
        case transferResponse       // requesting team: your request was accepted/denied
        case transferRelease        // owning team: requesting team returned the member
        case transferRecallRequest  // requesting team: owning team wants their member back
    }
}

// MARK: - Team Flags (team → county upward)

struct TeamFlag: Content {
    var id: UUID
    var teamId: String
    var teamName: String
    var text: String
    var timestamp: Date
    var acknowledged: Bool
    var acknowledgedAt: Date?
}

// MARK: - County Transfer

struct AvailableMember: Content {
    var memberId: UUID
    var teamId: String
    var teamName: String
    var memberName: String
    var memberRole: String
    var addedAt: Date
}

struct TransferRequest: Content {
    var id: UUID
    var requestingTeamId: String
    var requestingTeamName: String
    var owningTeamId: String
    var memberId: UUID
    var memberName: String
    var status: TransferStatus
    var requestedAt: Date
    var respondedAt: Date?

    enum TransferStatus: String, Codable {
        case pending         = "Pending"
        case accepted        = "Accepted"
        case denied          = "Denied"
        case recallRequested = "RecallRequested"  // owning team sent a recall request
        case released        = "Released"         // requesting team returned voluntarily
        case recalled        = "Recalled"         // returned after a recall request
    }
}
