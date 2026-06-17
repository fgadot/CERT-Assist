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

    if let pin = Environment.get("COUNTY_PIN"), !pin.isEmpty {
        app.middleware.use(PINAuthMiddleware(pin: pin))
        print("🔐 County PIN authentication enabled")
    }

    try routes(app)

    print("✅ CERT County EOC Backend configured successfully")
    print("🗺️  County dashboard: /county")
}
