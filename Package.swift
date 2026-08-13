// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Flick",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "Flick",
            path: "Sources/Flick"
        ),
        .testTarget(
            name: "FlickTests",
            dependencies: [
                "Flick",
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests/FlickTests"
        ),
    ]
)
