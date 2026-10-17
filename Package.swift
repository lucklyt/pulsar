// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Pulsar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Pulsar", targets: ["Pulsar"]),
        .library(name: "PulsarCore", targets: ["PulsarCore"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "PulsarCore",
            path: "Sources/PulsarCore"
        ),
        .executableTarget(
            name: "Pulsar",
            dependencies: ["PulsarCore"],
            path: "Sources/Pulsar"
        ),
        .testTarget(
            name: "PulsarTests",
            dependencies: ["PulsarCore"],
            path: "Tests/PulsarTests"
        )
    ]
)
