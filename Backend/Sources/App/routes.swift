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
        loadPins()
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

    // ── PIN Management ─────────────────────────────────────────────────────────────

    private var dashboardPin: String?
    private var memberPin: String?

    private struct PinConfig: Codable {
        var dashboardPin: String?
        var memberPin: String?
    }

    private var pinConfigURL: URL { URL(fileURLWithPath: "/app/config/pins.json") }

    func loadPins() {
        if let data = try? Data(contentsOf: pinConfigURL),
           let config = try? JSONDecoder().decode(PinConfig.self, from: data) {
            dashboardPin = config.dashboardPin?.isEmpty == false ? config.dashboardPin : nil
            memberPin    = config.memberPin?.isEmpty == false    ? config.memberPin    : nil
        }
        // Fall back to env vars; TEAM_PIN initializes both PINs if neither is set from file
        let envPin = Environment.get("DASHBOARD_PIN") ?? Environment.get("TEAM_PIN")
        if (dashboardPin ?? "").isEmpty { dashboardPin = envPin }
        if (memberPin ?? "").isEmpty    { memberPin = Environment.get("MEMBER_PIN") ?? envPin }
        log("🔐 PINs: dashboard=\(isDashboardPinSet() ? "set" : "NOT SET — first-run required"), member=\(isMemberPinSet() ? "set" : "open")")
    }

    private func savePins() {
        let config = PinConfig(dashboardPin: dashboardPin, memberPin: memberPin)
        let dir = URL(fileURLWithPath: "/app/config")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(config) {
            try? data.write(to: pinConfigURL, options: .atomic)
        }
    }

    func getDashboardPin() -> String { dashboardPin ?? "" }
    func getMemberPin()   -> String { memberPin   ?? "" }
    func isDashboardPinSet() -> Bool { !(dashboardPin ?? "").isEmpty }
    func isMemberPinSet()    -> Bool { !(memberPin    ?? "").isEmpty }

    func setDashboardPin(_ pin: String) {
        dashboardPin = pin.isEmpty ? nil : pin
        savePins()
        log("🔐 Dashboard PIN \(pin.isEmpty ? "cleared" : "updated")")
    }

    func setMemberPin(_ pin: String) {
        memberPin = pin.isEmpty ? nil : pin
        savePins()
        log("🔐 Member PIN \(pin.isEmpty ? "cleared" : "updated")")
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

    // Inbox of received county alert/info messages, kept for dashboard display (last 50)
    var countyInbox: [CountyMessage] = []

    func applyCountyMessage(_ message: CountyMessage) {
        switch message.type {
        case .acknowledgment:
            if let reportId = message.reportId, var report = reports[reportId] {
                report.acknowledgedByCounty = true
                report.acknowledgedAt = message.timestamp
                reports[reportId] = report
                log("✅ COUNTY ACK: \(report.type.rawValue) acknowledged by County EOC")
            }
        case .alert:
            countyInbox.append(message)
            if countyInbox.count > 50 { countyInbox.removeFirst() }
            log("⚠️ COUNTY ALERT: \(message.text)")
        case .info:
            countyInbox.append(message)
            if countyInbox.count > 50 { countyInbox.removeFirst() }
            log("ℹ️ COUNTY MESSAGE: \(message.text)")
        case .transferRequest:
            log("📥 TRANSFER REQUEST: \(message.text)")
        case .transferResponse:
            log("📤 TRANSFER RESPONSE: \(message.text)")
        case .transferRelease:
            // Requesting team returned a borrowed member — clear our lentToTeam flag
            if let memberId = message.reportId, var member = members[memberId] {
                member.lentToTeam = nil
                member.lentRequestId = nil
                members[memberId] = member
                log("📤 MEMBER RETURNED: \(member.name) returned from \(message.text)")
            }
        case .transferRecallRequest:
            // Owning team wants their member back — Beta's dashboard will show this via transfer poll
            log("🔔 RECALL REQUEST: \(message.text)")
        }
    }

    // ── Loanable Members ──────────────────────────────────────────────────────────

    var loanableMembers: Set<UUID> = []

    func setLoanable(_ id: UUID, loanable: Bool) async {
        if loanable { loanableMembers.insert(id) } else { loanableMembers.remove(id) }
        log("🔄 LOANABLE: \(id) → \(loanable ? "available for transfer" : "not available")")
        await broadcastUpdate()
    }

    func setLentToTeam(_ teamId: String?, memberId: UUID, requestId: String? = nil) async {
        guard var member = members[memberId] else { return }
        member.lentToTeam = teamId
        member.lentRequestId = requestId
        members[memberId] = member
        if let teamId {
            log("🤝 LENT: \(member.name) on loan to \(teamId) (request: \(requestId ?? "?"))")
        } else {
            log("🔙 RETURNED: \(member.name) loan cleared")
        }
        await broadcastUpdate()
    }

    func getLoanableMembers() -> [UUID] { Array(loanableMembers) }

    func getCountyEndpoint() -> String? { countyEndpoint }
    func getTeamID() -> String { teamID }
    func getTeamName() -> String { teamName }

    private func pushToCounty() async {
        guard let countyEndpoint else { return }
        // Don't push to county until at least one member is checked in
        guard !members.isEmpty else { return }
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
            loanableMembers: Array(loanableMembers),
            countyInbox: countyInbox,
            lastUpdate: Date()
        )
    }
}

