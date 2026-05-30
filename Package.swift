// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HeyClaude",
    platforms: [.macOS("14.4")],   // NSHostingMenu (status-item menu) needs 14.4+
    products: [
        .library(name: "HeyClaudeKit", targets: ["HeyClaudeKit"]),
        .executable(name: "heyclaude", targets: ["heyclaude"]),
        // On-machine test harness: this CLT-only toolchain has no XCTest runner
        // (`xcrun --find xctest` fails), so the XCTest files in
        // Tests/HeyClaudeKitTests are retained for CI/Xcode while verification
        // here runs through this executable. See internal design notes.
        .executable(name: "heyclaude-selftest", targets: ["heyclaude-selftest"]),
        // SwiftUI menu-bar app (Phase 3A): the user-facing shell over HeyClaudeKit.
        .executable(name: "HeyClaudeApp", targets: ["HeyClaudeApp"]),
    ],
    targets: [
        // Prebuilt sherpa-onnx static xcframework (universal2 macOS).
        // Downloaded + module map injected by hand (gitignored); see
        // internal design notes for the reproducible setup.
        .binaryTarget(
            name: "CSherpaOnnx",
            path: "Sources/CSherpaOnnx/sherpa-onnx.xcframework"
        ),
        .target(
            name: "HeyClaudeKit",
            dependencies: ["CSherpaOnnx"],
            path: "Sources/HeyClaudeKit",
            linkerSettings: [
                // The static archive bundles onnxruntime + C++ code but not the
                // C++ runtime or system frameworks, so link them on the consumer.
                .linkedLibrary("c++"),
                .linkedFramework("Accelerate"),
                .linkedFramework("Foundation"),
            ]
        ),
        .executableTarget(
            name: "heyclaude",
            dependencies: ["HeyClaudeKit"],
            path: "Sources/heyclaude"
        ),
        .executableTarget(
            name: "heyclaude-selftest",
            dependencies: ["HeyClaudeKit"],
            path: "Sources/heyclaude-selftest"
        ),
        .executableTarget(
            name: "HeyClaudeApp",
            dependencies: ["HeyClaudeKit"],
            path: "Sources/HeyClaudeApp"
        ),
        .testTarget(
            name: "HeyClaudeKitTests",
            dependencies: ["HeyClaudeKit"],
            path: "Tests/HeyClaudeKitTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
