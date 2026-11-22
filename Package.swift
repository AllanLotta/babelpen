// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Revisor",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Revisor", targets: ["Revisor"]),
    ],
    targets: [
        // Pure logic (diff, prompt, config, strings). No AppKit, fully unit-tested.
        .target(name: "RevisorCore", path: "Sources/RevisorCore"),
        // The menu bar app: Accessibility, AI engines, UI.
        .executableTarget(name: "Revisor", dependencies: ["RevisorCore"], path: "Sources/Revisor"),
        .testTarget(name: "RevisorCoreTests", dependencies: ["RevisorCore"], path: "Tests/RevisorCoreTests"),
    ]
)
