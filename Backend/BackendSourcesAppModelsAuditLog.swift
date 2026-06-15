//
//  AuditLog.swift
//  CERT Field Board - Backend
//

import Foundation
import Fluent
import Vapor

// Fluent model for database persistence
final class AuditLog: Model, Content {
    static let schema = "audit_logs"
    
    @ID(key: .id)
    var id: UUID?
    
    @Field(key: "timestamp")
    var timestamp: Date
    
    @Field(key: "action")
    var action: String
    
    @Field(key: "actor_id")
    var actorID: String?  // Who performed the action (member ID or "system")
    
    @Field(key: "actor_name")
    var actorName: String?
    
    @Field(key: "target_type")
    var targetType: String  // "member", "subteam", "report", "task"
    
    @Field(key: "target_id")
    var targetID: String?
    
    @Field(key: "details")
    var details: String  // JSON string with additional info
    
    @Field(key: "ip_address")
    var ipAddress: String?
    
    init() { }
    
    init(id: UUID? = nil, action: String, actorID: String? = nil, actorName: String? = nil, targetType: String, targetID: String? = nil, details: String, ipAddress: String? = nil) {
        self.id = id
        self.timestamp = Date()
        self.action = action
        self.actorID = actorID
        self.actorName = actorName
        self.targetType = targetType
        self.targetID = targetID
        self.details = details
        self.ipAddress = ipAddress
    }
}

// Migration to create the table
struct CreateAuditLog: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("audit_logs")
            .id()
            .field("timestamp", .datetime, .required)
            .field("action", .string, .required)
            .field("actor_id", .string)
            .field("actor_name", .string)
            .field("target_type", .string, .required)
            .field("target_id", .string)
            .field("details", .string, .required)
            .field("ip_address", .string)
            .create()
    }
    
    func revert(on database: Database) async throws {
        try await database.schema("audit_logs").delete()
    }
}

// Helper for logging
extension Application {
    func logAudit(
        action: String,
        actorID: String? = nil,
        actorName: String? = nil,
        targetType: String,
        targetID: String? = nil,
        details: [String: Any] = [:],
        ipAddress: String? = nil
    ) async throws {
        let detailsJSON = try JSONSerialization.data(withJSONObject: details)
        let detailsString = String(data: detailsJSON, encoding: .utf8) ?? "{}"
        
        let log = AuditLog(
            action: action,
            actorID: actorID,
            actorName: actorName,
            targetType: targetType,
            targetID: targetID,
            details: detailsString,
            ipAddress: ipAddress
        )
        
        try await log.save(on: self.db)
        
        // Also print to console
        print("📝 AUDIT: [\(action)] \(actorName ?? "Unknown") -> \(targetType) \(targetID ?? "") | \(detailsString)")
    }
}

// Helper for requests
extension Request {
    func logAudit(
        action: String,
        actorID: String? = nil,
        actorName: String? = nil,
        targetType: String,
        targetID: String? = nil,
        details: [String: Any] = [:]
    ) async throws {
        let ipAddress = self.headers.first(name: "X-Real-IP") ?? self.headers.first(name: "X-Forwarded-For") ?? self.remoteAddress?.description
        
        try await self.application.logAudit(
            action: action,
            actorID: actorID,
            actorName: actorName,
            targetType: targetType,
            targetID: targetID,
            details: details,
            ipAddress: ipAddress
        )
    }
}
