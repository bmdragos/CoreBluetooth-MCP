import Foundation
import CoreBluetooth
import MCPServer

// MARK: - ftms_discover

struct FtmsDiscoverTool: Tool {
    typealias Context = BLEManager

    let name = "ftms_discover"
    let description = "Scan specifically for FTMS (Fitness Machine Service) devices with service UUID 0x1826."

    var inputSchema: JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([
                "duration": .object([
                    "type": .string("number"),
                    "description": .string("Scan duration in seconds (default: 5)")
                ])
            ])
        ])
    }

    func execute(arguments: [String: JSONValue], context: BLEManager) async throws -> String {
        let duration = arguments["duration"]?.intValue.map { Double($0) } ?? 5.0

        let devices = await context.scan(duration: duration, serviceUUIDs: [FTMS.serviceUUID])

        if devices.isEmpty {
            return "No FTMS devices found. Make sure your fitness equipment is powered on and in pairing mode."
        }

        let lines = devices.map { device -> String in
            let name = device.name ?? "(unnamed)"
            return "• \(name)\n  UUID: \(device.identifier.uuidString)\n  RSSI: \(device.rssi) dBm"
        }

        return "Found \(devices.count) FTMS device(s):\n\n\(lines.joined(separator: "\n\n"))"
    }
}

// MARK: - ftms_info

struct FtmsInfoTool: Tool {
    typealias Context = BLEManager

    let name = "ftms_info"
    let description = "Read FTMS Feature characteristic to show supported features (power control, cadence, etc.)."

    var inputSchema: JSONValue {
        Schema.empty
    }

    func execute(arguments: [String: JSONValue], context: BLEManager) async throws -> String {
        let state = await context.connectionState
        guard state == .connected else {
            throw ToolError("Not connected. Use ble_connect first.")
        }

        // Read Feature characteristic
        let data = try await context.read(characteristicUUID: FTMS.fitnessMachineFeature)

        guard let features = FTMSFeatures.parse(from: data) else {
            return "Failed to parse FTMS features. Raw data: \(data.hexString)"
        }

        var lines: [String] = []
        lines.append("FTMS Device Features")
        lines.append("====================")
        lines.append("")
        lines.append("Supported Data Fields:")
        for feature in features.supportedFeatures {
            lines.append("  ✓ \(feature)")
        }

        lines.append("")
        lines.append("Supported Target Settings:")
        for setting in features.supportedTargetSettings {
            lines.append("  ✓ \(setting)")
        }

        // Try to read power range if available
        do {
            let powerRangeData = try await context.read(characteristicUUID: FTMS.supportedPowerRange)
            if powerRangeData.count >= 6 {
                let minPower = Int16(bitPattern: UInt16(powerRangeData[0]) | (UInt16(powerRangeData[1]) << 8))
                let maxPower = Int16(bitPattern: UInt16(powerRangeData[2]) | (UInt16(powerRangeData[3]) << 8))
                let increment = UInt16(powerRangeData[4]) | (UInt16(powerRangeData[5]) << 8)
                lines.append("")
                lines.append("Power Range: \(minPower)W - \(maxPower)W (increment: \(increment)W)")
            }
        } catch {
            // Power range not available, that's fine
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - Helper Extension

extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
