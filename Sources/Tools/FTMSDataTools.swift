import Foundation
import CoreBluetooth
import MCPServer

// MARK: - ftms_read

struct FtmsReadTool: Tool {
    typealias Context = BLEManager

    let name = "ftms_read"
    let description = "Single read of Indoor Bike Data characteristic. Returns parsed values: power (watts), cadence (rpm), speed (km/h)."

    var inputSchema: JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([
                "format": .object([
                    "type": .string("string"),
                    "description": .string("Output format: 'text' (default), 'json', or 'raw'"),
                    "enum": .array([.string("text"), .string("json"), .string("raw")])
                ])
            ])
        ])
    }

    func execute(arguments: [String: JSONValue], context: BLEManager) async throws -> String {
        let state = await context.connectionState
        guard state == .connected else {
            throw ToolError("Not connected. Use ble_connect first.")
        }

        let format = arguments["format"]?.stringValue ?? "text"

        // Indoor Bike Data is notify-only per FTMS spec, so we subscribe and grab 1 sample
        let stream = try await context.subscribe(characteristicUUID: FTMS.indoorBikeData)
        var data: Data?

        for await sample in stream {
            data = sample
            break  // Just grab first notification
        }

        await context.unsubscribe(characteristicUUID: FTMS.indoorBikeData)

        guard let data else {
            throw ToolError("No data received from Indoor Bike Data characteristic")
        }

        if format == "raw" {
            return "Raw data (\(data.count) bytes): \(data.hexString)"
        }

        guard let bikeData = IndoorBikeData.parse(from: data) else {
            return "Failed to parse Indoor Bike Data. Raw: \(data.hexString)"
        }

        if format == "json" {
            return bikeData.toJSON()
        }

        // Text format
        var lines: [String] = []
        if let p = bikeData.instantaneousPower { lines.append("Power: \(p) W") }
        if let c = bikeData.instantaneousCadence { lines.append("Cadence: \(Int(c)) rpm") }
        if let s = bikeData.instantaneousSpeed { lines.append("Speed: \(String(format: "%.1f", s)) km/h") }
        if let h = bikeData.heartRate { lines.append("Heart Rate: \(h) bpm") }
        if let d = bikeData.totalDistance { lines.append("Distance: \(d) m") }
        if let e = bikeData.elapsedTime { lines.append("Elapsed: \(e) s") }

        return lines.isEmpty ? "No data fields present" : lines.joined(separator: "\n")
    }
}

// MARK: - ftms_subscribe

struct FtmsSubscribeTool: Tool {
    typealias Context = BLEManager

    let name = "ftms_subscribe"
    let description = "Subscribe to Indoor Bike Data notifications. Returns live streaming data. Use ftms_unsubscribe to stop."

    var inputSchema: JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([
                "samples": .object([
                    "type": .string("integer"),
                    "description": .string("Number of samples to collect before returning (default: 10, max: 100)")
                ]),
                "timeout": .object([
                    "type": .string("integer"),
                    "description": .string("Timeout in seconds (default: 30)")
                ]),
                "format": .object([
                    "type": .string("string"),
                    "description": .string("Output format: 'summary' (default), 'json', or 'raw'")
                ])
            ])
        ])
    }

    func execute(arguments: [String: JSONValue], context: BLEManager) async throws -> String {
        let state = await context.connectionState
        guard state == .connected else {
            throw ToolError("Not connected. Use ble_connect first.")
        }

        let maxSamples = min(arguments["samples"]?.intValue ?? 10, 100)
        let timeout = arguments["timeout"]?.intValue ?? 30
        let format = arguments["format"]?.stringValue ?? "summary"

        let stream = try await context.subscribe(characteristicUUID: FTMS.indoorBikeData)

        var samples: [IndoorBikeData] = []
        var rawSamples: [Data] = []
        let startTime = Date()

        for await data in stream {
            rawSamples.append(data)
            if let parsed = IndoorBikeData.parse(from: data) {
                samples.append(parsed)
            }

            if samples.count >= maxSamples {
                break
            }

            if Date().timeIntervalSince(startTime) > Double(timeout) {
                break
            }
        }

        await context.unsubscribe(characteristicUUID: FTMS.indoorBikeData)

        if samples.isEmpty {
            return "No data received (timeout: \(timeout)s)"
        }

        switch format {
        case "raw":
            let lines = rawSamples.enumerated().map { i, data in
                "[\(i + 1)] \(data.hexString)"
            }
            return "Received \(rawSamples.count) raw samples:\n\(lines.joined(separator: "\n"))"

        case "json":
            let jsonArray = samples.map { $0.toJSON() }
            return "[\(jsonArray.joined(separator: ","))]"

        default:  // summary
            // Calculate stats
            let powers = samples.compactMap { $0.instantaneousPower }
            let cadences = samples.compactMap { $0.instantaneousCadence }
            let speeds = samples.compactMap { $0.instantaneousSpeed }

            var lines: [String] = []
            lines.append("Collected \(samples.count) samples in \(String(format: "%.1f", Date().timeIntervalSince(startTime)))s")
            lines.append("")

            if !powers.isEmpty {
                let avgPower = powers.reduce(0, +) / powers.count
                let minPower = powers.min()!
                let maxPower = powers.max()!
                lines.append("Power: \(minPower)W - \(maxPower)W (avg: \(avgPower)W)")
            }

            if !cadences.isEmpty {
                let avgCadence = cadences.reduce(0, +) / Double(cadences.count)
                let minCadence = Int(cadences.min()!)
                let maxCadence = Int(cadences.max()!)
                lines.append("Cadence: \(minCadence) - \(maxCadence) rpm (avg: \(Int(avgCadence)) rpm)")
            }

            if !speeds.isEmpty {
                let avgSpeed = speeds.reduce(0, +) / Double(speeds.count)
                lines.append("Speed: \(String(format: "%.1f", speeds.min()!)) - \(String(format: "%.1f", speeds.max()!)) km/h (avg: \(String(format: "%.1f", avgSpeed)) km/h)")
            }

            // Show last reading
            if let last = samples.last {
                lines.append("")
                lines.append("Last reading: \(last.summary)")
            }

            return lines.joined(separator: "\n")
        }
    }
}

// MARK: - ftms_unsubscribe

struct FtmsUnsubscribeTool: Tool {
    typealias Context = BLEManager

    let name = "ftms_unsubscribe"
    let description = "Stop subscribing to Indoor Bike Data notifications."

    var inputSchema: JSONValue {
        Schema.empty
    }

    func execute(arguments: [String: JSONValue], context: BLEManager) async throws -> String {
        await context.unsubscribe(characteristicUUID: FTMS.indoorBikeData)
        return "Unsubscribed from Indoor Bike Data notifications"
    }
}
