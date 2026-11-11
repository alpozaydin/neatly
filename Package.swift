// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "filed",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "NamerCore", targets: ["NamerCore"]),
        .executable(name: "filed", targets: ["filed"]),
    ],
    targets: [
        .target(name: "NamerCore"),
        .executableTarget(name: "filed", dependencies: ["NamerCore"]),
        .executableTarget(name: "filed-eval", dependencies: ["NamerCore"]),
        // Plain executable instead of a test target: swift-testing/XCTest need full Xcode.
        .executableTarget(name: "checks", dependencies: ["NamerCore"], path: "Tests/NamerCoreTests"),
    ]
)
