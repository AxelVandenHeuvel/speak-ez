// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "speak-ez",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.15.5")
    ],
    targets: [
        // Pure logic: refinement rules, vocabulary correction, state machine.
        // No AppKit, no ML dependencies, fully unit-testable in CI.
        .target(
            name: "SpeakEzKit"
        ),
        // The menu-bar app.
        .executableTarget(
            name: "SpeakEz",
            dependencies: [
                "SpeakEzKit",
                .product(name: "FluidAudio", package: "FluidAudio"),
            ]
        ),
        .testTarget(
            name: "SpeakEzKitTests",
            dependencies: ["SpeakEzKit"]
        ),
    ]
)
