//
//  CountyModels.swift
//  CERT County EOC Backend
//

import Foundation
import Vapor

// MARK: - Team Summary (pushed by team servers)

struct TeamSummary: Content {
    var teamId: String
    var teamName: String
    var isActivated: Bool
    var location: String?
    var endpoint: String?          // e.g. "https://oakdale.cert.w6fgc.com"
    var memberCount: Int
    var activeMemberCount: Int
    var reportCounts: ReportSeverityCounts
    var unacknowledgedPriority: Int  // High + Life Safety not yet acked by county
    var openTaskCount: Int
    var lastContact: Date

    struct ReportSeverityCounts: Content {
        var lifeSafety: Int
        var high: Int
        var medium: Int
        var low: Int

        var total: Int { lifeSafety + high + medium + low }
        var priority: Int { lifeSafety + high }
    }
}

// MARK: - Available Member (team → county, for cross-team borrowing)

struct AvailableMember: Content {
    var memberId: UUID         // team's own member UUID (also used as county record key)
    var teamId: String
    var teamName: String
    var memberName: String
    var memberRole: String
    var addedAt: Date
}

// MARK: - Transfer Request (requesting team → county → owning team)

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

// MARK: - County Message (county → team, picked up by team polling)

struct CountyMessage: Content {
    var id: UUID
    var type: MessageType
    var targetTeamId: String
    var reportId: UUID?
    var text: String
    var timestamp: Date
    var confirmed: Bool            // true once team has polled and processed

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

// MARK: - Team Flag (team → county: flag for EOC review)

struct TeamFlag: Content {
    var id: UUID
    var teamId: String
    var teamName: String
    var text: String
    var timestamp: Date
    var acknowledged: Bool
    var acknowledgedAt: Date?
}

// MARK: - Broadcast Banner (persistent, shown on all team dashboards)

struct BroadcastBanner: Content {
    var text: String
    var type: BannerType
    var setAt: Date

    enum BannerType: String, Codable {
        case info      = "info"       // blue
        case important = "important"  // orange
        case emergency = "emergency"  // red
    }
}

// MARK: - County Dashboard (sent via WebSocket)

struct CountyDashboardData: Content {
    var teams: [TeamSummary]
    var pendingMessageCounts: [String: Int]   // teamId → count of unconfirmed messages
    var lastUpdate: Date
    var activeBanner: BroadcastBanner?
}
