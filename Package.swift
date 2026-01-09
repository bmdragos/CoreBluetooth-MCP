// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CoreBluetooth-MCP",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "corebluetooth-mcp", targets: ["CoreBluetooth-MCP"])
    ],
    targets: [
        .executableTarget(
            name: "CoreBluetooth-MCP",
            path: "Sources"
        )
    ]
)
