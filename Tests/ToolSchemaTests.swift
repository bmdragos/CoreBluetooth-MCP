import XCTest
@testable import CoreBluetooth_MCP
import MCPServer

final class ToolSchemaTests: XCTestCase {

    // MARK: - Core BLE Tools

    func testBleScanToolSchema() {
        let tool = BleScanTool()
        XCTAssertEqual(tool.name, "ble_scan")
        XCTAssertTrue(tool.description.contains("Scan"))

        guard case .object(let schema) = tool.inputSchema,
              let properties = schema["properties"],
              case .object(let props) = properties else {
            XCTFail("Expected object schema with properties")
            return
        }

        XCTAssertNotNil(props["duration"])
        XCTAssertNotNil(props["name_filter"])
        XCTAssertNotNil(props["service_uuid"])
    }

    func testBleConnectToolSchema() {
        let tool = BleConnectTool()
        XCTAssertEqual(tool.name, "ble_connect")

        guard case .object(let schema) = tool.inputSchema,
              let required = schema["required"],
              case .array(let reqArray) = required else {
            XCTFail("Expected required array")
            return
        }

        let reqStrings = reqArray.compactMap { $0.stringValue }
        XCTAssertTrue(reqStrings.contains("identifier"))
    }

    func testBleDisconnectToolSchema() {
        let tool = BleDisconnectTool()
        XCTAssertEqual(tool.name, "ble_disconnect")
        // Should have empty schema
        guard case .object(let schema) = tool.inputSchema else {
            XCTFail("Expected object schema")
            return
        }
        // Empty schema has no required fields
        XCTAssertNil(schema["required"])
    }

    func testBleStatusToolSchema() {
        let tool = BleStatusTool()
        XCTAssertEqual(tool.name, "ble_status")
    }

    func testBleServicesToolSchema() {
        let tool = BleServicesTool()
        XCTAssertEqual(tool.name, "ble_services")
    }

    func testBleCharacteristicsToolSchema() {
        let tool = BleCharacteristicsTool()
        XCTAssertEqual(tool.name, "ble_characteristics")
    }

    func testBleDescriptorsToolSchema() {
        let tool = BleDescriptorsTool()
        XCTAssertEqual(tool.name, "ble_descriptors")
    }

    func testBleReadToolSchema() {
        let tool = BleReadTool()
        XCTAssertEqual(tool.name, "ble_read")

        guard case .object(let schema) = tool.inputSchema,
              let required = schema["required"],
              case .array(let reqArray) = required else {
            XCTFail("Expected required array")
            return
        }

        let reqStrings = reqArray.compactMap { $0.stringValue }
        XCTAssertTrue(reqStrings.contains("uuid"))
    }

    func testBleWriteToolSchema() {
        let tool = BleWriteTool()
        XCTAssertEqual(tool.name, "ble_write")

        guard case .object(let schema) = tool.inputSchema,
              let required = schema["required"],
              case .array(let reqArray) = required else {
            XCTFail("Expected required array")
            return
        }

        let reqStrings = reqArray.compactMap { $0.stringValue }
        XCTAssertTrue(reqStrings.contains("uuid"))
    }

    func testBleSubscribeToolSchema() {
        let tool = BleSubscribeTool()
        XCTAssertEqual(tool.name, "ble_subscribe")
    }

    func testBleUnsubscribeToolSchema() {
        let tool = BleUnsubscribeTool()
        XCTAssertEqual(tool.name, "ble_unsubscribe")
    }

    func testBleBatteryToolSchema() {
        let tool = BleBatteryTool()
        XCTAssertEqual(tool.name, "ble_battery")
    }

    func testBleDeviceInfoToolSchema() {
        let tool = BleDeviceInfoTool()
        XCTAssertEqual(tool.name, "ble_device_info")
    }

    // MARK: - FTMS Discovery Tools

    func testFtmsDiscoverToolSchema() {
        let tool = FtmsDiscoverTool()
        XCTAssertEqual(tool.name, "ftms_discover")
        XCTAssertTrue(tool.description.contains("FTMS"))
    }

    func testFtmsInfoToolSchema() {
        let tool = FtmsInfoTool()
        XCTAssertEqual(tool.name, "ftms_info")
    }

    // MARK: - FTMS Data Tools

    func testFtmsReadToolSchema() {
        let tool = FtmsReadTool()
        XCTAssertEqual(tool.name, "ftms_read")

        guard case .object(let schema) = tool.inputSchema,
              let properties = schema["properties"],
              case .object(let props) = properties else {
            XCTFail("Expected object schema")
            return
        }

        XCTAssertNotNil(props["format"])
    }

    func testFtmsSubscribeToolSchema() {
        let tool = FtmsSubscribeTool()
        XCTAssertEqual(tool.name, "ftms_subscribe")
    }

    func testFtmsUnsubscribeToolSchema() {
        let tool = FtmsUnsubscribeTool()
        XCTAssertEqual(tool.name, "ftms_unsubscribe")
    }

    // MARK: - FTMS Control Tools

    func testFtmsRequestControlToolSchema() {
        let tool = FtmsRequestControlTool()
        XCTAssertEqual(tool.name, "ftms_request_control")
    }

    func testFtmsSetPowerToolSchema() {
        let tool = FtmsSetPowerTool()
        XCTAssertEqual(tool.name, "ftms_set_power")

        guard case .object(let schema) = tool.inputSchema,
              let required = schema["required"],
              case .array(let reqArray) = required else {
            XCTFail("Expected required array")
            return
        }

        let reqStrings = reqArray.compactMap { $0.stringValue }
        XCTAssertTrue(reqStrings.contains("watts"))
    }

