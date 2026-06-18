//
//  PINMiddleware.swift
//  CERT Field Board - Backend
//

import Vapor

struct DashboardPINMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        guard request.method != .GET else { return try await next.respond(to: request) }
        let pin = await dataStore.getDashboardPin()
        guard !pin.isEmpty else { throw Abort(.unauthorized, reason: "Dashboard PIN not configured") }
        let token = request.headers.first(name: "X-CERT-Token") ?? ""
        guard token == pin else { throw Abort(.unauthorized, reason: "Invalid dashboard PIN") }
        return try await next.respond(to: request)
    }
}

struct MemberPINMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        guard request.method != .GET else { return try await next.respond(to: request) }
        let pin = await dataStore.getMemberPin()
        if pin.isEmpty { return try await next.respond(to: request) }
        let token = request.headers.first(name: "X-CERT-Token") ?? ""
        guard token == pin else { throw Abort(.unauthorized, reason: "Invalid member PIN") }
        return try await next.respond(to: request)
    }
}