// MARK: - County HTTP helpers (free functions, not in actor)

private func countyRequest(
    method: String, endpoint: String, path: String, body: Data? = nil
) async -> Data? {
    guard let url = URL(string: "\(endpoint)\(path)") else { return nil }
    var req = URLRequest(url: url)
    req.httpMethod = method
    req.timeoutInterval = 10
    if let body {
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
    }
    if let pin = Environment.get("COUNTY_PIN"), !pin.isEmpty {
        req.setValue(pin, forHTTPHeaderField: "X-CERT-Token")
    }
    return await withCheckedContinuation { cont in
        URLSession.shared.dataTask(with: req) { d, _, _ in cont.resume(returning: d) }.resume()
    }
}

private func countyDecode<T: Decodable>(_ type: T.Type, method: String, endpoint: String, path: String, body: Data? = nil) async -> T? {
    guard let data = await countyRequest(method: method, endpoint: endpoint, path: path, body: body) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try? decoder.decode(type, from: data)
}

private func countyEncode<T: Encodable>(_ value: T) -> Data? {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.keyEncodingStrategy = .convertToSnakeCase
    return try? encoder.encode(value)
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

    let api       = app.grouped("api")
    let memberApi = app.grouped(MemberPINMiddleware()).grouped("api")
    let adminApi  = app.grouped(DashboardPINMiddleware()).grouped("api")

    // ── Setup (unprotected) ───────────────────────────────────────────────────────

    api.get("setup", "status") { req async throws -> [String: Bool] in
        return [
            "dashboard_pin_set": await dataStore.isDashboardPinSet(),
            "member_pin_set":    await dataStore.isMemberPinSet()
        ]
    }

    api.post("setup", "dashboard-pin") { req async throws -> HTTPStatus in
        struct PinSetup: Content { var pin: String; var currentPin: String? }
        let body = try req.content.decode(PinSetup.self)
        let current = await dataStore.getDashboardPin()
        if !current.isEmpty {
            guard body.currentPin == current else {
                throw Abort(.unauthorized, reason: "Incorrect current PIN")
            }
        }
        guard body.pin.count >= 4 else {
            throw Abort(.badRequest, reason: "PIN must be at least 4 characters")
        }
        let isFirstRun = current.isEmpty
        await dataStore.setDashboardPin(body.pin)
        // On first-run, seed the member PIN to the same value so check-in is protected immediately
        if isFirstRun {
            let memberAlreadySet = await dataStore.isMemberPinSet()
            if !memberAlreadySet { await dataStore.setMemberPin(body.pin) }
        }
        return .ok
    }

    // ── Dashboard auth validation (dashboard PIN required) ────────────────────────

    adminApi.post("auth") { req async throws -> HTTPStatus in
        return .ok
    }

    // ── Member API (member PIN) ───────────────────────────────────────────────────

    memberApi.post("checkin") { req async throws -> CheckInResponse in
        var member = try req.content.decode(CERTMember.self)
        if member.id == nil { member.id = UUID() }
        await dataStore.addMember(member)
        return CheckInResponse(success: true, message: "Checked in successfully", memberID: member.id)
    }

    api.get("members") { req async throws -> [CERTMember] in
        return await dataStore.getAllMembers()
    }

    memberApi.post("reports") { req async throws -> IncidentReport in
        var report = try req.content.decode(IncidentReport.self)
        if report.id == nil { report.id = UUID() }
        await dataStore.addReport(report)
        return report
    }

    api.get("reports") { req async throws -> [IncidentReport] in
        return await dataStore.getAllReports()
    }

    // ── Admin API (dashboard PIN) ─────────────────────────────────────────────────

    adminApi.put("reports", ":id") { req async throws -> IncidentReport in
        let id = try req.parameters.require("id", as: UUID.self)
        var report = try req.content.decode(IncidentReport.self)
        report.id = id
        report.lastUpdated = Date()
        await dataStore.updateReport(report)
        return report
    }

    adminApi.post("tasks") { req async throws -> CERTTask in
        var task = try req.content.decode(CERTTask.self)
        if task.id == nil { task.id = UUID() }
        task.createdAt = Date()
        await dataStore.addTask(task)
        return task
    }

    api.get("tasks") { req async throws -> [CERTTask] in
        return await dataStore.getAllTasks()
    }

    adminApi.put("tasks", ":id") { req async throws -> CERTTask in
        let id = try req.parameters.require("id", as: UUID.self)
        var task = try req.content.decode(CERTTask.self)
        task.id = id
        if task.status == .completed && task.completedAt == nil { task.completedAt = Date() }
        await dataStore.updateTask(task)
        return task
    }

    adminApi.post("incident") { req async throws -> Incident in
        var incident = try req.content.decode(Incident.self)
        if incident.id == nil { incident.id = UUID() }
        await dataStore.setIncident(incident)
        return incident
    }

    api.get("dashboard") { req async throws -> DashboardData in
        return await dataStore.getDashboardData()
    }

    // ── Sub-team endpoints ────────────────────────────────────────────────────────

    adminApi.post("subteams") { req async throws -> SubTeam in
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

    adminApi.put("subteams", ":id") { req async throws -> SubTeam in
        let id = try req.parameters.require("id", as: UUID.self)
        var subTeam = try req.content.decode(SubTeam.self)
        subTeam.id = id
        await dataStore.updateSubTeam(subTeam)
        return subTeam
    }

    adminApi.delete("subteams", ":id") { req async throws -> HTTPStatus in
        let id = try req.parameters.require("id", as: UUID.self)
        await dataStore.deleteSubTeam(id)
        return .ok
    }

    adminApi.post("members", ":id", "free") { req async throws -> HTTPStatus in
        let id = try req.parameters.require("id", as: UUID.self)
        await dataStore.freeMember(id)
        return .ok
    }

    memberApi.patch("members", ":id", "name") { req async throws -> HTTPStatus in
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

    memberApi.patch("members", ":id", "status") { req async throws -> HTTPStatus in
        let id = try req.parameters.require("id", as: UUID.self)
        struct StatusUpdate: Content { var status: CERTMember.MemberStatus }
        let update = try req.content.decode(StatusUpdate.self)
        guard var member = await dataStore.getAllMembers().first(where: { $0.id == id }) else {
            throw Abort(.notFound, reason: "Member not found")
        }
        member.status = update.status
        member.lastUpdated = Date()
        await dataStore.updateMember(member)
        return .ok
    }

    adminApi.patch("reports", ":id", "severity") { req async throws -> IncidentReport in
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

    adminApi.put("config", "member-pin") { req async throws -> HTTPStatus in
        struct PinUpdate: Content { var pin: String }
        let body = try req.content.decode(PinUpdate.self)
        await dataStore.setMemberPin(body.pin)
        return .ok
    }

    // ── County transfer / loanable members ───────────────────────────────────────

    api.get("config") { req async throws -> Response in
        let teamID = await dataStore.getTeamID()
        let teamName = await dataStore.getTeamName()
        let countyEnabled = await dataStore.getCountyEndpoint() != nil
        let safe = teamName.replacingOccurrences(of: "\"", with: "\\\"")
        let json = "{\"team_id\":\"\(teamID)\",\"team_name\":\"\(safe)\",\"county_enabled\":\(countyEnabled)}"
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/json")
        return Response(status: .ok, headers: headers, body: .init(string: json))
    }

    adminApi.patch("members", ":id", "loanable") { req async throws -> HTTPStatus in
        let id = try req.parameters.require("id", as: UUID.self)
        struct LoanableBody: Content { var loanable: Bool }
        let body = try req.content.decode(LoanableBody.self)
        guard let member = await dataStore.getAllMembers().first(where: { $0.id == id }) else {
            throw Abort(.notFound)
        }
        await dataStore.setLoanable(id, loanable: body.loanable)
        if let endpoint = await dataStore.getCountyEndpoint() {
            if body.loanable {
                let avail = AvailableMember(
                    memberId: id,
                    teamId: await dataStore.getTeamID(),
                    teamName: await dataStore.getTeamName(),
                    memberName: member.name,
                    memberRole: member.role,
                    addedAt: Date()
                )
                if let data = countyEncode(avail) {
                    _ = await countyRequest(method: "POST", endpoint: endpoint,
                                            path: "/api/available-members", body: data)
                }
            } else {
                _ = await countyRequest(method: "DELETE", endpoint: endpoint,
                                        path: "/api/available-members/\(id)")
            }
        }
        return .ok
    }

    adminApi.get("county", "available-members") { req async throws -> [AvailableMember] in
        guard let endpoint = await dataStore.getCountyEndpoint() else { return [] }
        let teamID = await dataStore.getTeamID()
        return await countyDecode([AvailableMember].self, method: "GET", endpoint: endpoint,
                                   path: "/api/available-members?exclude=\(teamID)") ?? []
    }

    adminApi.post("county", "transfer-requests") { req async throws -> TransferRequest in
        guard let endpoint = await dataStore.getCountyEndpoint() else {
            throw Abort(.serviceUnavailable, reason: "County server not configured")
        }
        struct RequestBody: Content { var owningTeamId: String; var memberId: UUID; var memberName: String }
        let body = try req.content.decode(RequestBody.self)
        struct FullBody: Encodable {
            var requestingTeamId: String; var requestingTeamName: String
            var owningTeamId: String; var memberId: UUID; var memberName: String
        }
        let full = FullBody(
            requestingTeamId: await dataStore.getTeamID(),
            requestingTeamName: await dataStore.getTeamName(),
            owningTeamId: body.owningTeamId,
            memberId: body.memberId,
            memberName: body.memberName
        )
        guard let bodyData = countyEncode(full),
              let result = await countyDecode(TransferRequest.self, method: "POST", endpoint: endpoint,
                                              path: "/api/transfer-requests", body: bodyData)
        else { throw Abort(.badGateway, reason: "County server error") }
        return result
    }

    adminApi.get("county", "transfer-requests") { req async throws -> [TransferRequest] in
        guard let endpoint = await dataStore.getCountyEndpoint() else { return [] }
        let teamID = await dataStore.getTeamID()
        return await countyDecode([TransferRequest].self, method: "GET", endpoint: endpoint,
                                   path: "/api/transfer-requests?team=\(teamID)") ?? []
    }

    adminApi.put("county", "transfer-requests", ":id") { req async throws -> TransferRequest in
        guard let endpoint = await dataStore.getCountyEndpoint() else {
            throw Abort(.serviceUnavailable, reason: "County server not configured")
        }
        let id = try req.parameters.require("id", as: UUID.self)
        struct RespondBody: Content { var status: String }
        let body = try req.content.decode(RespondBody.self)
        struct FullBody: Encodable { var status: String; var teamId: String }
        let full = FullBody(status: body.status, teamId: await dataStore.getTeamID())
        guard let bodyData = countyEncode(full),
              let result = await countyDecode(TransferRequest.self, method: "PUT", endpoint: endpoint,
                                              path: "/api/transfer-requests/\(id)", body: bodyData)
        else { throw Abort(.badGateway, reason: "County server error") }
        if body.status == "Accepted" {
            // Member is now on loan — mark locally so the dashboard shows the lent badge
            await dataStore.setLoanable(result.memberId, loanable: false)
            await dataStore.setLentToTeam(result.requestingTeamId, memberId: result.memberId,
                                          requestId: result.id.uuidString)
        }
        // RecallRequested: no backend state change — member stays lent; dashboard derives
        // "Recall Sent" state from currentLoanedOut (transfer request poll).
        return result
    }

    adminApi.delete("county", "transfer-requests", ":id") { req async throws -> HTTPStatus in
        guard let endpoint = await dataStore.getCountyEndpoint() else {
            throw Abort(.serviceUnavailable, reason: "County server not configured")
        }
        let id = try req.parameters.require("id", as: UUID.self)
        let teamId = await dataStore.getTeamID()
        // County returns the transfer request so we know which member to un-mark
        if let result = await countyDecode(TransferRequest.self, method: "DELETE", endpoint: endpoint,
                                           path: "/api/transfer-requests/\(id)?team=\(teamId)") {
            // If we're the owning team (Alpha recalling), clear lentToTeam immediately
            if result.owningTeamId == teamId {
                await dataStore.setLentToTeam(nil, memberId: result.memberId)
            }
        }
        return .ok
    }

    // ── Flag for county EOC review ────────────────────────────────────────────────
    adminApi.post("county", "flag") { req async throws -> HTTPStatus in
        guard let endpoint = await dataStore.getCountyEndpoint() else {
            throw Abort(.serviceUnavailable, reason: "County server not configured")
        }
        struct FlagBody: Content { var text: String }
        let body = try req.content.decode(FlagBody.self)
        struct FullBody: Encodable { var teamId: String; var teamName: String; var text: String }
        let full = FullBody(
            teamId: await dataStore.getTeamID(),
            teamName: await dataStore.getTeamName(),
            text: body.text
        )
        guard let bodyData = countyEncode(full) else { throw Abort(.internalServerError) }
        _ = await countyRequest(method: "POST", endpoint: endpoint, path: "/api/team-flags", body: bodyData)
        return .ok
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
