// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "neatly",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "NeatlyCore", targets: ["NeatlyCore"]),
        .executable(name: "neatly", targets: ["neatly"]),
    ],
    targets: [
        .target(name: "NeatlyCore"),
        .executableTarget(name: "neatly", dependencies: ["NeatlyCore"]),
        .executableTarget(name: "neatly-eval", dependencies: ["NeatlyCore"]),
        // Plain executable instead of a test target: swift-testing/XCTest need full Xcode.
        .executableTarget(name: "checks", dependencies: ["NeatlyCore"], path: "Tests/NeatlyCoreTests"),
    ]
)
