//
//  configure.swift
//  CERT County EOC Backend
//

import Vapor

public func configure(_ app: Application) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.keyEncodingStrategy = .convertToSnakeCase

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    decoder.keyDecodingStrategy = .convertFromSnakeCase

    ContentConfiguration.global.use(encoder: encoder, for: .json)
    ContentConfiguration.global.use(decoder: decoder, for: .json)

    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

    let corsConfiguration = CORSMiddleware.Configuration(
        allowedOrigin: .all,
        allowedMethods: [.GET, .POST, .PUT, .OPTIONS, .DELETE, .PATCH],
        allowedHeaders: [.accept, .authorization, .contentType, .origin, .xRequestedWith, .userAgent, .accessControlAllowOrigin]
    )
    app.middleware.use(CORSMiddleware(configuration: corsConfiguration), at: .beginning)

    let dashboardPin: String? = Environment.get("COUNTY_PIN").flatMap      { $0.isEmpty ? nil : $0 }
    let apiToken: String?     = Environment.get("COUNTY_API_TOKEN").flatMap { $0.isEmpty ? nil : $0 }
    if dashboardPin != nil || apiToken != nil {
        app.middleware.use(PINAuthMiddleware(dashboardPin: dashboardPin, apiToken: apiToken))
        print("🔐 County auth enabled — dashboard=\(dashboardPin != nil ? "passphrase set" : "open"), api=\(apiToken != nil ? "token set" : "open")")
    }

    try routes(app)

    print("✅ CERT County EOC Backend configured successfully")
    print("🗺️  County dashboard: /county")
}
