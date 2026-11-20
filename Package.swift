// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "Processes",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "Processes",
            targets: ["Processes"]
        ),
        .library(name: "TestFlowsProcesses", targets: ["TestFlowsProcesses"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-system.git",
            from: "1.5.0"
        ),
        .package(
            url: "https://github.com/swiftlang/swift-subprocess.git",
            from: "1.0.0"
        ),
        .package(url: "https://github.com/leviouwendijk/TestFlows.git", branch: "master"),
    ],
    targets: [
        .target(
            name: "Processes",
            dependencies: [
                .product(
                    name: "SystemPackage",
                    package: "swift-system"
                ),
                .product(
                    name: "Subprocess",
                    package: "swift-subprocess"
                ),
            ]
        ),
        .target(
            name: "TestFlowsProcesses",
            dependencies: [
                "Processes",
                .product(name: "TestFlows", package: "TestFlows"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
