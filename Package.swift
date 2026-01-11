// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CoreBluetooth-MCP",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "corebluetooth-mcp", targets: ["CoreBluetooth-MCP"])
    ],
    dependencies: [
        .package(path: "../swift-mcp-server"),
    ],
    targets: [
        .executableTarget(
            name: "CoreBluetooth-MCP",
            dependencies: [
                .product(name: "MCPServer", package: "swift-mcp-server"),
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "CoreBluetoothMCPTests",
            dependencies: ["CoreBluetooth-MCP"],
            path: "Tests"
        )
    ]
)
