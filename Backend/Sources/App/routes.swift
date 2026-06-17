//
//  routes.swift
//  CERT Field Board - Backend
//

import Vapor
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

actor DataStore {
    var currentIncident: Incident?
    var members: [UUID: CERTMember] = [:]
    var reports: [UUID: IncidentReport] = [:]
    var tasks: [UUID: CERTTask] = [:]
    var subTeams: [UUID: SubTeam] = [:]
    var connectedWebSockets: [WebSocket] = []

    // Audit log file
    private let logFileURL: URL

    // County integration — read from environment at startup
    private let countyEndpoint: String? = Environment.get("COUNTY_ENDPOINT")
    private let teamID: String = Environment.get("TEAM_ID") ?? "unknown"
    private let teamName: String = Environment.get("TEAM_NAME") ?? "Unknown Team"
    private let teamLocation: String? = Environment.get("TEAM_LOCATION")
    private let teamEndpoint: String? = Environment.get("TEAM_ENDPOINT")

    init() {
        let logsDir = URL(fileURLWithPath: "/app/logs")
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())
        logFileURL = logsDir.appendingPathComponent("cert-audit-\(dateString).log")

        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }

        log("🚀 DataStore initialized - Audit logging started")
    }

    private func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logEntry = "[\(timestamp)] \(message)\n"
        print(logEntry, terminator: "")
        if let data = logEntry.data(using: .utf8),
           let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
            fileHandle.seekToEndOfFile()
            fileHandle.write(data)
            fileHandle.closeFile()
        }
    }

    func addWebSocket(_ ws: WebSocket) {
        connectedWebSockets.append(ws)
    }

    func removeWebSocket(_ ws: WebSocket) {
        connectedWebSockets.removeAll { $0 === ws }
    }

    func broadcastUpdate() async {
        let data = getDashboardData()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase

        guard let jsonData = try? encoder.encode(data),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }

        for ws in connectedWebSockets {
            try? await ws.send(jsonString)
        }

        // Push summary to county (fire-and-forget)
        Task { await self.pushToCounty() }
    }

    // ── County integration ────────────────────────────────────────────────────────

    func buildTeamSummary() -> TeamSummary {
        let lsCount  = reports.values.filter { $0.severity == .lifeSafety }.count
        let hiCount  = reports.values.filter { $0.severity == .high }.count
        let medCount = reports.values.filter { $0.severity == .medium }.count
        let lowCount = reports.values.filter { $0.severity == .low }.count

        let unacked = reports.values.filter { r in
            guard !(r.acknowledgedByCounty ?? false) else { return false }
            let isHighPriority  = r.severity == .lifeSafety || r.severity == .high
            let autoEscalated   = isHighPriority && (r.escalatedToCounty != false)
            let manualEscalated = r.escalatedToCounty == true
            return autoEscalated || manualEscalated
        }.count

        let openTasks  = tasks.values.filter { $0.status == .open || $0.status == .assigned }.count
        let activeMembers = members.values.filter { $0.status == .available || $0.status == .assigned }.count

        return TeamSummary(
            teamID: teamID,
            teamName: teamName,
            location: teamLocation,
            endpoint: teamEndpoint,
            memberCount: members.count,
            activeMemberCount: activeMembers,
            reportCounts: TeamSummary.ReportSeverityCounts(
                lifeSafety: lsCount,
                high: hiCount,
                medium: medCount,
                low: lowCount
            ),
            unacknowledgedPriority: unacked,
            openTaskCount: openTasks,
            lastContact: Date()
        )
    }

    func applyCountyMessage(_ message: CountyMessage) {
        switch message.type {
        case .acknowledgment:
            if let reportID = message.reportID, var report = reports[reportID] {
                report.acknowledgedByCounty = true
                report.acknowledgedAt = message.timestamp
                reports[reportID] = report
                log("✅ COUNTY ACK: \(report.type.rawValue) acknowledged by County EOC")
            }
        case .alert:
            log("⚠️ COUNTY ALERT: \(message.text)")
        case .info:
            log("ℹ️ COUNTY MESSAGE: \(message.text)")
        }
    }

    private func pushToCounty() async {
        guard let countyEndpoint else { return }
        let summary = buildTeamSummary()

        guard let url = URL(string: "\(countyEndpoint)/api/teams/summary") else { return }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        guard let body = try? encoder.encode(summary) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 5

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            URLSession.shared.dataTask(with: request) { _, _, _ in
                continuation.resume()
            }.resume()
        }
    }

    // ── Members ───────────────────────────────────────────────────────────────────

    func addMember(_ member: CERTMember) async {
        members[member.id!] = member
        log("✅ MEMBER CHECK-IN: \(member.name) (\(member.role)) - Status: \(member.status.rawValue) - Equipment: \(member.equipment.joined(separator: ", "))")
        await broadcastUpdate()
    }

    func getAllMembers() -> [CERTMember] { Array(members.values) }

    func updateMember(_ member: CERTMember) async {
        let old = members[member.id!]
        members[member.id!] = member
        if let old {
            if old.status != member.status {
                log("🔄 MEMBER STATUS CHANGE: \(member.name) - \(old.status.rawValue) → \(member.status.rawValue)")
            }
            if old.subTeamID != member.subTeamID {
                let teamInfo = member.subTeamID != nil ? "assigned to sub-team" : "removed from sub-team"
                log("🔄 MEMBER TEAM CHANGE: \(member.name) - \(teamInfo)")
            }
        }
        await broadcastUpdate()
    }

    // ── Reports ───────────────────────────────────────────────────────────────────

    func addReport(_ report: IncidentReport) async {
        reports[report.id!] = report
        let reporterName = members[report.reportedBy]?.name ?? "Unknown"
        let teamInfo = report.subTeamID != nil ? " (Sub-Team Report)" : ""
        log("📋 NEW REPORT: \(report.type.rawValue) - Severity: \(report.severity.rawValue) - By: \(reporterName)\(teamInfo) - Location: \(report.location.address ?? "N/A")")
        await broadcastUpdate()
    }

    func getAllReports() -> [IncidentReport] { Array(reports.values) }

    func updateReport(_ report: IncidentReport) async {
        let old = reports[report.id!]
        reports[report.id!] = report
        if let old {
            if old.severity != report.severity {
                log("🔄 REPORT SEVERITY OVERRIDE: \(report.type.rawValue) - \(old.severity.rawValue) → \(report.severity.rawValue)")
            }
            if old.status != report.status {
                log("🔄 REPORT STATUS CHANGE: \(report.type.rawValue) - \(old.status.rawValue) → \(report.status.rawValue)")
            }
        }
        await broadcastUpdate()
    }

    // ── Tasks ─────────────────────────────────────────────────────────────────────

    func addTask(_ task: CERTTask) async {
        tasks[task.id!] = task
        let teamInfo = task.assignedSubTeamID != nil ? " → Assigned to sub-team" : ""
        log("📝 NEW TASK: \(task.title) - Priority: \(task.priority)\(teamInfo)")
        await broadcastUpdate()
    }

    func getAllTasks() -> [CERTTask] { Array(tasks.values) }

    func updateTask(_ task: CERTTask) async {
        tasks[task.id!] = task
        await broadcastUpdate()
    }

    // ── Sub-Teams ─────────────────────────────────────────────────────────────────

    func createSubTeam(_ subTeam: SubTeam) async {
        subTeams[subTeam.id!] = subTeam
        let memberNames = subTeam.memberIDs.compactMap { members[$0]?.name }
        log("🎨 SUB-TEAM CREATED: \(subTeam.color.rawValue) Team - Members: \(memberNames.joined(separator: ", "))")

        // Remove members from any other sub-team they were already in
        for (oldTeamID, oldTeam) in subTeams {
            if oldTeamID == subTeam.id { continue }
            let membersToRemove = oldTeam.memberIDs.filter { subTeam.memberIDs.contains($0) }
            if !membersToRemove.isEmpty {
                var updatedTeam = oldTeam
                updatedTeam.memberIDs = oldTeam.memberIDs.filter { !membersToRemove.contains($0) }
                let removedNames = membersToRemove.compactMap { members[$0]?.name }
                log("  ↳ Removed from \(oldTeam.color.rawValue) Team: \(removedNames.joined(separator: ", "))")
                if updatedTeam.memberIDs.count < 2 {
                    log("  ↳ \(oldTeam.color.rawValue) Team disbanded (less than 2 members)")
                    for remainingID in updatedTeam.memberIDs {
                        if var m = members[remainingID] {
                            m.subTeamID = nil; m.status = .available; members[remainingID] = m
                            log("  ↳ \(m.name) freed from disbanded team")
                        }
                    }
                    subTeams.removeValue(forKey: oldTeamID)
                } else {
                    subTeams[oldTeamID] = updatedTeam
                }
            }
        }

        for memberID in subTeam.memberIDs {
            if var m = members[memberID] {
                let oldStatus = m.status
                m.subTeamID = subTeam.id; m.status = .assigned; members[memberID] = m
                log("  ↳ Assigned: \(m.name) (\(oldStatus.rawValue) → Assigned)")
            }
        }

        await broadcastUpdate()
    }

    func getAllSubTeams() -> [SubTeam] { Array(subTeams.values) }

    func updateSubTeam(_ subTeam: SubTeam) async {
        if let oldSubTeam = subTeams[subTeam.id!] {
            log("🔄 SUB-TEAM UPDATE: \(subTeam.color.rawValue) Team - Reassigning members")
            for oldMemberID in oldSubTeam.memberIDs {
                if var m = members[oldMemberID] {
                    m.subTeamID = nil; m.status = .available; members[oldMemberID] = m
                    log("  ↳ Unassigned: \(m.name)")
                }
            }
        }
        subTeams[subTeam.id!] = subTeam
        for memberID in subTeam.memberIDs {
            if var m = members[memberID] {
                m.subTeamID = subTeam.id; m.status = .assigned; members[memberID] = m
                log("  ↳ Assigned: \(m.name)")
            }
        }
        await broadcastUpdate()
    }

    func deleteSubTeam(_ id: UUID) async {
        guard let subTeam = subTeams[id] else { return }
        let memberNames = subTeam.memberIDs.compactMap { members[$0]?.name }
        log("🗑️ SUB-TEAM DELETED: \(subTeam.color.rawValue) Team - Members unassigned: \(memberNames.joined(separator: ", "))")
        for memberID in subTeam.memberIDs {
            if var m = members[memberID] {
                m.subTeamID = nil; m.status = .available; members[memberID] = m
            }
        }
        subTeams.removeValue(forKey: id)
        await broadcastUpdate()
    }

    func freeMember(_ memberID: UUID) async {
        guard var member = members[memberID] else { return }
        let oldTeamID = member.subTeamID
        member.subTeamID = nil; member.status = .available; members[memberID] = member
        log("🆓 MEMBER FREED: \(member.name) - Set to Available")

        if let teamID = oldTeamID, var team = subTeams[teamID] {
            team.memberIDs.removeAll { $0 == memberID }
            if team.memberIDs.count < 2 {
                log("  ↳ \(team.color.rawValue) Team disbanded (less than 2 members)")
                for remainingID in team.memberIDs {
                    if var m = members[remainingID] {
                        m.subTeamID = nil; m.status = .available; members[remainingID] = m
                        log("  ↳ \(m.name) freed from disbanded team")
                    }
                }
                subTeams.removeValue(forKey: teamID)
            } else {
                subTeams[teamID] = team
            }
        }

        await broadcastUpdate()
    }

    func setIncident(_ incident: Incident) async {
        let action = currentIncident == nil ? "STARTED" : "UPDATED"
        log("🚨 INCIDENT \(action): \(incident.name) - Active: \(incident.isActive)")
        currentIncident = incident
        await broadcastUpdate()
    }

    func getDashboardData() -> DashboardData {
        return DashboardData(
            incident: currentIncident,
            members: Array(members.values),
            reports: Array(reports.values),
            tasks: Array(tasks.values),
            subTeams: Array(subTeams.values),
            lastUpdate: Date()
        )
    }
}

