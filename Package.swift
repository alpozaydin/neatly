// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "namer",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "NamerCore", targets: ["NamerCore"]),
        .executable(name: "namer", targets: ["namer"]),
    ],
    targets: [
        .target(name: "NamerCore"),
        .executableTarget(name: "namer", dependencies: ["NamerCore"]),
        // Plain executable instead of a test target: swift-testing/XCTest need full Xcode.
        .executableTarget(name: "checks", dependencies: ["NamerCore"], path: "Tests/NamerCoreTests"),
    ]
)
