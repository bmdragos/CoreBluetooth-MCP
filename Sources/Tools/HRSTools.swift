import Foundation
import CoreBluetooth

// MARK: - hrs_discover

struct HrsDiscoverTool: Tool {
    let name = "hrs_discover"
    let description = "Scan for Heart Rate Service devices (service UUID 0x180D)."

    var inputSchema: [String: JSONValue] {
        [
            "type": .string("object"),
            "properties": .object([
                "duration": .object([
                    "type": .string("number"),
                    "description": .string("Scan duration in seconds (default: 5)")
                ])
            ])
        ]
    }

    func execute(arguments: [String: JSONValue], bleManager: BLEManager) async throws -> String {
        let duration = arguments["duration"]?.intValue.map { Double($0) } ?? 5.0

        let devices = await bleManager.scan(duration: duration, serviceUUIDs: [HRS.serviceUUID])

        if devices.isEmpty {
            return "No Heart Rate devices found"
        }

        var lines = ["Found \(devices.count) Heart Rate device(s):", ""]
        for device in devices {
            let name = device.name ?? "(unnamed)"
            lines.append("• \(name)")
            lines.append("  UUID: \(device.identifier.uuidString)")
            lines.append("  RSSI: \(device.rssi) dBm")
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - hrs_read

struct HrsReadTool: Tool {
    let name = "hrs_read"
    let description = "Read current heart rate. Returns BPM and sensor contact status."

    var inputSchema: [String: JSONValue] {
        [
            "type": .string("object"),
            "properties": .object([
                "format": .object([
                    "type": .string("string"),
                    "description": .string("Output format: 'text' (default) or 'json'"),
                    "enum": .array([.string("text"), .string("json")])
                ])
            ])
        ]
    }

    func execute(arguments: [String: JSONValue], bleManager: BLEManager) async throws -> String {
        let state = await bleManager.connectionState
        guard state == .connected else {
            throw ToolError("Not connected. Use ble_connect first.")
        }

        let format = arguments["format"]?.stringValue ?? "text"

        // Subscribe briefly to get a reading (HR is notify-only on most devices)
        let stream = try await bleManager.subscribe(characteristicUUID: HRS.heartRateMeasurement)

        var measurement: HeartRateMeasurement? = nil
        let startTime = Date()

        for await data in stream {
            measurement = HeartRateMeasurement.parse(from: data)
            if measurement != nil { break }
            if Date().timeIntervalSince(startTime) > 5.0 { break }
        }

        await bleManager.unsubscribe(characteristicUUID: HRS.heartRateMeasurement)

        guard let hr = measurement else {
            throw ToolError("No heart rate data received. Is the sensor worn?")
        }

        if format == "json" {
            var dict: [String: Any] = ["heart_rate_bpm": hr.heartRate]
            if let energy = hr.energyExpended {
                dict["energy_kj"] = energy
            }
            if let rr = hr.rrIntervals {
                dict["rr_intervals_ms"] = rr.map { Int($0 * 1000) }
            }
            if let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
        }

        return hr.summary
    }
}

// MARK: - hrs_subscribe

struct HrsSubscribeTool: Tool {
    let name = "hrs_subscribe"
    let description = "Stream heart rate data. Returns readings with min/max/avg stats."

    var inputSchema: [String: JSONValue] {
        [
            "type": .string("object"),
            "properties": .object([
                "samples": .object([
                    "type": .string("integer"),
                    "description": .string("Number of readings to collect (default: 10, max: 100)")
                ]),
                "timeout": .object([
                    "type": .string("integer"),
                    "description": .string("Timeout in seconds (default: 30)")
                ])
            ])
        ]
    }

    func execute(arguments: [String: JSONValue], bleManager: BLEManager) async throws -> String {
        let state = await bleManager.connectionState
        guard state == .connected else {
            throw ToolError("Not connected. Use ble_connect first.")
        }

        let sampleCount = min(arguments["samples"]?.intValue ?? 10, 100)
        let timeout = arguments["timeout"]?.intValue ?? 30

        let stream = try await bleManager.subscribe(characteristicUUID: HRS.heartRateMeasurement)

        var readings: [HeartRateMeasurement] = []
        let startTime = Date()

        for await data in stream {
            if let hr = HeartRateMeasurement.parse(from: data) {
                readings.append(hr)
            }
            if readings.count >= sampleCount { break }
            if Date().timeIntervalSince(startTime) > Double(timeout) { break }
        }

        await bleManager.unsubscribe(characteristicUUID: HRS.heartRateMeasurement)

        if readings.isEmpty {
            return "No heart rate data received within \(timeout)s timeout"
        }

        let elapsed = Date().timeIntervalSince(startTime)
        let hrValues = readings.map { $0.heartRate }
        let minHR = hrValues.min()!
        let maxHR = hrValues.max()!
        let avgHR = hrValues.reduce(0, +) / hrValues.count

        var lines: [String] = []
        lines.append("Collected \(readings.count) reading(s) in \(String(format: "%.1f", elapsed))s")
        lines.append("")
        lines.append("Heart Rate: \(minHR) - \(maxHR) bpm (avg: \(avgHR) bpm)")

        // Check for RR intervals
        let allRR = readings.compactMap { $0.rrIntervals }.flatMap { $0 }
        if !allRR.isEmpty {
            let avgRR = allRR.reduce(0, +) / Double(allRR.count)
            let hrv = calculateHRV(rrIntervals: allRR)
            lines.append(String(format: "RR Interval: %.0fms avg", avgRR * 1000))
            lines.append(String(format: "HRV (RMSSD): %.1fms", hrv))
        }

        lines.append("")
        lines.append("Last reading: \(readings.last!.summary)")

        return lines.joined(separator: "\n")
    }

    private func calculateHRV(rrIntervals: [Double]) -> Double {
        // RMSSD - Root Mean Square of Successive Differences
        guard rrIntervals.count > 1 else { return 0 }

        var sumSquaredDiff: Double = 0
        for i in 1..<rrIntervals.count {
            let diff = rrIntervals[i] - rrIntervals[i - 1]
            sumSquaredDiff += diff * diff
        }

        let rmssd = sqrt(sumSquaredDiff / Double(rrIntervals.count - 1))
        return rmssd * 1000 // Convert to ms
    }
}

// MARK: - hrs_unsubscribe

struct HrsUnsubscribeTool: Tool {
    let name = "hrs_unsubscribe"
    let description = "Stop heart rate streaming."

    var inputSchema: [String: JSONValue] {
        [
            "type": .string("object"),
            "properties": .object([:])
        ]
    }

    func execute(arguments: [String: JSONValue], bleManager: BLEManager) async throws -> String {
        await bleManager.unsubscribe(characteristicUUID: HRS.heartRateMeasurement)
        return "Unsubscribed from Heart Rate"
    }
}

// MARK: - hrs_location

struct HrsLocationTool: Tool {
    let name = "hrs_location"
    let description = "Read body sensor location (chest, wrist, etc.)."

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

        do {
            let data = try await bleManager.read(characteristicUUID: HRS.bodySensorLocation)
            guard data.count >= 1 else {
                throw ToolError("Invalid sensor location data")
            }

            let location = BodySensorLocation(rawValue: data[0]) ?? .other
            return "Sensor Location: \(location.description)"
        } catch {
            throw ToolError("Body Sensor Location not available on this device")
        }
    }
}