    func testFtmsResetToolSchema() {
        let tool = FtmsResetTool()
        XCTAssertEqual(tool.name, "ftms_reset")
    }

    func testFtmsStartToolSchema() {
        let tool = FtmsStartTool()
        XCTAssertEqual(tool.name, "ftms_start")
    }

    func testFtmsStopToolSchema() {
        let tool = FtmsStopTool()
        XCTAssertEqual(tool.name, "ftms_stop")
    }

    // MARK: - Debug Tools

    func testFtmsRawReadToolSchema() {
        let tool = FtmsRawReadTool()
        XCTAssertEqual(tool.name, "ftms_raw_read")
    }

    func testFtmsRawWriteToolSchema() {
        let tool = FtmsRawWriteTool()
        XCTAssertEqual(tool.name, "ftms_raw_write")
    }

    func testFtmsLogStartToolSchema() {
        let tool = FtmsLogStartTool()
        XCTAssertEqual(tool.name, "ftms_log_start")
    }

    func testFtmsLogStopToolSchema() {
        let tool = FtmsLogStopTool()
        XCTAssertEqual(tool.name, "ftms_log_stop")
    }

    // MARK: - Advanced Tools

    func testFtmsMonitorToolSchema() {
        let tool = FtmsMonitorTool()
        XCTAssertEqual(tool.name, "ftms_monitor")
    }

    func testFtmsTestSequenceToolSchema() {
        let tool = FtmsTestSequenceTool()
        XCTAssertEqual(tool.name, "ftms_test_sequence")
    }

    // MARK: - HRS Tools

    func testHrsDiscoverToolSchema() {
        let tool = HrsDiscoverTool()
        XCTAssertEqual(tool.name, "hrs_discover")
        XCTAssertTrue(tool.description.contains("Heart Rate"))
    }

    func testHrsReadToolSchema() {
        let tool = HrsReadTool()
        XCTAssertEqual(tool.name, "hrs_read")
    }

    func testHrsSubscribeToolSchema() {
        let tool = HrsSubscribeTool()
        XCTAssertEqual(tool.name, "hrs_subscribe")
    }

    func testHrsUnsubscribeToolSchema() {
        let tool = HrsUnsubscribeTool()
        XCTAssertEqual(tool.name, "hrs_unsubscribe")
    }

    func testHrsLocationToolSchema() {
        let tool = HrsLocationTool()
        XCTAssertEqual(tool.name, "hrs_location")
    }
}

// MARK: - BLE State Tests

final class BLEStateTests: XCTestCase {

    func testBLEConnectionState_AllCases() {
        // Verify all states exist
        let disconnected = BLEConnectionState.disconnected
        let connecting = BLEConnectionState.connecting
        let connected = BLEConnectionState.connected
        let disconnecting = BLEConnectionState.disconnecting

        XCTAssertNotEqual(String(describing: disconnected), String(describing: connected))
        XCTAssertNotEqual(String(describing: connecting), String(describing: disconnecting))
    }

    func testBLEConnectionState_Sendable() {
        // BLEConnectionState should be Sendable
        let state: BLEConnectionState = .connected
        Task {
            let _ = state  // Can be sent across actor boundaries
        }
    }
}

// MARK: - Tool Count Validation

final class ToolRegistrationTests: XCTestCase {

    func testAllToolsHaveUniqueNames() {
        let tools: [any Tool<BLEManager>] = [
            BleScanTool(),
            BleConnectTool(),
            BleDisconnectTool(),
            BleStatusTool(),
            BleServicesTool(),
            BleCharacteristicsTool(),
            BleDescriptorsTool(),
            BleReadTool(),
            BleWriteTool(),
            BleSubscribeTool(),
            BleUnsubscribeTool(),
            BleBatteryTool(),
            BleDeviceInfoTool(),
            FtmsDiscoverTool(),
            FtmsInfoTool(),
            FtmsReadTool(),
            FtmsSubscribeTool(),
            FtmsUnsubscribeTool(),
            FtmsRequestControlTool(),
            FtmsSetPowerTool(),
            FtmsResetTool(),
            FtmsStartTool(),
            FtmsStopTool(),
            FtmsRawReadTool(),
            FtmsRawWriteTool(),
            FtmsLogStartTool(),
            FtmsLogStopTool(),
            FtmsMonitorTool(),
            FtmsTestSequenceTool(),
            HrsDiscoverTool(),
            HrsReadTool(),
            HrsSubscribeTool(),
            HrsUnsubscribeTool(),
            HrsLocationTool(),
        ]

        let names = tools.map { $0.name }
        let uniqueNames = Set(names)

        XCTAssertEqual(names.count, uniqueNames.count, "Duplicate tool names found")
        XCTAssertEqual(names.count, 34, "Expected 34 tools")
    }

    func testAllToolsHaveDescriptions() {
        let tools: [any Tool<BLEManager>] = [
            BleScanTool(),
            BleConnectTool(),
            BleDisconnectTool(),
            BleStatusTool(),
            FtmsDiscoverTool(),
            HrsDiscoverTool(),
        ]

        for tool in tools {
            XCTAssertFalse(tool.description.isEmpty, "\(tool.name) has empty description")
            XCTAssertGreaterThan(tool.description.count, 10, "\(tool.name) description too short")
        }
    }
}
