// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Babelpen",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Babelpen", targets: ["Babelpen"]),
    ],
    targets: [
        // Pure logic (diff, prompt, config, strings). No AppKit, fully unit-tested.
        .target(name: "BabelpenCore", path: "Sources/BabelpenCore"),
        // The menu bar app: Accessibility, AI engines, UI.
        .executableTarget(name: "Babelpen", dependencies: ["BabelpenCore"], path: "Sources/Babelpen"),
        .testTarget(name: "BabelpenCoreTests", dependencies: ["BabelpenCore"], path: "Tests/BabelpenCoreTests"),
    ]
)
