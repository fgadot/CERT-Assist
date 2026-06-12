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
    var connectedWebSockets: [WebSocket] = []
    
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
        await broadcastUpdate()
    }
    
    func getAllMembers() -> [CERTMember] {
        return Array(members.values)
    }
    
    func addReport(_ report: IncidentReport) async {
        reports[report.id!] = report
        await broadcastUpdate()
    }
    
    func getAllReports() -> [IncidentReport] {
        return Array(reports.values)
    }
    
    func addTask(_ task: CERTTask) async {
        tasks[task.id!] = task
        await broadcastUpdate()
    }
    
    func getAllTasks() -> [CERTTask] {
        return Array(tasks.values)
    }
    
    func setIncident(_ incident: Incident) async {
        currentIncident = incident
        await broadcastUpdate()
    }
    
    func getDashboardData() -> DashboardData {
        return DashboardData(
            incident: currentIncident,
            members: Array(members.values),
            reports: Array(reports.values),
            tasks: Array(tasks.values),
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
