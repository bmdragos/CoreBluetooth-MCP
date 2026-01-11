import Foundation
import CoreBluetooth
import MCPServer

// MARK: - ftms_request_control

struct FtmsRequestControlTool: Tool {
    typealias Context = BLEManager

    let name = "ftms_request_control"
    let description = "Request control of the FTMS device. Required before sending any control commands (set_power, start, stop, etc.)."

    var inputSchema: JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([:])
        ])
    }

    func execute(arguments: [String: JSONValue], context: BLEManager) async throws -> String {
        let state = await context.connectionState
        guard state == .connected else {
            throw ToolError("Not connected. Use ble_connect first.")
        }

        // Request Control: opcode 0x00
        let data = Data([FTMS.OpCode.requestControl.rawValue])
        try await context.write(characteristicUUID: FTMS.fitnessMachineControlPoint, data: data)

        // Small delay to allow device to process
        try await Task.sleep(nanoseconds: 200_000_000)

        return "Control requested. You can now send commands."
    }
}

// MARK: - ftms_set_power

struct FtmsSetPowerTool: Tool {
    typealias Context = BLEManager

    let name = "ftms_set_power"
    let description = "Set target power in watts. Requires ftms_request_control first."

    var inputSchema: JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([
                "watts": .object([
                    "type": .string("integer"),
                    "description": .string("Target power in watts (e.g., 100, 150, 200)")
                ])
            ]),
            "required": .array([.string("watts")])
        ])
    }

    func execute(arguments: [String: JSONValue], context: BLEManager) async throws -> String {
        let state = await context.connectionState
        guard state == .connected else {
            throw ToolError("Not connected. Use ble_connect first.")
        }

        guard let watts = arguments["watts"]?.intValue else {
            throw ToolError("Missing 'watts' parameter")
        }

        // Set Target Power: opcode 0x05, followed by sint16 power
        let powerInt16 = Int16(clamping: watts)
        let lowByte = UInt8(truncatingIfNeeded: powerInt16)
        let highByte = UInt8(truncatingIfNeeded: powerInt16 >> 8)
        let data = Data([FTMS.OpCode.setTargetPower.rawValue, lowByte, highByte])

        try await context.write(characteristicUUID: FTMS.fitnessMachineControlPoint, data: data)

        return "Target power set to \(watts)W"
    }
}

// MARK: - ftms_reset

struct FtmsResetTool: Tool {
    typealias Context = BLEManager

    let name = "ftms_reset"
    let description = "Send reset command to the FTMS device."

    var inputSchema: JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([:])
        ])
    }

    func execute(arguments: [String: JSONValue], context: BLEManager) async throws -> String {
        let state = await context.connectionState
        guard state == .connected else {
            throw ToolError("Not connected. Use ble_connect first.")
        }

        let data = Data([FTMS.OpCode.reset.rawValue])
        try await context.write(characteristicUUID: FTMS.fitnessMachineControlPoint, data: data)

        return "Reset command sent"
    }
}

// MARK: - ftms_start

struct FtmsStartTool: Tool {
    typealias Context = BLEManager

    let name = "ftms_start"
    let description = "Start or resume the workout/training session."

    var inputSchema: JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([:])
        ])
    }

    func execute(arguments: [String: JSONValue], context: BLEManager) async throws -> String {
        let state = await context.connectionState
        guard state == .connected else {
            throw ToolError("Not connected. Use ble_connect first.")
        }

        let data = Data([FTMS.OpCode.startOrResume.rawValue])
        try await context.write(characteristicUUID: FTMS.fitnessMachineControlPoint, data: data)

        return "Start/resume command sent"
    }
}

// MARK: - ftms_stop

struct FtmsStopTool: Tool {
    typealias Context = BLEManager

    let name = "ftms_stop"
    let description = "Stop or pause the workout/training session."

    var inputSchema: JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([
                "pause": .object([
                    "type": .string("boolean"),
                    "description": .string("If true, pause instead of stop (default: false)")
                ])
            ])
        ])
    }

    func execute(arguments: [String: JSONValue], context: BLEManager) async throws -> String {
        let state = await context.connectionState
        guard state == .connected else {
            throw ToolError("Not connected. Use ble_connect first.")
        }

        // Stop or Pause: opcode 0x08, param: 0x01 = stop, 0x02 = pause
        let isPause = arguments["pause"]?.stringValue == "true"
        let param: UInt8 = isPause ? 0x02 : 0x01
        let data = Data([FTMS.OpCode.stopOrPause.rawValue, param])

        try await context.write(characteristicUUID: FTMS.fitnessMachineControlPoint, data: data)

        return isPause ? "Pause command sent" : "Stop command sent"
    }
}
