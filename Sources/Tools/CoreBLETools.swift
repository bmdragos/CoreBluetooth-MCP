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

// MARK: - ble_services

struct BleServicesTool: Tool {
    let name = "ble_services"
    let description = "List all services on the connected device with their UUIDs and characteristic count."

    var inputSchema: [String: JSONValue] {
        [
            "type": .string("object"),
            "properties": .object([:])
        ]
    }

    func execute(arguments: [String: JSONValue], bleManager: BLEManager) async throws -> String {
        let state = await bleManager.connectionState
        guard state == .connected else {
            throw ToolError("Not connected. Use ble_connect first.")
        }

        let services = await bleManager.getServices()

        if services.isEmpty {
            return "No services discovered"
        }

        var lines: [String] = []
        lines.append("Services (\(services.count)):")
        lines.append("")

        for service in services.sorted(by: { $0.uuid.uuidString < $1.uuid.uuidString }) {
            let name = knownServiceName(service.uuid) ?? "Unknown Service"
            lines.append("• \(service.uuid.uuidString)")
            lines.append("  Name: \(name)")
            lines.append("  Characteristics: \(service.characteristics.count)")
        }

        return lines.joined(separator: "\n")
    }

    // Official Bluetooth SIG Assigned Numbers
    // Source: https://github.com/NordicSemiconductor/bluetooth-numbers-database
    private func knownServiceName(_ uuid: CBUUID) -> String? {
        let known: [String: String] = [
            "1800": "Generic Access",
            "1801": "Generic Attribute",
            "180A": "Device Information",
            "180D": "Heart Rate",
            "180F": "Battery Service",
            "1816": "Cycling Speed and Cadence",
            "1818": "Cycling Power",
            "1826": "Fitness Machine"
        ]
        return known[uuid.uuidString]
    }
}

// MARK: - ble_characteristics

struct BleCharacteristicsTool: Tool {
    let name = "ble_characteristics"
    let description = "List characteristics for a service (or all services) with their properties (read/write/notify)."

    var inputSchema: [String: JSONValue] {
        [
            "type": .string("object"),
            "properties": .object([
                "service": .object([
                    "type": .string("string"),
                    "description": .string("Service UUID to inspect (e.g., '1826'). If omitted, lists all characteristics.")
                ])
            ])
        ]
    }

