//
//  AuditLog.swift
//  CERT Field Board - Backend
//
//  Persistent audit log stored in SQLite (survives container restarts).
//  Complies with FEMA ICS-214 Activity Log and ICS-211 Check-In/Check-Out requirements.
//

import Foundation
import Fluent
import Vapor

// MARK: - Fluent Model

final class AuditLog: Model, Content {
    static let schema = "audit_logs"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "timestamp")
    var timestamp: Date

    @Field(key: "action")
    var action: String        // e.g. "member_checkin", "status_change", "report_submitted"

    @Field(key: "actor_id")
    var actorID: String?      // Member UUID or "system"

    @Field(key: "actor_name")
    var actorName: String?

    @Field(key: "target_type")
    var targetType: String    // "member", "report", "task", "subteam"

    @Field(key: "target_id")
    var targetID: String?

    @Field(key: "details")
    var details: String       // JSON string with action-specific fields

    @Field(key: "ip_address")
    var ipAddress: String?

    init() {}

    init(
        action: String,
        actorID: String? = nil,
        actorName: String? = nil,
        targetType: String,
        targetID: String? = nil,
        details: String,
        ipAddress: String? = nil
    ) {
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

// MARK: - Migration

struct CreateAuditLog: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("audit_logs")
            .id()
            .field("timestamp",   .datetime, .required)
            .field("action",      .string,   .required)
            .field("actor_id",    .string)
            .field("actor_name",  .string)
            .field("target_type", .string,   .required)
            .field("target_id",   .string)
            .field("details",     .string,   .required)
            .field("ip_address",  .string)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("audit_logs").delete()
    }
}

// MARK: - Request helper

extension Request {
    func logAudit(
        action: String,
        actorID: String? = nil,
        actorName: String? = nil,
        targetType: String,
        targetID: String? = nil,
        details: [String: Any] = [:]
    ) async throws {
        let ip = headers.first(name: "X-Real-IP")
            ?? headers.first(name: "X-Forwarded-For")
            ?? remoteAddress?.description

        let detailsJSON: String
        if let data = try? JSONSerialization.data(withJSONObject: details),
           let str = String(data: data, encoding: .utf8) {
            detailsJSON = str
        } else {
            detailsJSON = "{}"
        }

        let entry = AuditLog(
            action: action,
            actorID: actorID,
            actorName: actorName,
            targetType: targetType,
            targetID: targetID,
            details: detailsJSON,
            ipAddress: ip
        )
        try await entry.save(on: db)
    }
}

// MARK: - ICS-214 HTML Export

