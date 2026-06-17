//
//  routes.swift
//  CERT County EOC Backend
//

import Vapor

actor CountyDataStore {
    var teams: [String: TeamSummary] = [:]
    var pendingMessages: [String: [CountyMessage]] = [:]   // teamID → pending messages
    var confirmedMessages: [UUID: CountyMessage] = [:]
    var connectedWebSockets: [WebSocket] = []

    func updateTeamSummary(_ summary: TeamSummary) async {
        teams[summary.teamID] = summary
        await broadcastUpdate()
    }

    func createMessage(_ message: CountyMessage) async {
        var list = pendingMessages[message.targetTeamID] ?? []
        list.append(message)
        pendingMessages[message.targetTeamID] = list
        await broadcastUpdate()
    }

    func getMessages(for teamID: String) -> [CountyMessage] {
        return pendingMessages[teamID] ?? []
    }

    func confirmMessage(id: UUID) async {
        for (teamID, messages) in pendingMessages {
            if let msg = messages.first(where: { $0.id == id }) {
                var confirmed = msg
                confirmed.confirmed = true
                confirmedMessages[id] = confirmed
                pendingMessages[teamID] = messages.filter { $0.id != id }
                break
            }
        }
        await broadcastUpdate()
    }

    func addWebSocket(_ ws: WebSocket) {
        connectedWebSockets.append(ws)
    }

    func removeWebSocket(_ ws: WebSocket) {
        connectedWebSockets.removeAll { $0 === ws }
    }

    func getDashboardData() -> CountyDashboardData {
        // Sort teams by urgency: life safety first, then unacked high, then by name
        let sorted = teams.values.sorted { a, b in
            let aScore = a.reportCounts.lifeSafety * 10000
                       + a.unacknowledgedPriority * 100
                       + a.reportCounts.high * 10
            let bScore = b.reportCounts.lifeSafety * 10000
                       + b.unacknowledgedPriority * 100
                       + b.reportCounts.high * 10
            if aScore != bScore { return aScore > bScore }
            return a.teamName < b.teamName
        }

        let pendingCounts = pendingMessages.mapValues { $0.count }

        return CountyDashboardData(
            teams: sorted,
            pendingMessageCounts: pendingCounts,
            lastUpdate: Date()
        )
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
    }
}

let countyStore = CountyDataStore()

func routes(_ app: Application) throws {

    // ── PIN validation ────────────────────────────────────────────────────────────
    app.post("api", "auth") { req async throws -> HTTPStatus in
        return .ok
    }

    // ── Team → County: push summary on every state change ──────────────────────
    app.post("api", "teams", "summary") { req async throws -> HTTPStatus in
        let summary = try req.content.decode(TeamSummary.self)
        guard summary.teamID.range(of: #"^[a-zA-Z0-9\-_]{1,64}$"#, options: .regularExpression) != nil else {
            throw Abort(.badRequest, reason: "Invalid team ID: must be alphanumeric, hyphens, or underscores (max 64 chars)")
        }
        if let endpoint = summary.endpoint {
            guard endpoint.hasPrefix("https://"), URL(string: endpoint) != nil else {
                throw Abort(.badRequest, reason: "Team endpoint must be a valid https:// URL")
            }
        }
        await countyStore.updateTeamSummary(summary)
        return .ok
    }

    // ── County dashboard REST snapshot ──────────────────────────────────────────
    app.get("api", "county", "dashboard") { req async throws -> CountyDashboardData in
        return await countyStore.getDashboardData()
    }

    // ── County acknowledges a specific report (creates pending message for team) ─
    app.post("api", "teams", ":teamId", "acknowledge", ":reportId") { req async throws -> CountyMessage in
        let teamId = try req.parameters.require("teamId", as: String.self)
        let reportIdStr = try req.parameters.require("reportId", as: String.self)
        guard let reportId = UUID(uuidString: reportIdStr) else {
            throw Abort(.badRequest, reason: "Invalid report ID")
        }

        struct AckBody: Content { var note: String? }
        let body = try? req.content.decode(AckBody.self)

        let message = CountyMessage(
            id: UUID(),
            type: .acknowledgment,
            targetTeamID: teamId,
            reportID: reportId,
            text: body?.note ?? "Acknowledged by County EOC",
            timestamp: Date(),
            confirmed: false
        )
        await countyStore.createMessage(message)
        return message
    }

    // ── County sends an alert/info message to a team ────────────────────────────
    app.post("api", "teams", ":teamId", "message") { req async throws -> CountyMessage in
        let teamId = try req.parameters.require("teamId", as: String.self)

        struct MessageBody: Content { var type: CountyMessage.MessageType; var text: String }
        let body = try req.content.decode(MessageBody.self)

        let message = CountyMessage(
            id: UUID(),
            type: body.type,
            targetTeamID: teamId,
            reportID: nil,
            text: body.text,
            timestamp: Date(),
            confirmed: false
        )
        await countyStore.createMessage(message)
        return message
    }

    // ── Team polls here for pending messages ─────────────────────────────────────
    app.get("api", "messages") { req async throws -> [CountyMessage] in
        guard let teamId = req.query[String.self, at: "team"] else {
            throw Abort(.badRequest, reason: "Missing ?team= parameter")
        }
        return await countyStore.getMessages(for: teamId)
    }

    // ── Team confirms it processed a message ─────────────────────────────────────
    app.post("api", "messages", ":id", "confirm") { req async throws -> HTTPStatus in
        let id = try req.parameters.require("id", as: UUID.self)
        await countyStore.confirmMessage(id: id)
        return .ok
    }

    // ── County dashboard WebSocket ───────────────────────────────────────────────
    app.webSocket("ws") { req, ws in
        Task {
            await countyStore.addWebSocket(ws)
            let data = await countyStore.getDashboardData()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.keyEncodingStrategy = .convertToSnakeCase
            if let jsonData = try? encoder.encode(data),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                try? await ws.send(jsonString)
            }
        }
        ws.onClose.whenComplete { _ in
            Task { await countyStore.removeWebSocket(ws) }
        }
    }

    // ── Serve county dashboard ───────────────────────────────────────────────────
    app.get("county") { req -> Response in
        return req.fileio.streamFile(at: app.directory.publicDirectory + "county.html")
    }

    app.get { req -> Response in
        return req.redirect(to: "/county")
    }
}
