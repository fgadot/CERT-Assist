//
//  configure.swift
//  CERT Field Board Backend
//

import Vapor

public func configure(_ app: Application) throws {
    
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
}