    func execute(arguments: [String: JSONValue], bleManager: BLEManager) async throws -> String {
        let state = await bleManager.connectionState
        guard state == .connected else {
            throw ToolError("Not connected. Use ble_connect first.")
        }

        if let serviceUUIDString = arguments["service"]?.stringValue {
            // List characteristics for specific service
            let serviceUUID = CBUUID(string: serviceUUIDString)
            guard let characteristics = await bleManager.getCharacteristics(forService: serviceUUID) else {
                throw ToolError("Service \(serviceUUIDString) not found")
            }

            var lines: [String] = []
            lines.append("Characteristics for service \(serviceUUIDString):")
            lines.append("")

            for char in characteristics.sorted(by: { $0.uuid.uuidString < $1.uuid.uuidString }) {
                let name = knownCharacteristicName(char.uuid) ?? "Unknown"
                let props = formatProperties(char.properties)
                lines.append("• \(char.uuid.uuidString)")
                lines.append("  Name: \(name)")
                lines.append("  Properties: \(props)")
            }

            return lines.joined(separator: "\n")
        } else {
            // List all characteristics grouped by service
            let allChars = await bleManager.getAllCharacteristics()

            if allChars.isEmpty {
                return "No characteristics discovered"
            }

            // Group by service
            var byService: [CBUUID: [(uuid: CBUUID, properties: CBCharacteristicProperties)]] = [:]
            for char in allChars {
                byService[char.serviceUUID, default: []].append((char.uuid, char.properties))
            }

            var lines: [String] = []
            lines.append("All Characteristics (\(allChars.count) total):")
            lines.append("")

            for serviceUUID in byService.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
                let serviceName = knownServiceName(serviceUUID) ?? "Unknown Service"
                lines.append("━━━ \(serviceUUID.uuidString) (\(serviceName)) ━━━")

                for char in byService[serviceUUID]!.sorted(by: { $0.uuid.uuidString < $1.uuid.uuidString }) {
                    let name = knownCharacteristicName(char.uuid) ?? "Unknown"
                    let props = formatProperties(char.properties)
                    lines.append("  • \(char.uuid.uuidString) [\(props)]")
                    lines.append("    \(name)")
                }
                lines.append("")
            }

            return lines.joined(separator: "\n")
        }
    }

    private func formatProperties(_ props: CBCharacteristicProperties) -> String {
        var parts: [String] = []
        if props.contains(.read) { parts.append("R") }
        if props.contains(.write) { parts.append("W") }
        if props.contains(.writeWithoutResponse) { parts.append("WNR") }
        if props.contains(.notify) { parts.append("N") }
        if props.contains(.indicate) { parts.append("I") }
        return parts.isEmpty ? "none" : parts.joined(separator: ", ")
    }

    // Official Bluetooth SIG Assigned Numbers
    // Source: https://github.com/NordicSemiconductor/bluetooth-numbers-database
    private func knownServiceName(_ uuid: CBUUID) -> String? {
        let known: [String: String] = [
            "1800": "Generic Access",
            "1801": "Generic Attribute",
            "180A": "Device Information",
            "180D": "Heart Rate",
            "180F": "Battery Service",
            "1816": "Cycling Speed and Cadence",
            "1818": "Cycling Power",
            "1826": "Fitness Machine"
        ]
        return known[uuid.uuidString]
    }

    // Official Bluetooth SIG Assigned Numbers
    // Source: https://github.com/NordicSemiconductor/bluetooth-numbers-database
    private func knownCharacteristicName(_ uuid: CBUUID) -> String? {
        let known: [String: String] = [
            // Generic Access
            "2A00": "Device Name",
            "2A01": "Appearance",
            // Device Information
            "2A29": "Manufacturer Name String",
            "2A24": "Model Number String",
            "2A25": "Serial Number String",
            "2A27": "Hardware Revision String",
            "2A26": "Firmware Revision String",
            "2A28": "Software Revision String",
            // Battery
            "2A19": "Battery Level",
            // Heart Rate
            "2A37": "Heart Rate Measurement",
            "2A38": "Body Sensor Location",
            // Cycling Power
            "2A63": "Cycling Power Measurement",
            "2A65": "Cycling Power Feature",
            "2A66": "Cycling Power Control Point",
            // Cycling Speed and Cadence
            "2A5B": "CSC Measurement",
            "2A5C": "CSC Feature",
            // FTMS
            "2ACC": "Fitness Machine Feature",
            "2ACD": "Treadmill Data",
            "2ACE": "Cross Trainer Data",
            "2ACF": "Step Climber Data",
            "2AD0": "Stair Climber Data",
            "2AD1": "Rower Data",
            "2AD2": "Indoor Bike Data",
            "2AD3": "Training Status",
            "2AD4": "Supported Speed Range",
            "2AD5": "Supported Inclination Range",
            "2AD6": "Supported Resistance Level Range",
            "2AD7": "Supported Heart Rate Range",
            "2AD8": "Supported Power Range",
            "2AD9": "Fitness Machine Control Point",
            "2ADA": "Fitness Machine Status"
        ]
        return known[uuid.uuidString]
    }
}

// MARK: - ble_read

struct BleReadTool: Tool {
    let name = "ble_read"
    let description = "Read any characteristic by UUID. Returns hex data and decoded values if possible."

    var inputSchema: [String: JSONValue] {
        [
            "type": .string("object"),
            "properties": .object([
                "uuid": .object([
                    "type": .string("string"),
                    "description": .string("Characteristic UUID (e.g., '2A19' for battery level, or full UUID)")
                ])
            ]),
            "required": .array([.string("uuid")])
        ]
    }

