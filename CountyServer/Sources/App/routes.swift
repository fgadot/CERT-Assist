//
//  routes.swift
//  CERT County EOC Backend
//

import Vapor

actor CountyDataStore {
    var teams: [String: TeamSummary] = [:]
    var pendingMessages: [String: [CountyMessage]] = [:]   // teamId → pending messages
    var confirmedMessages: [UUID: CountyMessage] = [:]
    var connectedWebSockets: [WebSocket] = []
    var availableMembers: [UUID: AvailableMember] = [:]    // memberId → available member record
    var transferRequests: [UUID: TransferRequest] = [:]    // requestId → transfer request
    var teamFlags: [UUID: TeamFlag] = [:]                  // flags raised by teams for county review

    func updateTeamSummary(_ summary: TeamSummary) async {
        teams[summary.teamId] = summary
        await broadcastUpdate()
    }

    func createMessage(_ message: CountyMessage) async {
        var list = pendingMessages[message.targetTeamId] ?? []
        list.append(message)
        pendingMessages[message.targetTeamId] = list
        await broadcastUpdate()
    }

    func getMessages(for teamId: String) -> [CountyMessage] {
        return pendingMessages[teamId] ?? []
    }

    func confirmMessage(id: UUID) async {
        for (teamId, messages) in pendingMessages {
            if let msg = messages.first(where: { $0.id == id }) {
                var confirmed = msg
                confirmed.confirmed = true
                confirmedMessages[id] = confirmed
                pendingMessages[teamId] = messages.filter { $0.id != id }
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

    // MARK: - Broadcast (county → all registered teams)

    func broadcastMessage(type: CountyMessage.MessageType, text: String) async {
        for teamId in teams.keys {
            let msg = CountyMessage(
                id: UUID(), type: type, targetTeamId: teamId,
                reportId: nil, text: text, timestamp: Date(), confirmed: false
            )
            var list = pendingMessages[teamId] ?? []
            list.append(msg)
            pendingMessages[teamId] = list
        }
        await broadcastUpdate()
    }

    // MARK: - Team Flags (team → county)

    func createTeamFlag(_ flag: TeamFlag) async {
        teamFlags[flag.id] = flag
        await broadcastUpdate()
    }

    func acknowledgeTeamFlag(id: UUID) async -> TeamFlag? {
        guard var flag = teamFlags[id] else { return nil }
        flag.acknowledged = true
        flag.acknowledgedAt = Date()
        teamFlags[id] = flag
        await broadcastUpdate()
        return flag
    }

    func getTeamFlags() -> [TeamFlag] {
        return teamFlags.values.sorted { $0.timestamp > $1.timestamp }
    }

    // MARK: - Available Members

    func registerAvailableMember(_ member: AvailableMember) async {
        availableMembers[member.memberId] = member
        await broadcastUpdate()
    }

    func removeAvailableMember(memberId: UUID) async {
        availableMembers.removeValue(forKey: memberId)
        await broadcastUpdate()
    }

    func getAvailableMembers(excludingTeam teamId: String? = nil) -> [AvailableMember] {
        let all = availableMembers.values
        if let teamId {
            return all.filter { $0.teamId != teamId }.sorted { $0.memberName < $1.memberName }
        }
        return all.sorted { $0.memberName < $1.memberName }
    }

    // MARK: - Transfer Requests

    func createTransferRequest(_ request: TransferRequest) async {
        transferRequests[request.id] = request
        let notify = CountyMessage(
            id: UUID(),
            type: .transferRequest,
            targetTeamId: request.owningTeamId,
            reportId: nil,
            text: "\(request.requestingTeamName) is requesting \(request.memberName)",
            timestamp: Date(),
            confirmed: false
        )
        await createMessage(notify)
    }

    func getTransferRequest(id: UUID) -> TransferRequest? {
        return transferRequests[id]
    }

    func releaseTransfer(id: UUID, callerTeamId: String) async -> TransferRequest? {
        guard var request = transferRequests[id] else { return nil }
        // If a recall was in flight, mark as "Recalled"; otherwise voluntary "Released"
        let wasRecallPending = request.status == .recallRequested
        request.status = wasRecallPending ? .recalled : .released
        request.respondedAt = Date()
        transferRequests[id] = request

        if callerTeamId == request.requestingTeamId {
            // Requesting team returned: notify owning team to clear lentToTeam via county poll
            let notify = CountyMessage(
                id: UUID(),
                type: .transferRelease,
                targetTeamId: request.owningTeamId,
                reportId: request.memberId,
                text: request.requestingTeamId,
                timestamp: Date(),
                confirmed: false
            )
            await createMessage(notify)
        }

        await broadcastUpdate()
        return request
    }

    func requestRecall(id: UUID) async -> TransferRequest? {
        guard var request = transferRequests[id], request.status == .accepted else { return nil }
        request.status = .recallRequested
        request.respondedAt = Date()
        transferRequests[id] = request
        // Notify requesting team (Beta) that owning team wants the member back
        let notify = CountyMessage(
            id: UUID(),
            type: .transferRecallRequest,
            targetTeamId: request.requestingTeamId,
            reportId: request.memberId,
            text: "\(request.owningTeamId) is requesting \(request.memberName) back",
            timestamp: Date(),
            confirmed: false
        )
        await createMessage(notify)
        await broadcastUpdate()
        return request
    }

    func respondToTransferRequest(id: UUID, status: TransferRequest.TransferStatus) async -> TransferRequest? {
        guard var request = transferRequests[id] else { return nil }
        request.status = status
        request.respondedAt = Date()
        transferRequests[id] = request
        let statusText = status == .accepted ? "accepted" : "denied"
        let notify = CountyMessage(
            id: UUID(),
            type: .transferResponse,
            targetTeamId: request.requestingTeamId,
            reportId: nil,
            text: "Transfer of \(request.memberName) was \(statusText) by \(request.owningTeamId)",
            timestamp: Date(),
            confirmed: false
        )
        await createMessage(notify)
        if status == .accepted {
            availableMembers.removeValue(forKey: request.memberId)
        }
        await broadcastUpdate()
        return request
    }

    func getTransferRequests(for teamId: String) -> [TransferRequest] {
        return transferRequests.values
            .filter { $0.requestingTeamId == teamId || $0.owningTeamId == teamId }
            .sorted { $0.requestedAt > $1.requestedAt }
    }

    func getDashboardData() -> CountyDashboardData {
        // Only show teams that have at least one checked-in member
        let activeTeams = teams.values.filter { $0.memberCount > 0 }
        // Sort teams by urgency: life safety first, then unacked high, then by name
        let sorted = activeTeams.sorted { a, b in
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
        guard summary.teamId.range(of: #"^[a-zA-Z0-9\-_]{1,64}$"#, options: .regularExpression) != nil else {
            throw Abort(.badRequest, reason: "Invalid team ID: must be alphanumeric, hyphens, or underscores (max 64 chars)")
        }
        if let endpoint = summary.endpoint {
            let isLocalHTTP = endpoint.hasPrefix("http://localhost") || endpoint.hasPrefix("http://127.0.0.1")
            guard (endpoint.hasPrefix("https://") || isLocalHTTP), URL(string: endpoint) != nil else {
                throw Abort(.badRequest, reason: "Team endpoint must be a valid https:// URL (or http://localhost for local dev)")
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
            targetTeamId: teamId,
            reportId: reportId,
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
            targetTeamId: teamId,
            reportId: nil,
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

    // ── Available Members (team marks member as loanable) ───────────────────────

    app.post("api", "available-members") { req async throws -> HTTPStatus in
        let member = try req.content.decode(AvailableMember.self)
        await countyStore.registerAvailableMember(member)
        return .ok
    }

    app.delete("api", "available-members", ":memberId") { req async throws -> HTTPStatus in
        let memberId = try req.parameters.require("memberId", as: UUID.self)
        await countyStore.removeAvailableMember(memberId: memberId)
        return .ok
    }

    app.get("api", "available-members") { req async throws -> [AvailableMember] in
        let excludeTeam = req.query[String.self, at: "exclude"]
        return await countyStore.getAvailableMembers(excludingTeam: excludeTeam)
    }

    // ── Transfer Requests (cross-team member borrowing) ──────────────────────────

    app.post("api", "transfer-requests") { req async throws -> TransferRequest in
        struct RequestBody: Content {
            var requestingTeamId: String
            var requestingTeamName: String
            var owningTeamId: String
            var memberId: UUID
            var memberName: String
        }
        let body = try req.content.decode(RequestBody.self)

        // Prevent duplicate pending requests for the same member from the same team
        let existing = await countyStore.getTransferRequests(for: body.requestingTeamId)
        let duplicate = existing.first {
            $0.memberId == body.memberId &&
            $0.requestingTeamId == body.requestingTeamId &&
            $0.status == .pending
        }
        if duplicate != nil { throw Abort(.conflict, reason: "Pending request already exists for this member") }

        let request = TransferRequest(
            id: UUID(),
            requestingTeamId: body.requestingTeamId,
            requestingTeamName: body.requestingTeamName,
            owningTeamId: body.owningTeamId,
            memberId: body.memberId,
            memberName: body.memberName,
            status: .pending,
            requestedAt: Date(),
            respondedAt: nil
        )
        await countyStore.createTransferRequest(request)
        return request
    }

    app.get("api", "transfer-requests") { req async throws -> [TransferRequest] in
        guard let teamId = req.query[String.self, at: "team"] else {
            throw Abort(.badRequest, reason: "Missing ?team= parameter")
        }
        return await countyStore.getTransferRequests(for: teamId)
    }

    // ── Release (requesting team acknowledges return) ─────────────────────────────
    app.delete("api", "transfer-requests", ":id") { req async throws -> TransferRequest in
        let id = try req.parameters.require("id", as: UUID.self)
        guard let teamId = req.query[String.self, at: "team"] else {
            throw Abort(.badRequest, reason: "Missing ?team= parameter")
        }
        guard let request = await countyStore.getTransferRequest(id: id) else {
            throw Abort(.notFound, reason: "Transfer request not found")
        }
        guard request.requestingTeamId == teamId || request.owningTeamId == teamId else {
            throw Abort(.forbidden, reason: "Only the requesting or owning team can release")
        }
        guard request.status == .accepted || request.status == .recallRequested else {
            throw Abort(.conflict, reason: "Can only release an accepted or recall-pending transfer")
        }
        guard let released = await countyStore.releaseTransfer(id: id, callerTeamId: teamId) else {
            throw Abort(.internalServerError)
        }
        return released
    }

    app.put("api", "transfer-requests", ":id") { req async throws -> TransferRequest in
        let id = try req.parameters.require("id", as: UUID.self)
        guard let request = await countyStore.getTransferRequest(id: id) else {
            throw Abort(.notFound, reason: "Transfer request not found")
        }
        struct ResponseBody: Content { var status: TransferRequest.TransferStatus; var teamId: String }
        let body = try req.content.decode(ResponseBody.self)

        // Case 1: Owning team responds to a pending request (Accept / Deny)
        if request.status == .pending {
            guard body.teamId == request.owningTeamId else {
                throw Abort(.forbidden, reason: "Only the owning team can respond to a pending request")
            }
            guard body.status == .accepted || body.status == .denied else {
                throw Abort(.badRequest, reason: "Response must be Accepted or Denied")
            }
            guard let updated = await countyStore.respondToTransferRequest(id: id, status: body.status) else {
                throw Abort(.internalServerError)
            }
            return updated
        }

        // Case 2: Owning team initiates a recall (Accepted → RecallRequested)
        if request.status == .accepted {
            guard body.teamId == request.owningTeamId else {
                throw Abort(.forbidden, reason: "Only the owning team can initiate a recall")
            }
            guard body.status == .recallRequested else {
                throw Abort(.badRequest, reason: "Can only send RecallRequested from an accepted transfer")
            }
            guard let updated = await countyStore.requestRecall(id: id) else {
                throw Abort(.internalServerError)
            }
            return updated
        }

        throw Abort(.conflict, reason: "Cannot update a transfer in \(request.status.rawValue) status")
    }

    // ── Broadcast message to all registered teams ────────────────────────────────
    app.post("api", "broadcast") { req async throws -> HTTPStatus in
        struct BroadcastBody: Content { var type: CountyMessage.MessageType; var text: String }
        let body = try req.content.decode(BroadcastBody.self)
        await countyStore.broadcastMessage(type: body.type, text: body.text)
        return .ok
    }

    // ── Team Flags (team → county for EOC review) ─────────────────────────────────
    app.post("api", "team-flags") { req async throws -> TeamFlag in
        struct FlagBody: Content { var teamId: String; var teamName: String; var text: String }
        let body = try req.content.decode(FlagBody.self)
        let flag = TeamFlag(
            id: UUID(), teamId: body.teamId, teamName: body.teamName,
            text: body.text, timestamp: Date(), acknowledged: false, acknowledgedAt: nil
        )
        await countyStore.createTeamFlag(flag)
        return flag
    }

    app.get("api", "team-flags") { req async throws -> [TeamFlag] in
        return await countyStore.getTeamFlags()
    }

    app.post("api", "team-flags", ":id", "acknowledge") { req async throws -> TeamFlag in
        let id = try req.parameters.require("id", as: UUID.self)
        guard let flag = await countyStore.acknowledgeTeamFlag(id: id) else {
            throw Abort(.notFound, reason: "Flag not found")
        }
        return flag
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
