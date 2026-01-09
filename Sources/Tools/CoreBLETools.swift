import Foundation
import CoreBluetooth

// MARK: - ble_scan

struct BleScanTool: Tool {
    let name = "ble_scan"
    let description = "Scan for nearby BLE devices. Optionally filter by name or service UUID."

    var inputSchema: [String: JSONValue] {
        [
            "type": .string("object"),
            "properties": .object([
                "duration": .object([
                    "type": .string("number"),
                    "description": .string("Scan duration in seconds (default: 5)")
                ]),
                "name_filter": .object([
                    "type": .string("string"),
                    "description": .string("Filter devices by name (case-insensitive partial match)")
                ]),
                "service_uuid": .object([
                    "type": .string("string"),
                    "description": .string("Filter by service UUID (e.g., '1826' for FTMS)")
                ])
            ])
        ]
    }

    func execute(arguments: [String: JSONValue], bleManager: BLEManager) async throws -> String {
        let duration = arguments["duration"]?.intValue.map { Double($0) } ?? 5.0
        let nameFilter = arguments["name_filter"]?.stringValue?.lowercased()
        let serviceUUID = arguments["service_uuid"]?.stringValue.map { CBUUID(string: $0) }

        let devices = await bleManager.scan(duration: duration, serviceUUIDs: serviceUUID.map { [$0] })

        var filtered = devices
        if let nameFilter = nameFilter {
            filtered = devices.filter { $0.name?.lowercased().contains(nameFilter) == true }
        }

        if filtered.isEmpty {
            return "No devices found"
        }

        let lines = filtered.map { device -> String in
            let name = device.name ?? "(unnamed)"
            let rssi = device.rssi
            let services = device.serviceUUIDs.map { $0.uuidString }.joined(separator: ", ")
            let serviceInfo = services.isEmpty ? "" : " [Services: \(services)]"
            return "• \(name) (\(device.identifier.uuidString)) RSSI: \(rssi) dBm\(serviceInfo)"
        }

        return "Found \(filtered.count) device(s):\n\(lines.joined(separator: "\n"))"
    }
}

// MARK: - ble_connect

struct BleConnectTool: Tool {
    let name = "ble_connect"
    let description = "Connect to a BLE device by name or UUID. Run ble_scan first to discover devices."

    var inputSchema: [String: JSONValue] {
        [
            "type": .string("object"),
            "properties": .object([
                "identifier": .object([
                    "type": .string("string"),
                    "description": .string("Device name (partial match) or UUID")
                ])
            ]),
            "required": .array([.string("identifier")])
        ]
    }

    func execute(arguments: [String: JSONValue], bleManager: BLEManager) async throws -> String {
        guard let identifier = arguments["identifier"]?.stringValue else {
            throw ToolError("Missing identifier parameter")
        }

        // Try as UUID first
        if let uuid = UUID(uuidString: identifier) {
            try await bleManager.connect(identifier: uuid)
        } else {
            // Try as name
            try await bleManager.connect(name: identifier)
        }

        let info = await bleManager.getDeviceInfo()
        let deviceName = info?["name"] as? String ?? "Unknown"
        let services = info?["services"] as? [String] ?? []

        return "Connected to \(deviceName)\nServices discovered: \(services.count)\n\(services.joined(separator: ", "))"
    }
}

// MARK: - ble_disconnect

struct BleDisconnectTool: Tool {
    let name = "ble_disconnect"
    let description = "Disconnect from the currently connected BLE device."

    var inputSchema: [String: JSONValue] {
        [
            "type": .string("object"),
            "properties": .object([:])
        ]
    }

    func execute(arguments: [String: JSONValue], bleManager: BLEManager) async throws -> String {
        let info = await bleManager.getDeviceInfo()
        let deviceName = info?["name"] as? String ?? "Unknown"

        await bleManager.disconnect()

        return "Disconnected from \(deviceName)"
    }
}

// MARK: - ble_status

struct BleStatusTool: Tool {
    let name = "ble_status"
    let description = "Show current BLE connection state, device info, and signal strength."

    var inputSchema: [String: JSONValue] {
        [
            "type": .string("object"),
            "properties": .object([:])
        ]
    }

    func execute(arguments: [String: JSONValue], bleManager: BLEManager) async throws -> String {
        let state = await bleManager.connectionState
        let btState = await bleManager.state

        var lines: [String] = []

        // Bluetooth state
        let btStateStr: String
        switch btState {
        case .poweredOn: btStateStr = "Powered On"
        case .poweredOff: btStateStr = "Powered Off"
        case .resetting: btStateStr = "Resetting"
        case .unauthorized: btStateStr = "Unauthorized"
        case .unsupported: btStateStr = "Unsupported"
        case .unknown: btStateStr = "Unknown"
        @unknown default: btStateStr = "Unknown"
        }
        lines.append("Bluetooth: \(btStateStr)")

        // Connection state
        let connStateStr: String
        switch state {
        case .disconnected: connStateStr = "Disconnected"
        case .connecting: connStateStr = "Connecting..."
        case .connected: connStateStr = "Connected"
        case .disconnecting: connStateStr = "Disconnecting..."
        }
        lines.append("Connection: \(connStateStr)")

        if state == .connected {
            if let info = await bleManager.getDeviceInfo() {
                lines.append("Device: \(info["name"] as? String ?? "Unknown")")
                lines.append("UUID: \(info["identifier"] as? String ?? "Unknown")")

                if let rssi = await bleManager.getRSSI() {
                    lines.append("RSSI: \(rssi) dBm")
                }

                let services = info["services"] as? [String] ?? []
                lines.append("Services: \(services.count)")
                for svc in services {
                    lines.append("  • \(svc)")
                }

                let chars = info["characteristics"] as? [String] ?? []
                lines.append("Characteristics: \(chars.count)")
            }
        }

        return lines.joined(separator: "\n")
    }
}