    func execute(arguments: [String: JSONValue], bleManager: BLEManager) async throws -> String {
        let state = await bleManager.connectionState
        guard state == .connected else {
            throw ToolError("Not connected. Use ble_connect first.")
        }

        guard let uuidString = arguments["uuid"]?.stringValue else {
            throw ToolError("Missing 'uuid' parameter")
        }

        let uuid = CBUUID(string: uuidString)
        let data = try await bleManager.read(characteristicUUID: uuid)

        var lines: [String] = []
        lines.append("Characteristic: \(uuid.uuidString)")
        if let name = knownCharacteristicName(uuid) {
            lines.append("Name: \(name)")
        }
        lines.append("Length: \(data.count) bytes")
        lines.append("Hex: \(data.hexString)")

        // Try to decode as ASCII if printable
        if let ascii = String(data: data, encoding: .utf8),
           ascii.allSatisfy({ $0.isASCII && !$0.isNewline }) {
            lines.append("ASCII: \(ascii)")
        }

        // Known characteristic decodings
        if let decoded = decodeKnownCharacteristic(uuid: uuid, data: data) {
            lines.append("Value: \(decoded)")
        }

        return lines.joined(separator: "\n")
    }

    private func decodeKnownCharacteristic(uuid: CBUUID, data: Data) -> String? {
        switch uuid.uuidString {
        case "2A19": // Battery Level
            guard data.count >= 1 else { return nil }
            return "\(data[0])%"
        case "2A37": // Heart Rate Measurement
            guard data.count >= 2 else { return nil }
            let flags = data[0]
            let is16bit = (flags & 0x01) != 0
            if is16bit && data.count >= 3 {
                let hr = UInt16(data[1]) | (UInt16(data[2]) << 8)
                return "\(hr) bpm"
            } else {
                return "\(data[1]) bpm"
            }
        default:
            return nil
        }
    }

    private func knownCharacteristicName(_ uuid: CBUUID) -> String? {
        let known: [String: String] = [
            "2A00": "Device Name",
            "2A19": "Battery Level",
            "2A29": "Manufacturer Name",
            "2A24": "Model Number",
            "2A25": "Serial Number",
            "2A26": "Firmware Revision",
            "2A27": "Hardware Revision",
            "2A28": "Software Revision",
            "2A37": "Heart Rate Measurement",
            "2A38": "Body Sensor Location",
            "2A63": "Cycling Power Measurement",
            "2ACC": "Fitness Machine Feature",
            "2AD2": "Indoor Bike Data",
            "2AD9": "Fitness Machine Control Point"
        ]
        return known[uuid.uuidString]
    }
}

// MARK: - ble_write

struct BleWriteTool: Tool {
    let name = "ble_write"
    let description = "Write to any characteristic by UUID. Supports hex bytes or text."

    var inputSchema: [String: JSONValue] {
        [
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
                "text": .object([
                    "type": .string("string"),
                    "description": .string("Text to write (alternative to hex)")
                ]),
                "response": .object([
                    "type": .string("boolean"),
                    "description": .string("Wait for write response (default: true)")
                ])
            ]),
            "required": .array([.string("uuid")])
        ]
    }

    func execute(arguments: [String: JSONValue], bleManager: BLEManager) async throws -> String {
        let state = await bleManager.connectionState
        guard state == .connected else {
            throw ToolError("Not connected. Use ble_connect first.")
        }

        guard let uuidString = arguments["uuid"]?.stringValue else {
            throw ToolError("Missing 'uuid' parameter")
        }

        let data: Data
        if let hexString = arguments["hex"]?.stringValue {
            // Parse hex string
            let hexParts = hexString.split(separator: " ").compactMap { part -> UInt8? in
                let hex = part.hasPrefix("0x") ? String(part.dropFirst(2)) : String(part)
                return UInt8(hex, radix: 16)
            }
            guard !hexParts.isEmpty else {
                throw ToolError("Invalid hex string. Use format like '05 64 00' or '0x05 0x64 0x00'")
            }
            data = Data(hexParts)
        } else if let textString = arguments["text"]?.stringValue {
            guard let textData = textString.data(using: .utf8) else {
                throw ToolError("Could not encode text as UTF-8")
            }
            data = textData
        } else {
            throw ToolError("Missing 'hex' or 'text' parameter")
        }

        let withResponse = arguments["response"]?.stringValue != "false"

        let uuid = CBUUID(string: uuidString)
        try await bleManager.write(characteristicUUID: uuid, data: data, withResponse: withResponse)

        let responseType = withResponse ? "with response" : "without response"
        return "Wrote \(data.count) bytes to \(uuid.uuidString) (\(responseType))\nData: \(data.hexString)"
    }
}

