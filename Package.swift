// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "look-mum-no-hands",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .library(name: "LMNHCore", targets: ["LMNHCore"]),
        .executable(name: "lmnh-mcp", targets: ["LMNHMCP"]),
        .executable(name: "lmnh-mcp-http", targets: ["LMNHHTTPMCP"]),
        .executable(name: "lmnh-control", targets: ["LMNHControlApp"])
    ],
    targets: [
        .target(
            name: "LMNHCore",
            path: "Sources/LMNHCore",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "LMNHMCP",
            dependencies: ["LMNHCore"],
            path: "Sources/LMNHMCP"
        ),
        .executableTarget(
            name: "LMNHHTTPMCP",
            dependencies: ["LMNHCore"],
            path: "Sources/LMNHHTTPMCP"
        ),
        .executableTarget(
            name: "LMNHControlApp",
            dependencies: ["LMNHCore"],
            path: "Sources/LMNHControlApp",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "LMNHCoreTests",
            dependencies: ["LMNHCore"],
            path: "Tests/LMNHCoreTests"
        )
    ]
)