func buildICS214HTML(teamName: String, incidentName: String, entries: [AuditLog]) -> String {
    let fmt = DateFormatter()
    fmt.dateFormat = "MM/dd/yyyy HH:mm"
    fmt.timeZone = TimeZone.current

    let now = fmt.string(from: Date())
    let firstTime = entries.first.map { fmt.string(from: $0.timestamp) } ?? now

    // ── ICS-211 Personnel Roster ──────────────────────────────────────────────
    let checkins  = entries.filter { $0.action == "member_checkin" }
    let checkouts = entries.filter { $0.action == "member_checkout" }

    var personnelRows = ""
    for entry in checkins {
        let det = parseDetails(entry.details)
        let role  = det["role"] ?? "—"
        let equip = det["equipment"] ?? "—"
        let cin   = fmt.string(from: entry.timestamp)
        let cout  = checkouts.first { $0.actorID == entry.actorID }
                        .map { fmt.string(from: $0.timestamp) } ?? "—"
        personnelRows += "<tr><td>\(esc(entry.actorName ?? "—"))</td>"
            + "<td>\(esc(role))</td><td>\(cin)</td><td>\(esc(equip))</td><td>\(cout)</td></tr>"
    }
    if personnelRows.isEmpty {
        personnelRows = "<tr><td colspan='5' style='color:#888;font-style:italic;'>No check-ins recorded</td></tr>"
    }

    // ── ICS-214 Activity Log ──────────────────────────────────────────────────
    var activityRows = ""
    for entry in entries {
        let det  = parseDetails(entry.details)
        let desc = describeAction(action: entry.action, actor: entry.actorName, details: det)
        activityRows += "<tr><td style='white-space:nowrap;'>\(fmt.string(from: entry.timestamp))</td>"
            + "<td>\(esc(entry.actorName ?? "System"))</td>"
            + "<td>\(esc(desc))</td></tr>"
    }
    if activityRows.isEmpty {
        activityRows = "<tr><td colspan='3' style='color:#888;font-style:italic;'>No activity recorded</td></tr>"
    }

    return """
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="UTF-8">
    <title>ICS-214 Activity Log — \(esc(teamName))</title>
    <style>
      body { font-family: Arial, Helvetica, sans-serif; font-size: 12px; color: #000;
             max-width: 960px; margin: 0 auto; padding: 28px; }
      h1 { font-size: 18px; text-align: center; margin: 0 0 4px; }
      .subtitle { text-align: center; font-size: 12px; color: #555; margin-bottom: 20px; }
      .header-box { border: 2px solid #000; padding: 10px 14px; margin-bottom: 18px;
                    display: grid; grid-template-columns: 1fr 1fr; gap: 6px 24px; }
      .hf label { font-weight: bold; }
      h2 { font-size: 13px; background: #333; color: white; padding: 5px 10px;
           margin: 18px 0 6px; }
      table { width: 100%; border-collapse: collapse; font-size: 11px; margin-bottom: 12px; }
      th { background: #555; color: white; padding: 5px 8px; text-align: left; }
      td { padding: 4px 8px; border-bottom: 1px solid #e0e0e0; vertical-align: top; }
      tr:nth-child(even) td { background: #f7f7f7; }
      .print-btn { background: #1a6fdb; color: white; border: none; padding: 10px 22px;
                   font-size: 13px; border-radius: 6px; cursor: pointer; margin-bottom: 18px; }
      footer { margin-top: 24px; font-size: 10px; color: #999; text-align: center; }
      @media print { .print-btn { display: none; } }
    </style>
    </head>
    <body>
    <button class="print-btn" onclick="window.print()">🖨️ Print / Save as PDF</button>
    <h1>ACTIVITY LOG (ICS 214)</h1>
    <p class="subtitle">FEMA/NIMS Incident Documentation &nbsp;·&nbsp; Generated \(now)</p>

    <div class="header-box">
      <div class="hf"><label>1. Incident Name: </label>\(esc(incidentName))</div>
      <div class="hf"><label>4. Home Agency: </label>Manatee County CERT</div>
      <div class="hf"><label>2. Operational Period: </label>\(firstTime) — \(now)</div>
      <div class="hf"><label>3. Unit Name / Position: </label>\(esc(teamName))</div>
    </div>

    <h2>5. Personnel Roster (ICS-211 Check-In / Check-Out)</h2>
    <table>
      <tr>
        <th>Name</th><th>ICS Role</th><th>Check-In</th><th>Equipment</th><th>Check-Out</th>
      </tr>
      \(personnelRows)
    </table>

    <h2>6. Activity Log (Chronological)</h2>
    <table>
      <tr><th>Date / Time</th><th>Personnel</th><th>Activity</th></tr>
      \(activityRows)
    </table>

    <footer>
      CERT Assist &nbsp;·&nbsp; certassist.us &nbsp;·&nbsp; ICS-214 Activity Log (v3.1 format)
      &nbsp;·&nbsp; Retain all completed originals per NIMS documentation requirements.
    </footer>
    </body>
    </html>
    """
}

// MARK: - Private helpers

private func parseDetails(_ json: String) -> [String: String] {
    guard let data = json.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return [:] }
    return obj.reduce(into: [:]) { $0[$1.key] = "\($1.value)" }
}

private func describeAction(action: String, actor: String?, details: [String: String]) -> String {
    switch action {
    case "member_checkin":
        let role  = details["role"]      ?? ""
        let equip = details["equipment"] ?? ""
        return "Checked in — Role: \(role)\(equip.isEmpty ? "" : " | Equipment: \(equip)")"
    case "member_checkout":
        return "Checked out — Role: \(details["role"] ?? "")"
    case "status_change":
        return "Status: \(details["from"] ?? "?") → \(details["to"] ?? "?")"
    case "report_submitted":
        let type = details["type"] ?? ""; let sev = details["severity"] ?? ""
        let loc  = details["location"] ?? ""; let subj = details["subject"] ?? ""
        var s = "Submitted \(sev) report: \(type)"
        if !subj.isEmpty { s += " — \(subj)" }
        if !loc.isEmpty  { s += " at \(loc)" }
        return s
    case "report_replied":
        return "Replied to \(details["report_type"] ?? "report") from \(details["reporter"] ?? "member")"
    case "task_created":
        return "Task created: \(details["title"] ?? "") [\(details["priority"] ?? "") priority]"
    case "task_completed":
        return "Task completed: \(details["title"] ?? "")"
    case "subteam_created":
        return "Sub-team created: \(details["color"] ?? "") (\(details["member_count"] ?? "0") members)"
    default:
        return action.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

private func esc(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;")
     .replacingOccurrences(of: "<", with: "&lt;")
     .replacingOccurrences(of: ">", with: "&gt;")
     .replacingOccurrences(of: "\"", with: "&quot;")
}