// MARK: - ble_subscribe

struct BleSubscribeTool: Tool {
    let name = "ble_subscribe"
    let description = "Subscribe to notifications from any characteristic. Collects samples and returns summary."

    var inputSchema: [String: JSONValue] {
        [
            "type": .string("object"),
            "properties": .object([
                "uuid": .object([
                    "type": .string("string"),
                    "description": .string("Characteristic UUID to subscribe to (e.g., '2A37' for heart rate)")
                ]),
                "samples": .object([
                    "type": .string("integer"),
                    "description": .string("Number of notifications to collect (default: 10, max: 100)")
                ]),
                "timeout": .object([
                    "type": .string("integer"),
                    "description": .string("Timeout in seconds (default: 30)")
                ]),
                "format": .object([
                    "type": .string("string"),
                    "description": .string("Output format: 'hex' (default), 'ascii', or 'raw'")
                ])
            ]),
            "required": .array([.string("uuid")])
        ]
    }

    func execute(arguments: [String: JSONValue], bleManager: BLEManager) async throws -> String {
        let state = await bleManager.connectionState
        guard state == .connected else {
            throw ToolError("Not connected. Use ble_connect first.")
        }

        guard let uuidString = arguments["uuid"]?.stringValue else {
            throw ToolError("Missing 'uuid' parameter")
        }

        let sampleCount = min(arguments["samples"]?.intValue ?? 10, 100)
        let timeout = arguments["timeout"]?.intValue ?? 30
        let format = arguments["format"]?.stringValue ?? "hex"

        let uuid = CBUUID(string: uuidString)
        let stream = try await bleManager.subscribe(characteristicUUID: uuid)

        var samples: [Data] = []
        let startTime = Date()

        for await data in stream {
            samples.append(data)
            if samples.count >= sampleCount {
                break
            }
            if Date().timeIntervalSince(startTime) > Double(timeout) {
                break
            }
        }

        await bleManager.unsubscribe(characteristicUUID: uuid)

        if samples.isEmpty {
            return "No notifications received within \(timeout)s timeout"
        }

        var lines: [String] = []
        lines.append("Received \(samples.count) notification(s) from \(uuid.uuidString)")
        lines.append("")

        for (index, data) in samples.enumerated() {
            let formatted: String
            switch format {
            case "ascii":
                formatted = String(data: data, encoding: .utf8) ?? data.hexString
            case "raw":
                formatted = data.map { String($0) }.joined(separator: ",")
            default:
                formatted = data.hexString
            }
            lines.append("[\(index + 1)] \(formatted) (\(data.count) bytes)")
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - ble_unsubscribe

struct BleUnsubscribeTool: Tool {
    let name = "ble_unsubscribe"
    let description = "Stop notifications from a characteristic."

    var inputSchema: [String: JSONValue] {
        [
            "type": .string("object"),
            "properties": .object([
                "uuid": .object([
                    "type": .string("string"),
                    "description": .string("Characteristic UUID to unsubscribe from")
                ])
            ]),
            "required": .array([.string("uuid")])
        ]
    }

    func execute(arguments: [String: JSONValue], bleManager: BLEManager) async throws -> String {
        let state = await bleManager.connectionState
        guard state == .connected else {
            throw ToolError("Not connected. Use ble_connect first.")
        }

        guard let uuidString = arguments["uuid"]?.stringValue else {
            throw ToolError("Missing 'uuid' parameter")
        }

        let uuid = CBUUID(string: uuidString)
        await bleManager.unsubscribe(characteristicUUID: uuid)

        return "Unsubscribed from \(uuid.uuidString)"
    }
}
