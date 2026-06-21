// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ClaudeMcpSwitch",
    platforms: [
        .macOS("14.0")
    ],
    products: [
        .executable(name: "ClaudeMcpSwitch", targets: ["ClaudeMcpSwitch"])
    ],
    targets: [
        .executableTarget(
            name: "ClaudeMcpSwitch",
            path: "Sources/ClaudeMcpSwitch",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "ClaudeMcpSwitchTests",
            dependencies: ["ClaudeMcpSwitch"],
            path: "ClaudeMcpSwitchTests"
        )
    ]
)
