// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CERTCountyBackend",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.89.0"),
    ],
    targets: [
        .executableTarget(
            name: "Run",
            dependencies: [.target(name: "App")],
            path: "Sources/Run"
        ),
        .target(
            name: "App",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
            ],
            path: "Sources/App"
        ),
    ]
)
