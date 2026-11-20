// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "ProcessesTests",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "TestFlowsProcesses",
            targets: ["TestFlowsProcesses"]
        ),
        .executable(
            name: "ptest",
            targets: ["ProcessesTestFlows"]
        ),
    ],
    dependencies: [

        .package(
            url: "https://github.com/leviouwendijk/TestFlows.git",
            branch: "master"
        ),
        .package(path: ".."),
    ],
    targets: [
        .target(
            name: "TestFlowsProcesses",
            dependencies: [
                .product(name: "Processes", package: "Processes"),
                .product(
                    name: "TestFlows",
                    package: "TestFlows"
                ),
            ]
        ),
        .executableTarget(
            name: "ProcessesTestFlows",
            dependencies: [
                .product(name: "Processes", package: "Processes"),
                "TestFlowsProcesses",
                .product(
                    name: "TestFlows",
                    package: "TestFlows"
                ),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
