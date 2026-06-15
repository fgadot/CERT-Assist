//
//  configure.swift
//  CERT Field Board Backend
//

import Vapor
import Fluent
import FluentSQLiteDriver

public func configure(_ app: Application) throws {
    
    // Configure JSON encoder/decoder for dates
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.keyEncodingStrategy = .convertToSnakeCase
    
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    
    ContentConfiguration.global.use(encoder: encoder, for: .json)
    ContentConfiguration.global.use(decoder: decoder, for: .json)
    
    // Configure SQLite database in /app/data directory (persisted via Docker volume)
    let dbPath = app.directory.workingDirectory + "data/cert_data.db"
    app.databases.use(.sqlite(.file(dbPath)), as: .sqlite)
    
    // Run migrations (none yet, but ready for future use)
    // app.migrations.add(...)
    // try app.autoMigrate().wait()
    
    // Configure maximum upload file size (for future photo uploads)
    app.routes.defaultMaxBodySize = "10mb"
    
    // Serve files from /Public directory
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
    
    // Configure CORS for iOS app
    let corsConfiguration = CORSMiddleware.Configuration(
        allowedOrigin: .all,
        allowedMethods: [.GET, .POST, .PUT, .OPTIONS, .DELETE, .PATCH],
        allowedHeaders: [.accept, .authorization, .contentType, .origin, .xRequestedWith, .userAgent, .accessControlAllowOrigin]
    )
    let cors = CORSMiddleware(configuration: corsConfiguration)
    app.middleware.use(cors, at: .beginning)
    
    // Register routes
    try routes(app)
    
    print("✅ CERT Field Board Backend configured successfully")
    print("📁 Database location: cert_data.db")
}

