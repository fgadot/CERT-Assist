//
//  CountyModels.swift
//  CERT County EOC Backend
//

import Foundation
import Vapor

// MARK: - Team Summary (pushed by team servers)

struct TeamSummary: Content {
    var teamID: String
    var teamName: String
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

// MARK: - County Message (county → team, picked up by team polling)

struct CountyMessage: Content {
    var id: UUID
    var type: MessageType
    var targetTeamID: String
    var reportID: UUID?
    var text: String
    var timestamp: Date
    var confirmed: Bool            // true once team has polled and processed

    enum MessageType: String, Codable {
        case acknowledgment
        case alert
        case info
    }
}

// MARK: - County Dashboard (sent via WebSocket)

struct CountyDashboardData: Content {
    var teams: [TeamSummary]
    var pendingMessageCounts: [String: Int]   // teamID → count of unconfirmed messages
    var lastUpdate: Date
}
