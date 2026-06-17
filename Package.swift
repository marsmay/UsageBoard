// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "UsageBoard",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "UsageBoard", targets: ["UsageBoardApp"]),
        .library(name: "UsageBoardCore", targets: ["UsageBoardCore"])
    ],
    targets: [
        .target(
            name: "UsageBoardCore"
        ),
        .executableTarget(
            name: "UsageBoardApp",
            dependencies: ["UsageBoardCore"]
        ),
        .testTarget(
            name: "UsageBoardTests",
            dependencies: ["UsageBoardCore"]
        ),
        .testTarget(
            name: "UsageBoardAppTests",
            dependencies: ["UsageBoardApp"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
