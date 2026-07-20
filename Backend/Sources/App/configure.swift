//
//  configure.swift
//  CERT Field Board Backend
//

import Vapor
import Fluent
import FluentSQLiteDriver
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public func configure(_ app: Application) throws {

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.keyEncodingStrategy = .convertToSnakeCase

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    decoder.keyDecodingStrategy = .convertFromSnakeCase

    ContentConfiguration.global.use(encoder: encoder, for: .json)
    ContentConfiguration.global.use(decoder: decoder, for: .json)

    let dbPath = app.directory.workingDirectory + "data/cert_data.db"
    app.databases.use(.sqlite(.file(dbPath)), as: .sqlite)

    app.routes.defaultMaxBodySize = "10mb"

    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

    let corsConfiguration = CORSMiddleware.Configuration(
        allowedOrigin: .all,
        allowedMethods: [.GET, .POST, .PUT, .OPTIONS, .DELETE, .PATCH],
        allowedHeaders: [.accept, .authorization, .contentType, .origin, .xRequestedWith, .userAgent, .accessControlAllowOrigin]
    )
    app.middleware.use(CORSMiddleware(configuration: corsConfiguration), at: .beginning)

    app.migrations.add(CreateAuditLog())
    try app.autoMigrate().wait()

    try routes(app)

    // ── County message polling (Option 2: teams poll county, not county push to teams) ──
    // Teams poll the county server every 30s for pending messages (acks, alerts, etc.)
    // This way county never needs to reach team servers directly — teams pull messages.
    if let countyEndpoint = Environment.get("COUNTY_ENDPOINT"),
       let teamID = Environment.get("TEAM_ID") {
        print("🗺️  County endpoint: \(countyEndpoint) — startup push + polling every 30s for messages")
        Task {
            // Wait for server to fully start, then push initial state to county
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await dataStore.broadcastUpdate()
            print("📡 Initial county push sent")

            while true {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                await pollCountyMessages(countyEndpoint: countyEndpoint, teamID: teamID)
            }
        }
    }

    print("✅ CERT Field Board Backend configured successfully")
    print("📁 Team ID: \(Environment.get("TEAM_ID") ?? "not set")")
}

// Polls county server for messages addressed to this team, processes them, then confirms.
private func pollCountyMessages(countyEndpoint: String, teamID: String) async {
    guard let url = URL(string: "\(countyEndpoint)/api/messages?team=\(teamID)") else { return }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    decoder.keyDecodingStrategy = .convertFromSnakeCase

    // URLSession async overloads aren't available on Linux; use completion-handler form.
    let fetchedData: Data? = await withCheckedContinuation { continuation in
        URLSession.shared.dataTask(with: url) { data, _, _ in
            continuation.resume(returning: data)
        }.resume()
    }
    guard let data = fetchedData,
          let messages = try? decoder.decode([CountyMessage].self, from: data),
          !messages.isEmpty else { return }

    print("📬 Received \(messages.count) message(s) from county")

    for message in messages {
        await dataStore.applyCountyMessage(message)

        // Confirm we processed it so county can clear it
        if let confirmURL = URL(string: "\(countyEndpoint)/api/messages/\(message.id)/confirm") {
            var req = URLRequest(url: confirmURL)
            req.httpMethod = "POST"
            req.timeoutInterval = 5
            if let apiToken = Environment.get("COUNTY_API_TOKEN"), !apiToken.isEmpty {
                req.setValue(apiToken, forHTTPHeaderField: "X-CERT-API-Token")
            }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                URLSession.shared.dataTask(with: req) { _, _, _ in
                    continuation.resume()
                }.resume()
            }
        }
    }

    // Broadcast updated state (acks now visible on team dashboard)
    await dataStore.broadcastUpdate()
}
