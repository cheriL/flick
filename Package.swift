// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Flick",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Flick",
            path: "Sources/Flick"
        ),
        .testTarget(
            name: "FlickTests",
            dependencies: ["Flick"],
            path: "Tests/FlickTests"
        ),
    ]
)
