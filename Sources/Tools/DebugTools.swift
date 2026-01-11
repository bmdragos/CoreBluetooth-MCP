import Foundation
import CoreBluetooth
import MCPServer

// MARK: - ftms_raw_read

struct FtmsRawReadTool: Tool {
    typealias Context = BLEManager

    let name = "ftms_raw_read"
    let description = "Read any characteristic as raw hex bytes. Use for debugging or custom characteristics."

    var inputSchema: JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([
                "uuid": .object([
                    "type": .string("string"),
                    "description": .string("Characteristic UUID (e.g., '2AD2' or full UUID)")
                ])
            ]),
            "required": .array([.string("uuid")])
        ])
    }

    func execute(arguments: [String: JSONValue], context: BLEManager) async throws -> String {
        let state = await context.connectionState
        guard state == .connected else {
            throw ToolError("Not connected. Use ble_connect first.")
        }

        guard let uuidString = arguments["uuid"]?.stringValue else {
            throw ToolError("Missing 'uuid' parameter")
        }

        let uuid = CBUUID(string: uuidString)
        let data = try await context.read(characteristicUUID: uuid)

        var lines: [String] = []
        lines.append("UUID: \(uuid.uuidString)")
        lines.append("Length: \(data.count) bytes")
        lines.append("Hex: \(data.hexString)")

        // Also show as ASCII if printable
        if let ascii = String(data: data, encoding: .utf8), ascii.allSatisfy({ $0.isASCII && !$0.isNewline }) {
            lines.append("ASCII: \(ascii)")
        }

        // Show individual bytes
        let byteBreakdown = data.enumerated().map { i, byte in
            "  [\(i)]: 0x\(String(format: "%02X", byte)) (\(byte))"
        }
        if !byteBreakdown.isEmpty {
            lines.append("Bytes:")
            lines.append(contentsOf: byteBreakdown)
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - ftms_raw_write

struct FtmsRawWriteTool: Tool {
    typealias Context = BLEManager

    let name = "ftms_raw_write"
    let description = "Write raw hex bytes to any characteristic. Use for debugging or custom commands."

    var inputSchema: JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([
                "uuid": .object([
                    "type": .string("string"),
                    "description": .string("Characteristic UUID (e.g., '2AD9')")
                ]),
                "hex": .object([
                    "type": .string("string"),
                    "description": .string("Hex bytes to write, space-separated (e.g., '05 64 00')")
                ]),
                "no_response": .object([
                    "type": .string("boolean"),
                    "description": .string("Write without waiting for response (default: false)")
                ])
            ]),
            "required": .array([.string("uuid"), .string("hex")])
        ])
    }

    func execute(arguments: [String: JSONValue], context: BLEManager) async throws -> String {
        let state = await context.connectionState
        guard state == .connected else {
            throw ToolError("Not connected. Use ble_connect first.")
        }

        guard let uuidString = arguments["uuid"]?.stringValue else {
            throw ToolError("Missing 'uuid' parameter")
        }

        guard let hexString = arguments["hex"]?.stringValue else {
            throw ToolError("Missing 'hex' parameter")
        }

        let noResponse = arguments["no_response"]?.stringValue == "true"

        // Parse hex string
        let hexParts = hexString.split(separator: " ").compactMap { part -> UInt8? in
            let hex = part.hasPrefix("0x") ? String(part.dropFirst(2)) : String(part)
            return UInt8(hex, radix: 16)
        }

        guard !hexParts.isEmpty else {
            throw ToolError("Invalid hex string. Use format like '05 64 00' or '0x05 0x64 0x00'")
        }

        let data = Data(hexParts)
        let uuid = CBUUID(string: uuidString)

        try await context.write(characteristicUUID: uuid, data: data, withResponse: !noResponse)

        return "Wrote \(data.count) bytes to \(uuid.uuidString): \(data.hexString)"
    }
}

// MARK: - ftms_log_start

struct FtmsLogStartTool: Tool {
    typealias Context = BLEManager

    let name = "ftms_log_start"
    let description = "Start logging all notifications to a CSV file."

    var inputSchema: JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([
                "file": .object([
                    "type": .string("string"),
                    "description": .string("Output file path (default: ~/ftms_log_<timestamp>.csv)")
                ])
            ])
        ])
    }

    func execute(arguments: [String: JSONValue], context: BLEManager) async throws -> String {
        let defaultPath = NSHomeDirectory() + "/ftms_log_\(Int(Date().timeIntervalSince1970)).csv"
        let filePath = arguments["file"]?.stringValue ?? defaultPath

        try await context.startLogging(filePath: filePath)

        return "Logging started to: \(filePath)\nUse ftms_log_stop to stop and finalize."
    }
}

// MARK: - ftms_log_stop

struct FtmsLogStopTool: Tool {
    typealias Context = BLEManager

    let name = "ftms_log_stop"
    let description = "Stop logging notifications and finalize the log file."

    var inputSchema: JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([:])
        ])
    }

    func execute(arguments: [String: JSONValue], context: BLEManager) async throws -> String {
        guard let path = await context.stopLogging() else {
            return "Logging was not active"
        }

        return "Logging stopped. File saved to: \(path)"
    }
}
