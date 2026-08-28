// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PRQueue",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "PRQueue",
            path: "Sources/PRQueue"
        ),
        .testTarget(
            name: "PRQueueTests",
            dependencies: ["PRQueue"],
            path: "Tests/PRQueueTests"
        )
    ]
)
