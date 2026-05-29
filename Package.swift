// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HeyClaude",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HeyClaudeKit", targets: ["HeyClaudeKit"]),
        .executable(name: "heyclaude-spike", targets: ["heyclaude-spike"]),
    ],
    targets: [
        // Binary target for sherpa-onnx is added in Task 2.
        .target(
            name: "HeyClaudeKit",
            path: "Sources/HeyClaudeKit"
        ),
        .executableTarget(
            name: "heyclaude-spike",
            dependencies: ["HeyClaudeKit"],
            path: "Sources/heyclaude-spike"
        ),
        .testTarget(
            name: "HeyClaudeKitTests",
            dependencies: ["HeyClaudeKit"],
            path: "Tests/HeyClaudeKitTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