let dataStore = DataStore()

func routes(_ app: Application) throws {

    app.get { req -> Response in
        let html = """
        <!DOCTYPE html><html><head><title>CERT Field Board API</title>
        <style>body{font-family:-apple-system,sans-serif;padding:40px}h1{color:#007AFF}
        .ep{background:#f5f5f5;padding:10px;margin:10px 0;border-radius:5px}
        code{background:#e0e0e0;padding:2px 6px;border-radius:3px}</style></head>
        <body><h1>🚨 CERT Field Board API</h1><p>Server running.</p>
        <div class="ep"><strong>POST</strong> <code>/api/checkin</code></div>
        <div class="ep"><strong>GET/POST</strong> <code>/api/reports</code></div>
        <div class="ep"><strong>GET/POST/PUT</strong> <code>/api/tasks</code></div>
        <div class="ep"><strong>GET</strong> <code>/api/dashboard</code></div>
        <div class="ep"><strong>GET</strong> <code>/dashboard</code> — Team leader dashboard</div>
        <div class="ep"><strong>GET</strong> <code>/member</code> — Member portal</div>
        </body></html>
        """
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "text/html; charset=utf-8")
        return Response(status: .ok, headers: headers, body: .init(string: html))
    }

    let api = app.grouped("api")

    // PIN validation — middleware accepts or rejects; reaching here means PIN is correct
    api.post("auth") { req async throws -> HTTPStatus in
        return .ok
    }

    api.post("checkin") { req async throws -> CheckInResponse in
        var member = try req.content.decode(CERTMember.self)
        if member.id == nil { member.id = UUID() }
        await dataStore.addMember(member)
        return CheckInResponse(success: true, message: "Checked in successfully", memberID: member.id)
    }

    api.get("members") { req async throws -> [CERTMember] in
        return await dataStore.getAllMembers()
    }

    api.post("reports") { req async throws -> IncidentReport in
        var report = try req.content.decode(IncidentReport.self)
        if report.id == nil { report.id = UUID() }
        await dataStore.addReport(report)
        return report
    }

    api.get("reports") { req async throws -> [IncidentReport] in
        return await dataStore.getAllReports()
    }

    api.put("reports", ":id") { req async throws -> IncidentReport in
        let id = try req.parameters.require("id", as: UUID.self)
        var report = try req.content.decode(IncidentReport.self)
        report.id = id
        report.lastUpdated = Date()
        await dataStore.updateReport(report)
        return report
    }

    api.post("tasks") { req async throws -> CERTTask in
        var task = try req.content.decode(CERTTask.self)
        if task.id == nil { task.id = UUID() }
        task.createdAt = Date()
        await dataStore.addTask(task)
        return task
    }

    api.get("tasks") { req async throws -> [CERTTask] in
        return await dataStore.getAllTasks()
    }

    api.put("tasks", ":id") { req async throws -> CERTTask in
        let id = try req.parameters.require("id", as: UUID.self)
        var task = try req.content.decode(CERTTask.self)
        task.id = id
        if task.status == .completed && task.completedAt == nil { task.completedAt = Date() }
        await dataStore.updateTask(task)
        return task
    }

    api.post("incident") { req async throws -> Incident in
        var incident = try req.content.decode(Incident.self)
        if incident.id == nil { incident.id = UUID() }
        await dataStore.setIncident(incident)
        return incident
    }

    api.get("dashboard") { req async throws -> DashboardData in
        return await dataStore.getDashboardData()
    }

    // ── Sub-team endpoints ────────────────────────────────────────────────────────

    api.post("subteams") { req async throws -> SubTeam in
        var subTeam = try req.content.decode(SubTeam.self)
        if subTeam.id == nil { subTeam.id = UUID() }
        let now = Date()
        subTeam.createdAt = now
        subTeam.lastUpdated = now
        await dataStore.createSubTeam(subTeam)
        return subTeam
    }

    api.get("subteams") { req async throws -> [SubTeam] in
        return await dataStore.getAllSubTeams()
    }

    api.put("subteams", ":id") { req async throws -> SubTeam in
        let id = try req.parameters.require("id", as: UUID.self)
        var subTeam = try req.content.decode(SubTeam.self)
        subTeam.id = id
        await dataStore.updateSubTeam(subTeam)
        return subTeam
    }

    api.delete("subteams", ":id") { req async throws -> HTTPStatus in
        let id = try req.parameters.require("id", as: UUID.self)
        await dataStore.deleteSubTeam(id)
        return .ok
    }

    api.post("members", ":id", "free") { req async throws -> HTTPStatus in
        let id = try req.parameters.require("id", as: UUID.self)
        await dataStore.freeMember(id)
        return .ok
    }

    api.patch("members", ":id", "name") { req async throws -> HTTPStatus in
        let id = try req.parameters.require("id", as: UUID.self)
        struct NameUpdate: Content { var name: String }
        let update = try req.content.decode(NameUpdate.self)
        guard var member = await dataStore.getAllMembers().first(where: { $0.id == id }) else {
            throw Abort(.notFound, reason: "Member not found")
        }
        member.name = update.name
        member.lastUpdated = Date()
        await dataStore.updateMember(member)
        return .ok
    }

    api.patch("reports", ":id", "severity") { req async throws -> IncidentReport in
        let id = try req.parameters.require("id", as: UUID.self)
        struct SeverityUpdate: Content { var severity: IncidentReport.Severity }
        let update = try req.content.decode(SeverityUpdate.self)
        guard var report = await dataStore.getAllReports().first(where: { $0.id == id }) else {
            throw Abort(.notFound, reason: "Report not found")
        }
        report.severity = update.severity
        report.lastUpdated = Date()
        await dataStore.updateReport(report)
        return report
    }

    // ── WebSocket ─────────────────────────────────────────────────────────────────

    app.webSocket("ws") { req, ws in
        print("📱 New WebSocket connection")
        Task {
            await dataStore.addWebSocket(ws)
            let data = await dataStore.getDashboardData()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.keyEncodingStrategy = .convertToSnakeCase
            if let jsonData = try? encoder.encode(data),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                try? await ws.send(jsonString)
            }
        }
        ws.onClose.whenComplete { _ in
            Task { await dataStore.removeWebSocket(ws); print("📱 WebSocket closed") }
        }
    }

    // ── Static pages ──────────────────────────────────────────────────────────────

    app.get("dashboard") { req -> Response in
        return req.fileio.streamFile(at: app.directory.publicDirectory + "dashboard.html")
    }

    app.get("member") { req -> Response in
        return req.fileio.streamFile(at: app.directory.publicDirectory + "member.html")
    }
}
