//
//  routes.swift
//  CERT Field Board - Backend
//

import Vapor

actor DataStore {
    var currentIncident: Incident?
    var members: [UUID: CERTMember] = [:]
    var reports: [UUID: IncidentReport] = [:]
    var tasks: [UUID: CERTTask] = [:]
    var subTeams: [UUID: SubTeam] = [:]  // ← NEW: Store sub-teams
    var connectedWebSockets: [WebSocket] = []
    
    // Audit log file
    private let logFileURL: URL
    
    init() {
        // Create logs directory if it doesn't exist
        let logsDir = URL(fileURLWithPath: "/app/logs")
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        
        // Create log file with timestamp
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())
        logFileURL = logsDir.appendingPathComponent("cert-audit-\(dateString).log")
        
        // Create file if it doesn't exist
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }
        
        log("🚀 DataStore initialized - Audit logging started")
    }
    
    private func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logEntry = "[\(timestamp)] \(message)\n"
        
        // Print to console
        print(logEntry, terminator: "")
        
        // Write to file
        if let data = logEntry.data(using: .utf8) {
            if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            }
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
        
        guard let jsonData = try? encoder.encode(data),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }
        
        for ws in connectedWebSockets {
            try? await ws.send(jsonString)
        }
    }
    
    func addMember(_ member: CERTMember) async {
        members[member.id!] = member
        log("✅ MEMBER CHECK-IN: \(member.name) (\(member.role)) - Status: \(member.status.rawValue) - Equipment: \(member.equipment.joined(separator: ", "))")
        await broadcastUpdate()
    }
    
    func getAllMembers() -> [CERTMember] {
        return Array(members.values)
    }
    
    func updateMember(_ member: CERTMember) async {
        let oldMember = members[member.id!]
        members[member.id!] = member
        
        if let old = oldMember {
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
    
    func addReport(_ report: IncidentReport) async {
        reports[report.id!] = report
        
        let reporterName = members[report.reportedBy]?.name ?? "Unknown"
        let teamInfo = report.subTeamID != nil ? " (Sub-Team Report)" : ""
        log("📋 NEW REPORT: \(report.type.rawValue) - Severity: \(report.severity.rawValue) - Reported by: \(reporterName)\(teamInfo) - Location: \(report.location.address ?? "N/A")")
        
        await broadcastUpdate()
    }
    
    func getAllReports() -> [IncidentReport] {
        return Array(reports.values)
    }
    
    func updateReport(_ report: IncidentReport) async {
        let oldReport = reports[report.id!]
        reports[report.id!] = report
        
        if let old = oldReport {
            if old.severity != report.severity {
                log("🔄 REPORT SEVERITY OVERRIDE: \(report.type.rawValue) - \(old.severity.rawValue) → \(report.severity.rawValue)")
            }
            if old.status != report.status {
                log("🔄 REPORT STATUS CHANGE: \(report.type.rawValue) - \(old.status.rawValue) → \(report.status.rawValue)")
            }
        }
        
        await broadcastUpdate()
    }
    
    func addTask(_ task: CERTTask) async {
        tasks[task.id!] = task
        
        let teamInfo = task.assignedSubTeamID != nil ? " → Assigned to sub-team" : ""
        log("📝 NEW TASK: \(task.title) - Priority: \(task.priority)\(teamInfo)")
        
        await broadcastUpdate()
    }
    
    func getAllTasks() -> [CERTTask] {
        return Array(tasks.values)
    }
    
    func updateTask(_ task: CERTTask) async {
        tasks[task.id!] = task
        await broadcastUpdate()
    }
    
    // ← NEW: Sub-team methods
    func createSubTeam(_ subTeam: SubTeam) async {
        subTeams[subTeam.id!] = subTeam
        
        let memberNames = subTeam.memberIDs.compactMap { members[$0]?.name }
        log("🎨 SUB-TEAM CREATED: \(subTeam.color.rawValue) Team - Members: \(memberNames.joined(separator: ", "))")
        
        // Update members with subTeamID
        for memberID in subTeam.memberIDs {
            if var member = members[memberID] {
                let oldStatus = member.status
                member.subTeamID = subTeam.id
                member.status = .assigned
                members[memberID] = member
                log("  ↳ Assigned: \(member.name) (\(oldStatus.rawValue) → Assigned)")
            }
        }
        
        await broadcastUpdate()
    }
    
    func getAllSubTeams() -> [SubTeam] {
        return Array(subTeams.values)
    }
    
    func updateSubTeam(_ subTeam: SubTeam) async {
        // Remove old members from this sub-team
        if let oldSubTeam = subTeams[subTeam.id!] {
            log("🔄 SUB-TEAM UPDATE: \(subTeam.color.rawValue) Team - Reassigning members")
            
            for oldMemberID in oldSubTeam.memberIDs {
                if var member = members[oldMemberID] {
                    member.subTeamID = nil
                    member.status = .available
                    members[oldMemberID] = member
                    log("  ↳ Unassigned: \(member.name)")
                }
            }
        }
        
        // Update sub-team
        subTeams[subTeam.id!] = subTeam
        
        // Assign new members
        for memberID in subTeam.memberIDs {
            if var member = members[memberID] {
                member.subTeamID = subTeam.id
                member.status = .assigned
                members[memberID] = member
                log("  ↳ Assigned: \(member.name)")
            }
        }
        
        await broadcastUpdate()
    }
    
    func deleteSubTeam(_ id: UUID) async {
        guard let subTeam = subTeams[id] else { return }
        
        let memberNames = subTeam.memberIDs.compactMap { members[$0]?.name }
        log("🗑️ SUB-TEAM DELETED: \(subTeam.color.rawValue) Team - Members unassigned: \(memberNames.joined(separator: ", "))")
        
        // Unassign all members
        for memberID in subTeam.memberIDs {
            if var member = members[memberID] {
                member.subTeamID = nil
                member.status = .available
                members[memberID] = member
            }
        }
        
        subTeams.removeValue(forKey: id)
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
            subTeams: Array(subTeams.values),  // ← NEW: Include sub-teams
            lastUpdate: Date()
        )
    }
}

