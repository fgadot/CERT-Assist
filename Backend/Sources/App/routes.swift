//
//  routes.swift
//  CERT Field Board - Backend
//

import Vapor
import Fluent
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
        loadVersions()
        loadActivation()
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
    private var versionConfigURL: URL { URL(fileURLWithPath: "/app/config/versions.json") }
    private var activationURL: URL { URL(fileURLWithPath: "/app/data/activation.json") }

    // ── CERT Activation state ─────────────────────────────────────────────────────
    var isActivated: Bool = false

    func loadActivation() {
        struct ActivationState: Decodable { var isActivated: Bool }
        if let data = try? Data(contentsOf: activationURL),
           let state = try? JSONDecoder().decode(ActivationState.self, from: data) {
            isActivated = state.isActivated
        }
        log("🟢 Activation state loaded: \(isActivated ? "ACTIVATED" : "INACTIVE")")
    }

    func saveActivation() {
        let json = "{\"isActivated\":\(isActivated)}"
        let dir = URL(fileURLWithPath: "/app/data")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? json.data(using: .utf8)?.write(to: activationURL, options: .atomic)
    }

    func setActivated(_ value: Bool) async {
        isActivated = value
        saveActivation()
        log(value ? "🟢 CERT ACTIVATED — team is now visible to county EOC" : "🔴 CERT DEACTIVATED — team removed from county EOC view")
        await broadcastUpdate()
    }

    private var minimumVersion: String = "1.2"
    private var latestVersion: String = "1.2"

    func loadVersions() {
        struct VersionConfig: Decodable { var minimumVersion: String; var latestVersion: String }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        if let data = try? Data(contentsOf: versionConfigURL),
           let config = try? decoder.decode(VersionConfig.self, from: data) {
            minimumVersion = config.minimumVersion
            latestVersion  = config.latestVersion
        }
        log("📱 App versions: minimum=\(minimumVersion), latest=\(latestVersion)")
    }

    func getMinimumVersion() -> String { minimumVersion }
    func getLatestVersion()  -> String { latestVersion  }

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
        let activeMembers = members.values.filter { $0.status == .available || $0.status == .onTask }.count

        return TeamSummary(
            teamID: teamID,
            teamName: teamName,
            isActivated: isActivated,
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
    var countyBanner: BroadcastBanner? = nil

    func setCountyBanner(_ banner: BroadcastBanner?) async {
        countyBanner = banner
        await broadcastUpdate()
    }

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

    // ── Force Checkout ────────────────────────────────────────────────────────────
    // Device tokens queued for "checked out by leader" notification (in-memory)

    private var forceCheckedOutTokens: Set<String> = []   // iOS device tokens
    private var forceCheckedOutMemberIDs: Set<UUID> = []  // web portal member UUIDs

    func markForceCheckout(deviceToken: String?, memberID: UUID?) {
        if let token = deviceToken, !token.isEmpty { forceCheckedOutTokens.insert(token) }
        if let id = memberID { forceCheckedOutMemberIDs.insert(id) }
        log("🚪 FORCE CHECKOUT QUEUED (device/member notification pending)")
    }

    // Returns true and removes the entry if it was queued; false otherwise
    func checkAndClearForceCheckout(deviceToken: String) -> Bool {
        return forceCheckedOutTokens.remove(deviceToken) != nil
    }

    func checkAndClearForceCheckoutByID(_ id: UUID) -> Bool {
        return forceCheckedOutMemberIDs.remove(id) != nil
    }

    func memberByDeviceToken(_ token: String) -> CERTMember? {
        members.values.first { $0.deviceToken == token }
    }

    func subTeamForMember(_ member: CERTMember) -> SubTeam? {
        guard let id = member.subTeamId else { return nil }
        return subTeams[id]
    }

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
        if let apiToken = Environment.get("COUNTY_API_TOKEN"), !apiToken.isEmpty {
            request.setValue(apiToken, forHTTPHeaderField: "X-CERT-API-Token")
        }

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

    func removeMember(id: UUID) async {
        if let m = members.removeValue(forKey: id) {
            log("👋 MEMBER CHECKED OUT (admin): \(m.name)")
        }
        await broadcastUpdate()
        await pushToCounty()
    }

    func updateMember(_ member: CERTMember) async {
        let old = members[member.id!]
        members[member.id!] = member
        if let old {
            if old.status != member.status {
                log("🔄 MEMBER STATUS CHANGE: \(member.name) - \(old.status.rawValue) → \(member.status.rawValue)")
            }
            if old.subTeamId != member.subTeamId {
                let teamInfo = member.subTeamId != nil ? "assigned to sub-team" : "removed from sub-team"
                log("🔄 MEMBER TEAM CHANGE: \(member.name) - \(teamInfo)")
            }
        }
        await broadcastUpdate()
    }

    // ── Reports ───────────────────────────────────────────────────────────────────

    func addReport(_ report: IncidentReport) async {
        reports[report.id!] = report
        let reporterName = members[report.reportedBy]?.name ?? "Unknown"
        let teamInfo = report.subTeamId != nil ? " (Sub-Team Report)" : ""
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
        let teamInfo = task.assignedSubTeamId != nil ? " → Assigned to sub-team" : ""
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
                            m.subTeamId = nil; m.status = .available; members[remainingID] = m
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
                m.subTeamId = subTeam.id; m.status = .onTask; members[memberID] = m
                log("  ↳ Assigned: \(m.name) (\(oldStatus.rawValue) → On Task)")
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
                    m.subTeamId = nil; m.status = .available; members[oldMemberID] = m
                    log("  ↳ Unassigned: \(m.name)")
                }
            }
        }
        subTeams[subTeam.id!] = subTeam
        for memberID in subTeam.memberIDs {
            if var m = members[memberID] {
                m.subTeamId = subTeam.id; m.status = .onTask; members[memberID] = m
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
                m.subTeamId = nil; m.status = .available; members[memberID] = m
            }
        }
        subTeams.removeValue(forKey: id)
        // Clear any tasks that were assigned to this sub-team
        for (taskID, var task) in tasks where task.assignedSubTeamId == id {
            task.assignedSubTeamId = nil
            task.status = .open
            tasks[taskID] = task
            log("  ↳ Task '\(task.title)' unassigned from deleted team")
        }
        await broadcastUpdate()
    }

    func freeMember(_ memberID: UUID) async {
        guard var member = members[memberID] else { return }
        let oldTeamID = member.subTeamId
        member.subTeamId = nil; member.status = .available; members[memberID] = member
        log("🆓 MEMBER FREED: \(member.name) - Set to Available")

        if let teamID = oldTeamID, var team = subTeams[teamID] {
            team.memberIDs.removeAll { $0 == memberID }
            if team.memberIDs.count < 2 {
                log("  ↳ \(team.color.rawValue) Team disbanded (less than 2 members)")
                for remainingID in team.memberIDs {
                    if var m = members[remainingID] {
                        m.subTeamId = nil; m.status = .available; members[remainingID] = m
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
            countyBanner: countyBanner,
            isActivated: isActivated,
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
    if let apiToken = Environment.get("COUNTY_API_TOKEN"), !apiToken.isEmpty {
        req.setValue(apiToken, forHTTPHeaderField: "X-CERT-API-Token")
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
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "text/html; charset=utf-8")
        let html = """
        <!DOCTYPE html><html lang="en"><head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Field Operations</title>
        <style>
          body { margin: 0; background: #f4f4f4; display: flex; align-items: center;
                 justify-content: center; height: 100vh; font-family: -apple-system, sans-serif; }
          p { color: #aaa; font-size: 14px; }
        </style>
        </head><body><p>This site is not publicly available.</p></body></html>
        """
        return Response(status: .ok, headers: headers, body: .init(string: html))
    }

    let api       = app.grouped("api")
    let memberApi = app.grouped(MemberPINMiddleware()).grouped("api")
    let adminApi  = app.grouped(DashboardPINMiddleware()).grouped("api")

    // ── Version check (unprotected — must be reachable by outdated clients) ──────

    struct VersionInfo: Content {
        var minimumVersion: String
        var latestVersion: String
    }

    api.get("version") { req async -> VersionInfo in
        VersionInfo(
            minimumVersion: await dataStore.getMinimumVersion(),
            latestVersion:  await dataStore.getLatestVersion()
        )
    }

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

        // Reject re-registration if a team leader force-checked-out this device
        if let token = member.deviceToken, !token.isEmpty,
           await dataStore.checkAndClearForceCheckout(deviceToken: token) {
            return CheckInResponse(
                success: false,
                message: "You have been checked out by your Team Leader.",
                memberID: nil,
                checkedOutByLeader: true
            )
        }

        // Deduplicate: if a device token matches an existing member, resume that session
        if let token = member.deviceToken, !token.isEmpty {
            let all = await dataStore.getAllMembers()
            if let existing = all.first(where: { $0.deviceToken == token }) {
                var resumed = member
                resumed.id = existing.id
                resumed.subTeamId = existing.subTeamId
                resumed.lentToTeam = existing.lentToTeam
                resumed.lentRequestId = existing.lentRequestId
                await dataStore.updateMember(resumed)
                try? await req.logAudit(
                    action: "member_checkin",
                    actorID: resumed.id?.uuidString,
                    actorName: resumed.name,
                    targetType: "member",
                    targetID: resumed.id?.uuidString,
                    details: ["role": resumed.role, "equipment": resumed.equipment.joined(separator: ", "), "resumed": "true"]
                )
                return CheckInResponse(success: true, message: "Session resumed", memberID: resumed.id)
            }
        }

        if member.id == nil { member.id = UUID() }
        await dataStore.addMember(member)
        try? await req.logAudit(
            action: "member_checkin",
            actorID: member.id?.uuidString,
            actorName: member.name,
            targetType: "member",
            targetID: member.id?.uuidString,
            details: ["role": member.role, "equipment": member.equipment.joined(separator: ", ")]
        )
        return CheckInResponse(success: true, message: "Checked in successfully", memberID: member.id)
    }

    api.get("members") { req async throws -> [CERTMember] in
        return await dataStore.getAllMembers()
    }

    memberApi.post("checkout") { req async throws -> HTTPStatus in
        struct CheckoutBody: Decodable { var memberId: UUID }
        let body = try req.content.decode(CheckoutBody.self)
        guard let member = await dataStore.members[body.memberId] else { return .noContent }
        await dataStore.removeMember(id: body.memberId)
        try? await req.logAudit(
            action: "member_checkout",
            actorID: body.memberId.uuidString,
            actorName: member.name,
            targetType: "member",
            targetID: body.memberId.uuidString,
            details: ["role": member.role, "status_at_checkout": member.status.rawValue]
        )
        return .noContent
    }

    // Poll endpoint — iOS calls with deviceToken, web portal calls with memberId
    memberApi.get("me") { req async throws -> MeResponse in
        struct PollQuery: Decodable { var deviceToken: String?; var memberId: String? }
        let query = (try? req.query.decode(PollQuery.self)) ?? PollQuery(deviceToken: nil, memberId: nil)

        if let token = query.deviceToken, !token.isEmpty,
           await dataStore.checkAndClearForceCheckout(deviceToken: token) {
            return MeResponse(checkedOutByLeader: true)
        }
        if let idString = query.memberId, let id = UUID(uuidString: idString),
           await dataStore.checkAndClearForceCheckoutByID(id) {
            return MeResponse(checkedOutByLeader: true)
        }

        // Resolve the caller's member record to return current sub-team assignment
        var member: CERTMember? = nil
        if let token = query.deviceToken, !token.isEmpty {
            member = await dataStore.memberByDeviceToken(token)
        } else if let idString = query.memberId, let id = UUID(uuidString: idString) {
            member = await dataStore.members[id]
        }

        var subTeamName: String? = nil
        var subTeamColor: String? = nil
        if let m = member, let subTeam = await dataStore.subTeamForMember(m) {
            subTeamName = "\(subTeam.color.rawValue) Team"
            subTeamColor = subTeam.color.rawValue
        }

        var memberTasks: [CERTTask]? = nil
        if let m = member, let memberId = m.id {
            let memberSubTeamId = m.subTeamId
            let assigned = await dataStore.tasks.values.filter { task in
                guard task.status == .open || task.status == .assigned else { return false }
                if task.assignedTo.contains(memberId) { return true }
                if let stId = task.assignedSubTeamId, let mstId = memberSubTeamId, stId == mstId { return true }
                return false
            }
            memberTasks = Array(assigned)
        }

        return MeResponse(checkedOutByLeader: false, subTeamName: subTeamName, subTeamColor: subTeamColor, assignedTasks: memberTasks)
    }

    memberApi.post("reports") { req async throws -> IncidentReport in
        var report = try req.content.decode(IncidentReport.self)
        if report.id == nil { report.id = UUID() }
        // Auto-populate ICS-213 From fields from the checked-in member record
        if let memberRecord = await dataStore.members[report.reportedBy] {
            if report.fromName == nil { report.fromName = memberRecord.name }
            if report.fromPosition == nil { report.fromPosition = memberRecord.icsPosition ?? memberRecord.role }
        }
        if report.toName == nil { report.toName = "Team Leader" }
        await dataStore.addReport(report)
        try? await req.logAudit(
            action: "report_submitted",
            actorID: report.reportedBy.uuidString,
            actorName: report.fromName,
            targetType: "report",
            targetID: report.id?.uuidString,
            details: ["type": report.type.rawValue, "severity": report.severity.rawValue,
                      "location": report.location.address ?? "", "subject": report.subject ?? ""]
        )
        return report
    }

    api.get("reports") { req async throws -> [IncidentReport] in
        return await dataStore.getAllReports()
    }

    // ── Admin API (dashboard PIN) ─────────────────────────────────────────────────

    adminApi.post("members") { req async throws -> CERTMember in
        var member = try req.content.decode(CERTMember.self)
        if member.id == nil { member.id = UUID() }
        member.lastUpdated = Date()
        await dataStore.addMember(member)
        try? await req.logAudit(
            action: "member_checkin",
            actorID: member.id?.uuidString,
            actorName: member.name,
            targetType: "member",
            targetID: member.id?.uuidString,
            details: ["role": member.role, "equipment": member.equipment.joined(separator: ", "), "added_by": "Team Leader"]
        )
        return member
    }

    adminApi.delete("members", ":id") { req async throws -> HTTPStatus in
        let id = try req.parameters.require("id", as: UUID.self)
        guard let member = await dataStore.members[id] else { throw Abort(.notFound) }
        // Queue a force-checkout notification (iOS polls by device token, web polls by member ID)
        await dataStore.markForceCheckout(deviceToken: member.deviceToken, memberID: id)
        await dataStore.removeMember(id: id)
        try? await req.logAudit(
            action: "member_checkout",
            actorID: id.uuidString,
            actorName: member.name,
            targetType: "member",
            targetID: id.uuidString,
            details: ["role": member.role, "status_at_checkout": member.status.rawValue, "checked_out_by": "Team Leader"]
        )
        return .noContent
    }

    // ── CERT Activation / Deactivation ───────────────────────────────────────────

    adminApi.post("activate") { req async throws -> HTTPStatus in
        await dataStore.setActivated(true)
        try? await req.logAudit(action: "cert_activate", actorName: "Team Leader",
            targetType: "team", details: ["status": "activated"])
        return .ok
    }

    adminApi.post("deactivate") { req async throws -> HTTPStatus in
        await dataStore.setActivated(false)
        try? await req.logAudit(action: "cert_deactivate", actorName: "Team Leader",
            targetType: "team", details: ["status": "deactivated"])
        return .ok
    }

    adminApi.put("reports", ":id") { req async throws -> IncidentReport in
        let id = try req.parameters.require("id", as: UUID.self)
        var report = try req.content.decode(IncidentReport.self)
        report.id = id
        report.lastUpdated = Date()
        await dataStore.updateReport(report)
        return report
    }

    adminApi.post("reports", ":id", "reply") { req async throws -> IncidentReport in
        let id = try req.parameters.require("id", as: UUID.self)
        struct ReplyBody: Content { var replyText: String; var repliedByName: String? }
        let body = try req.content.decode(ReplyBody.self)
        guard var report = await dataStore.reports[id] else { throw Abort(.notFound) }
        let reportType = report.type.rawValue
        let reporterName = report.fromName ?? "Member"
        report.replyText = body.replyText
        report.repliedByName = body.repliedByName
        report.repliedAt = Date()
        report.lastUpdated = Date()
        await dataStore.updateReport(report)
        try? await req.logAudit(
            action: "report_replied",
            actorName: body.repliedByName ?? "Team Leader",
            targetType: "report",
            targetID: id.uuidString,
            details: ["report_type": reportType, "reporter": reporterName]
        )
        return report
    }

    adminApi.post("tasks") { req async throws -> CERTTask in
        var task = try req.content.decode(CERTTask.self)
        if task.id == nil { task.id = UUID() }
        task.createdAt = Date()
        await dataStore.addTask(task)
        var taskDetails: [String: Any] = ["title": task.title, "priority": task.priority]
        if let subTeamId = task.assignedSubTeamId,
           let subTeam = await dataStore.subTeams[subTeamId] {
            taskDetails["assigned_team"] = subTeam.color.rawValue
        }
        if !task.notes.isEmpty { taskDetails["notes"] = task.notes }
        try? await req.logAudit(
            action: "task_created",
            actorName: "Team Leader",
            targetType: "task",
            targetID: task.id?.uuidString,
            details: taskDetails
        )
        return task
    }

    api.get("tasks") { req async throws -> [CERTTask] in
        return await dataStore.getAllTasks()
    }

    adminApi.put("tasks", ":id") { req async throws -> CERTTask in
        let id = try req.parameters.require("id", as: UUID.self)
        let oldTask = await dataStore.tasks[id]
        var task = try req.content.decode(CERTTask.self)
        task.id = id
        if task.status == .completed && task.completedAt == nil { task.completedAt = Date() }
        await dataStore.updateTask(task)
        let action: String
        if task.status == .completed && oldTask?.status != .completed {
            action = "task_completed"
        } else {
            action = "task_updated"
        }
        var taskDetails: [String: Any] = [
            "title": task.title,
            "priority": task.priority,
            "status": task.status.rawValue
        ]
        if let subTeamId = task.assignedSubTeamId,
           let subTeam = await dataStore.subTeams[subTeamId] {
            taskDetails["assigned_team"] = subTeam.color.rawValue
        }
        if !task.notes.isEmpty { taskDetails["notes"] = task.notes }
        try? await req.logAudit(
            action: action,
            actorName: "Team Leader",
            targetType: "task",
            targetID: id.uuidString,
            details: taskDetails
        )
        return task
    }

    // ── Member-accessible task actions ───────────────────────────────────────────

    memberApi.post("tasks", ":id", "comment") { req async throws -> CERTTask in
        let id = try req.parameters.require("id", as: UUID.self)
        struct CommentBody: Content { var text: String; var authorName: String? }
        let body = try req.content.decode(CommentBody.self)
        guard var task = await dataStore.tasks[id] else { throw Abort(.notFound) }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone.current
        let timeStr = formatter.string(from: Date())
        let author = (body.authorName?.isEmpty == false) ? body.authorName! : "Member"
        let newEntry = "[\(timeStr)] \(author): \(body.text)"
        task.notes = task.notes.isEmpty ? newEntry : task.notes + "\n" + newEntry
        await dataStore.updateTask(task)
        try? await req.logAudit(
            action: "task_comment",
            actorName: author,
            targetType: "task",
            targetID: id.uuidString,
            details: ["title": task.title, "comment": body.text]
        )
        return task
    }

    memberApi.post("tasks", ":id", "complete") { req async throws -> CERTTask in
        let id = try req.parameters.require("id", as: UUID.self)
        guard var task = await dataStore.tasks[id] else { throw Abort(.notFound) }
        // Identify who completed it — use sub-team name if assigned, otherwise "Team Member"
        var fromName = "Team Member"
        var taskDetails: [String: Any] = ["title": task.title, "priority": task.priority]
        if let subTeamId = task.assignedSubTeamId,
           let subTeam = await dataStore.subTeams[subTeamId] {
            fromName = "\(subTeam.color.rawValue) Team"
            taskDetails["assigned_team"] = subTeam.color.rawValue
        }
        task.status = .completed
        task.completedAt = Date()
        await dataStore.updateTask(task)
        try? await req.logAudit(
            action: "task_completed",
            actorName: fromName,
            targetType: "task",
            targetID: id.uuidString,
            details: taskDetails
        )
        return task
    }

    adminApi.post("incident") { req async throws -> Incident in
        var incident = try req.content.decode(Incident.self)
        if incident.id == nil { incident.id = UUID() }
        let isNew = await dataStore.currentIncident == nil
        await dataStore.setIncident(incident)
        try? await req.logAudit(
            action: isNew ? "incident_started" : "incident_updated",
            actorName: "Team Leader",
            targetType: "incident",
            targetID: incident.id?.uuidString,
            details: ["name": incident.name, "active": incident.isActive ? "Yes" : "No"]
        )
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
        let allMembers = await dataStore.getAllMembers()
        let memberNames = allMembers.filter { m in m.id.map { subTeam.memberIDs.contains($0) } ?? false }.map { $0.name }
        try? await req.logAudit(
            action: "subteam_created",
            actorName: "Team Leader",
            targetType: "subteam",
            targetID: subTeam.id?.uuidString,
            details: ["color": subTeam.color.rawValue, "members": memberNames.joined(separator: ", ")]
        )
        return subTeam
    }

    api.get("subteams") { req async throws -> [SubTeam] in
        return await dataStore.getAllSubTeams()
    }

    adminApi.put("subteams", ":id") { req async throws -> SubTeam in
        let id = try req.parameters.require("id", as: UUID.self)
        var subTeam = try req.content.decode(SubTeam.self)
        subTeam.id = id
        if subTeam.memberIDs.isEmpty {
            await dataStore.deleteSubTeam(id)
            try? await req.logAudit(
                action: "subteam_dissolved",
                actorName: "Team Leader",
                targetType: "subteam",
                targetID: id.uuidString,
                details: ["color": subTeam.color.rawValue, "reason": "last member removed"]
            )
        } else {
            await dataStore.updateSubTeam(subTeam)
            let allMembers = await dataStore.getAllMembers()
            let memberNames = allMembers.filter { m in m.id.map { subTeam.memberIDs.contains($0) } ?? false }.map { $0.name }
            try? await req.logAudit(
                action: "subteam_updated",
                actorName: "Team Leader",
                targetType: "subteam",
                targetID: id.uuidString,
                details: ["color": subTeam.color.rawValue, "members": memberNames.joined(separator: ", ")]
            )
        }
        return subTeam
    }

    adminApi.delete("subteams", ":id") { req async throws -> HTTPStatus in
        let id = try req.parameters.require("id", as: UUID.self)
        let subTeam = await dataStore.subTeams[id]
        await dataStore.deleteSubTeam(id)
        try? await req.logAudit(
            action: "subteam_dissolved",
            actorName: "Team Leader",
            targetType: "subteam",
            targetID: id.uuidString,
            details: ["color": subTeam?.color.rawValue ?? "Unknown"]
        )
        return .ok
    }

    adminApi.post("members", ":id", "free") { req async throws -> HTTPStatus in
        let id = try req.parameters.require("id", as: UUID.self)
        let member = await dataStore.members[id]
        await dataStore.freeMember(id)
        try? await req.logAudit(
            action: "member_freed",
            actorName: "Team Leader",
            targetType: "member",
            targetID: id.uuidString,
            details: ["name": member?.name ?? "Unknown", "role": member?.role ?? ""]
        )
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
        let oldStatus = member.status
        member.status = update.status
        member.lastUpdated = Date()
        await dataStore.updateMember(member)
        try? await req.logAudit(
            action: "status_change",
            actorID: id.uuidString,
            actorName: member.name,
            targetType: "member",
            targetID: id.uuidString,
            details: ["from": oldStatus.rawValue, "to": update.status.rawValue]
        )
        return .ok
    }

    memberApi.patch("members", ":id", "location") { req async throws -> HTTPStatus in
        let id = try req.parameters.require("id", as: UUID.self)
        struct LocationUpdate: Content {
            var latitude: Double
            var longitude: Double
            var address: String?
            var timestamp: Date
        }
        let update = try req.content.decode(LocationUpdate.self)
        guard var member = await dataStore.getAllMembers().first(where: { $0.id == id }) else {
            return .noContent
        }
        member.location = LocationData(latitude: update.latitude, longitude: update.longitude,
                                       address: update.address, timestamp: update.timestamp)
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
        let oldSeverity = report.severity
        report.severity = update.severity
        report.lastUpdated = Date()
        await dataStore.updateReport(report)
        try? await req.logAudit(
            action: "report_severity_changed",
            actorName: "Team Leader",
            targetType: "report",
            targetID: id.uuidString,
            details: ["type": report.type.rawValue, "from": oldSeverity.rawValue, "to": update.severity.rawValue,
                      "reporter": report.fromName ?? "Member"]
        )
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
    adminApi.post("county", "flag") { req async throws -> TeamFlag in
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
        guard let flag = await countyDecode(TeamFlag.self, method: "POST", endpoint: endpoint,
                                             path: "/api/team-flags", body: bodyData) else {
            throw Abort(.badGateway, reason: "County flag creation failed")
        }
        return flag
    }

    adminApi.get("county", "my-flags") { req async throws -> [TeamFlag] in
        guard let endpoint = await dataStore.getCountyEndpoint() else { return [] }
        let teamId = await dataStore.getTeamID()
        return await countyDecode([TeamFlag].self, method: "GET", endpoint: endpoint,
                                   path: "/api/team-flags?team=\(teamId)") ?? []
    }

    // ── Incident Log (FEMA ICS-214) ───────────────────────────────────────────────

    adminApi.get("auditlog") { req async throws -> [AuditLog] in
        let limit = (try? req.query.get(Int.self, at: "limit")) ?? 500
        return try await AuditLog.query(on: req.db)
            .sort(\.$timestamp, .descending)
            .limit(limit)
            .all()
    }

    adminApi.get("auditlog", "export") { req async throws -> Response in
        let entries = try await AuditLog.query(on: req.db)
            .sort(\.$timestamp, .ascending)
            .all()
        let teamName = await dataStore.getTeamName()
        let incident = await dataStore.currentIncident
        let incidentName = incident?.name ?? "CERT Activation"
        let html = buildICS214HTML(teamName: teamName, incidentName: incidentName, entries: entries)
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "text/html; charset=utf-8")
        return Response(status: .ok, headers: headers, body: .init(string: html))
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

    // Changelog only accessible with dashboard PIN
    app.grouped(DashboardPINMiddleware()).get("changelog") { req -> Response in
        return req.fileio.streamFile(at: app.directory.publicDirectory + "changelog.html")
    }
}
