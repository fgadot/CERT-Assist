//
//  PINMiddleware.swift
//  CERT County EOC Backend
//

import Vapor

struct PINAuthMiddleware: AsyncMiddleware {
    let dashboardPin: String?   // County dashboard login — typed by humans (COUNTY_PIN env var)
    let apiToken: String?       // Machine-to-machine — sent automatically by team servers (COUNTY_API_TOKEN env var)

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        // GETs (including WebSocket upgrades) pass through unauthenticated
        guard request.method != .GET else {
            return try await next.respond(to: request)
        }

        let certToken    = request.headers.first(name: "X-CERT-Token")     ?? ""
        let machineToken = request.headers.first(name: "X-CERT-API-Token") ?? ""

        let dashboardOK = dashboardPin.map { !$0.isEmpty && certToken    == $0 } ?? false
        let apiOK       = apiToken.map     { !$0.isEmpty && machineToken == $0 } ?? false

        guard dashboardOK || apiOK else {
            throw Abort(.unauthorized, reason: "Invalid or missing credentials")
        }
        return try await next.respond(to: request)
    }
}
