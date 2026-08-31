// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Flick",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "Flick",
            path: "Sources/Flick",
            // Tools-version 6.2+ defaults to Swift 6 language mode, which
            // enforces strict concurrency. The existing codebase isn't
            // audited for that yet — force Swift 5 mode for now so we can
            // adopt `.macOS(.v26)` (requires PackageDescription 6.2) without
            // rewriting every `@MainActor` boundary. Migrating to Swift 6
            // mode is a separate, larger effort.
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "FlickTests",
            dependencies: [
                "Flick",
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests/FlickTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
    ]
)