let dataStore = DataStore()

func routes(_ app: Application) throws {
    
    app.get { req -> Response in
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>CERT Field Board API</title>
            <style>
                body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif; padding: 40px; }
                h1 { color: #007AFF; }
                .endpoint { background: #f5f5f5; padding: 10px; margin: 10px 0; border-radius: 5px; }
                code { background: #e0e0e0; padding: 2px 6px; border-radius: 3px; }
            </style>
        </head>
        <body>
            <h1>🚨 CERT Field Board API</h1>
            <p>Backend server is running!</p>
            
            <h2>Available Endpoints:</h2>
            
            <div class="endpoint">
                <strong>POST</strong> <code>/api/checkin</code><br>
                Check in a CERT member
            </div>
            
            <div class="endpoint">
                <strong>GET</strong> <code>/api/members</code><br>
                Get all checked-in members
            </div>
            
            <div class="endpoint">
                <strong>POST</strong> <code>/api/reports</code><br>
                Submit an incident report
            </div>
            
            <div class="endpoint">
                <strong>GET</strong> <code>/api/reports</code><br>
                Get all reports
            </div>
            
            <div class="endpoint">
                <strong>POST</strong> <code>/api/tasks</code><br>
                Create a task
            </div>
            
            <div class="endpoint">
                <strong>GET</strong> <code>/api/tasks</code><br>
                Get all tasks
            </div>
            
            <div class="endpoint">
                <strong>GET</strong> <code>/api/dashboard</code><br>
                Get complete dashboard data
            </div>
            
            <div class="endpoint">
                <strong>GET</strong> <code>/dashboard</code><br>
                Web-based incident commander dashboard
            </div>
            
            <p><small>CERT Field Board v1.0 - Swift + Vapor</small></p>
        </body>
        </html>
        """
        
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "text/html; charset=utf-8")
        return Response(status: .ok, headers: headers, body: .init(string: html))
    }
    
    let api = app.grouped("api")
    
    api.post("checkin") { req async throws -> CheckInResponse in
        var member = try req.content.decode(CERTMember.self)
        
        if member.id == nil {
            member.id = UUID()
        }
        
        await dataStore.addMember(member)
        
        return CheckInResponse(
            success: true,
            message: "Checked in successfully",
            memberID: member.id
        )
    }
    
    api.get("members") { req async throws -> [CERTMember] in
        return await dataStore.getAllMembers()
    }
    
    api.post("reports") { req async throws -> IncidentReport in
        var report = try req.content.decode(IncidentReport.self)
        
        if report.id == nil {
            report.id = UUID()
        }
        
        await dataStore.addReport(report)
        
        return report
    }
    
    api.get("reports") { req async throws -> [IncidentReport] in
        return await dataStore.getAllReports()
    }
    
    api.post("tasks") { req async throws -> CERTTask in
        var task = try req.content.decode(CERTTask.self)
        
        if task.id == nil {
            task.id = UUID()
        }
        
        await dataStore.addTask(task)
        
        return task
    }
    
    api.get("tasks") { req async throws -> [CERTTask] in
        return await dataStore.getAllTasks()
    }
    
    api.post("incident") { req async throws -> Incident in
        var incident = try req.content.decode(Incident.self)
        
        if incident.id == nil {
            incident.id = UUID()
        }
        
        await dataStore.setIncident(incident)
        
        return incident
    }
    
    api.get("dashboard") { req async throws -> DashboardData in
        return await dataStore.getDashboardData()
    }
    
    // ← NEW: Sub-team endpoints
    
    api.post("subteams") { req async throws -> SubTeam in
        var subTeam = try req.content.decode(SubTeam.self)
        
        if subTeam.id == nil {
            subTeam.id = UUID()
        }
        
        // Always set timestamps on backend (ignore any sent from client)
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
        
        // Get subteam info before deleting for audit log
        let subTeams = await dataStore.getAllSubTeams()
        let subTeam = subTeams.first { $0.id == id }
        
        await dataStore.deleteSubTeam(id)
        
        return .ok
    }
    
    // Update report severity (team leader can override)
    api.patch("reports", ":id", "severity") { req async throws -> IncidentReport in
        let id = try req.parameters.require("id", as: UUID.self)
        
        struct SeverityUpdate: Content {
            var severity: IncidentReport.Severity
        }
        
        let update = try req.content.decode(SeverityUpdate.self)
        
        guard var report = await dataStore.getAllReports().first(where: { $0.id == id }) else {
            throw Abort(.notFound, reason: "Report not found")
        }
        
        report.severity = update.severity
        report.lastUpdated = Date()
        
        await dataStore.updateReport(report)
        
        return report
    }
    
    app.webSocket("ws") { req, ws in
        print("📱 New WebSocket connection")
        
        Task {
            await dataStore.addWebSocket(ws)
            
            let data = await dataStore.getDashboardData()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            
            if let jsonData = try? encoder.encode(data),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                try? await ws.send(jsonString)
            }
        }
        
        ws.onClose.whenComplete { result in
            Task {
                await dataStore.removeWebSocket(ws)
                print("📱 WebSocket closed")
            }
        }
    }
    
    app.get("dashboard") { req -> Response in
        return req.fileio.streamFile(at: app.directory.publicDirectory + "dashboard.html")
    }
}
