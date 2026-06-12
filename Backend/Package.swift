// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CERTFieldBoardBackend",
    platforms: [
       .macOS(.v13)
    ],
    dependencies: [
        // Vapor framework
        .package(url: "https://github.com/vapor/vapor.git", from: "4.89.0"),
    ],
    targets: [
        .executableTarget(
            name: "Run",
            dependencies: [
                .target(name: "App")
            ]
        ),
        .target(
            name: "App",
            dependencies: [
                .product(name: "Vapor", package: "vapor")
            ]
        ),
    ]
)
