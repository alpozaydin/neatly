// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "neatly",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "NamerCore", targets: ["NamerCore"]),
        .executable(name: "neatly", targets: ["neatly"]),
    ],
    targets: [
        .target(name: "NamerCore"),
        .executableTarget(name: "neatly", dependencies: ["NamerCore"]),
        .executableTarget(name: "neatly-eval", dependencies: ["NamerCore"]),
        // Plain executable instead of a test target: swift-testing/XCTest need full Xcode.
        .executableTarget(name: "checks", dependencies: ["NamerCore"], path: "Tests/NamerCoreTests"),
    ]
)
