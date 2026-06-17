//
//  PINMiddleware.swift
//  CERT Field Board - Backend
//

import Vapor

struct PINAuthMiddleware: AsyncMiddleware {
    let pin: String

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        // GETs (including WebSocket upgrades) pass through unauthenticated
        guard request.method != .GET else {
            return try await next.respond(to: request)
        }
        let token = request.headers.first(name: "X-CERT-Token") ?? ""
        guard token == pin else {
            throw Abort(.unauthorized, reason: "Invalid or missing PIN")
        }
        return try await next.respond(to: request)
    }
}
