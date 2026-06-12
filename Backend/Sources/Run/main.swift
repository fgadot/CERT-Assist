//
//  main.swift
//  CERT Field Board Backend
//

import Vapor
import App

@main
struct Main {
    static func main() async throws {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)
        
        let app = Application(env)
        defer { app.shutdown() }
        
        try configure(app)
        try app.run()
    }
}
