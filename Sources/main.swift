import Foundation
import CoreBluetooth
import MCPServer

// Entry point - run the MCP server
let context = BLEManager()
let server = MCPServer(
    info: ServerInfo(name: "ble-mcp", version: "1.0.0"),
    context: context
)

// We need a RunLoop for CoreBluetooth callbacks
// Run the server in a Task and keep the RunLoop alive
Task {
    // Start BLE manager
    await context.start()

    // Register all tools
    await registerTools(server: server)

    // Run the server
    await server.run()
    exit(0)
}

RunLoop.main.run()

// MARK: - Tool Registration

func registerTools(server: MCPServer<BLEManager>) async {
    // Core BLE tools
    await server.register(BleScanTool())
    await server.register(BleConnectTool())
    await server.register(BleDisconnectTool())
    await server.register(BleStatusTool())
    await server.register(BleServicesTool())
    await server.register(BleCharacteristicsTool())
    await server.register(BleDescriptorsTool())
    await server.register(BleReadTool())
    await server.register(BleWriteTool())
    await server.register(BleSubscribeTool())
    await server.register(BleUnsubscribeTool())
    await server.register(BleBatteryTool())
    await server.register(BleDeviceInfoTool())

    // FTMS Discovery
    await server.register(FtmsDiscoverTool())
    await server.register(FtmsInfoTool())

    // FTMS Data
    await server.register(FtmsReadTool())
    await server.register(FtmsSubscribeTool())
    await server.register(FtmsUnsubscribeTool())

    // FTMS Control
    await server.register(FtmsRequestControlTool())
    await server.register(FtmsSetPowerTool())
    await server.register(FtmsResetTool())
    await server.register(FtmsStartTool())
    await server.register(FtmsStopTool())

    // Debugging
    await server.register(FtmsRawReadTool())
    await server.register(FtmsRawWriteTool())
    await server.register(FtmsLogStartTool())
    await server.register(FtmsLogStopTool())

    // Nice to have
    await server.register(FtmsMonitorTool())
    await server.register(FtmsTestSequenceTool())

    // Heart Rate Service
    await server.register(HrsDiscoverTool())
    await server.register(HrsReadTool())
    await server.register(HrsSubscribeTool())
    await server.register(HrsUnsubscribeTool())
    await server.register(HrsLocationTool())
}
