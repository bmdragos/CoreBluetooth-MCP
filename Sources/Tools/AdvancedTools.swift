import Foundation
import CoreBluetooth
import MCPServer

// MARK: - ftms_monitor

struct FtmsMonitorTool: Tool {
    typealias Context = BLEManager

    let name = "ftms_monitor"
    let description = "Subscribe for a specified duration, then return a summary with min/max/avg stats."

    var inputSchema: JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([
                "duration": .object([
                    "type": .string("integer"),
                    "description": .string("Monitoring duration in seconds (default: 10, max: 300)")
                ])
            ])
        ])
    }

    func execute(arguments: [String: JSONValue], context: BLEManager) async throws -> String {
        let state = await context.connectionState
        guard state == .connected else {
            throw ToolError("Not connected. Use ble_connect first.")
        }

        let duration = min(arguments["duration"]?.intValue ?? 10, 300)

        let stream = try await context.subscribe(characteristicUUID: FTMS.indoorBikeData)

        var samples: [IndoorBikeData] = []
        let startTime = Date()

        for await data in stream {
            if let parsed = IndoorBikeData.parse(from: data) {
                samples.append(parsed)
            }

            if Date().timeIntervalSince(startTime) >= Double(duration) {
                break
            }
        }

        await context.unsubscribe(characteristicUUID: FTMS.indoorBikeData)

        let elapsed = Date().timeIntervalSince(startTime)

        if samples.isEmpty {
            return "No data received in \(duration) seconds"
        }

        // Calculate statistics
        let powers = samples.compactMap { $0.instantaneousPower }
        let cadences = samples.compactMap { $0.instantaneousCadence }
        let speeds = samples.compactMap { $0.instantaneousSpeed }
        let heartRates = samples.compactMap { $0.heartRate }

        var lines: [String] = []
        lines.append("═══════════════════════════════════════")
        lines.append("  FTMS Monitor Summary")
        lines.append("═══════════════════════════════════════")
        lines.append("")
        lines.append("Duration: \(String(format: "%.1f", elapsed))s")
        lines.append("Samples: \(samples.count) (\(String(format: "%.1f", Double(samples.count) / elapsed)) Hz)")
        lines.append("")

        if !powers.isEmpty {
            let avg = powers.reduce(0, +) / powers.count
            lines.append("Power:")
            lines.append("  Min: \(powers.min()!)W")
            lines.append("  Max: \(powers.max()!)W")
            lines.append("  Avg: \(avg)W")
            lines.append("")
        }

        if !cadences.isEmpty {
            let avg = cadences.reduce(0.0, +) / Double(cadences.count)
            lines.append("Cadence:")
            lines.append("  Min: \(Int(cadences.min()!)) rpm")
            lines.append("  Max: \(Int(cadences.max()!)) rpm")
            lines.append("  Avg: \(Int(avg)) rpm")
            lines.append("")
        }

        if !speeds.isEmpty {
            let avg = speeds.reduce(0.0, +) / Double(speeds.count)
            lines.append("Speed:")
            lines.append("  Min: \(String(format: "%.1f", speeds.min()!)) km/h")
            lines.append("  Max: \(String(format: "%.1f", speeds.max()!)) km/h")
            lines.append("  Avg: \(String(format: "%.1f", avg)) km/h")
            lines.append("")
        }

        if !heartRates.isEmpty {
            let avg = heartRates.reduce(0, +) / heartRates.count
            lines.append("Heart Rate:")
            lines.append("  Min: \(heartRates.min()!) bpm")
            lines.append("  Max: \(heartRates.max()!) bpm")
            lines.append("  Avg: \(avg) bpm")
        }

        lines.append("")
        lines.append("═══════════════════════════════════════")

        return lines.joined(separator: "\n")
    }
}

// MARK: - ftms_test_sequence

struct FtmsTestSequenceTool: Tool {
    typealias Context = BLEManager

    let name = "ftms_test_sequence"
    let description = "Run a quick validation: request control → set 100W → read → set 150W → read → report results."

    var inputSchema: JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([
                "power_low": .object([
                    "type": .string("integer"),
                    "description": .string("First power target in watts (default: 100)")
                ]),
                "power_high": .object([
                    "type": .string("integer"),
                    "description": .string("Second power target in watts (default: 150)")
                ]),
                "settle_time": .object([
                    "type": .string("number"),
                    "description": .string("Time to wait between commands in seconds (default: 2)")
                ])
            ])
        ])
    }

    func execute(arguments: [String: JSONValue], context: BLEManager) async throws -> String {
        let state = await context.connectionState
        guard state == .connected else {
            throw ToolError("Not connected. Use ble_connect first.")
        }

        let powerLow = arguments["power_low"]?.intValue ?? 100
        let powerHigh = arguments["power_high"]?.intValue ?? 150
        let settleTime = arguments["settle_time"]?.intValue.map { Double($0) } ?? 2.0

        var results: [(String, String, Bool)] = []  // (step, result, success)

        func addResult(_ step: String, _ result: String, success: Bool = true) {
            results.append((step, result, success))
        }

        // Step 1: Request Control
        do {
            let data = Data([FTMS.OpCode.requestControl.rawValue])
            try await context.write(characteristicUUID: FTMS.fitnessMachineControlPoint, data: data)
            try await Task.sleep(nanoseconds: 500_000_000)
            addResult("Request Control", "OK")
        } catch {
            addResult("Request Control", "FAILED: \(error.localizedDescription)", success: false)
        }

        // Step 2: Set Power Low
        do {
            let powerInt16 = Int16(clamping: powerLow)
            let data = Data([FTMS.OpCode.setTargetPower.rawValue, UInt8(truncatingIfNeeded: powerInt16), UInt8(truncatingIfNeeded: powerInt16 >> 8)])
            try await context.write(characteristicUUID: FTMS.fitnessMachineControlPoint, data: data)
            addResult("Set \(powerLow)W", "Command sent")
        } catch {
            addResult("Set \(powerLow)W", "FAILED: \(error.localizedDescription)", success: false)
        }

        // Wait for settle
        try await Task.sleep(nanoseconds: UInt64(settleTime * 1_000_000_000))

        // Step 3: Read data at low power (via subscribe - Indoor Bike Data is notify-only)
        do {
            let stream = try await context.subscribe(characteristicUUID: FTMS.indoorBikeData)
            var data: Data?
            for await sample in stream {
                data = sample
                break
            }
            await context.unsubscribe(characteristicUUID: FTMS.indoorBikeData)

            if let data, let bikeData = IndoorBikeData.parse(from: data) {
                addResult("Read @ \(powerLow)W", bikeData.summary)
            } else {
                addResult("Read @ \(powerLow)W", "No data or parse error", success: false)
            }
        } catch {
            addResult("Read @ \(powerLow)W", "FAILED: \(error.localizedDescription)", success: false)
        }

        // Step 4: Set Power High
        do {
            let powerInt16 = Int16(clamping: powerHigh)
            let data = Data([FTMS.OpCode.setTargetPower.rawValue, UInt8(truncatingIfNeeded: powerInt16), UInt8(truncatingIfNeeded: powerInt16 >> 8)])
            try await context.write(characteristicUUID: FTMS.fitnessMachineControlPoint, data: data)
            addResult("Set \(powerHigh)W", "Command sent")
        } catch {
            addResult("Set \(powerHigh)W", "FAILED: \(error.localizedDescription)", success: false)
        }

        // Wait for settle
        try await Task.sleep(nanoseconds: UInt64(settleTime * 1_000_000_000))

        // Step 5: Read data at high power (via subscribe - Indoor Bike Data is notify-only)
        do {
            let stream = try await context.subscribe(characteristicUUID: FTMS.indoorBikeData)
            var data: Data?
            for await sample in stream {
                data = sample
                break
            }
            await context.unsubscribe(characteristicUUID: FTMS.indoorBikeData)

            if let data, let bikeData = IndoorBikeData.parse(from: data) {
                addResult("Read @ \(powerHigh)W", bikeData.summary)
            } else {
                addResult("Read @ \(powerHigh)W", "No data or parse error", success: false)
            }
        } catch {
            addResult("Read @ \(powerHigh)W", "FAILED: \(error.localizedDescription)", success: false)
        }

        // Format results
        var lines: [String] = []
        lines.append("═══════════════════════════════════════")
        lines.append("  FTMS Test Sequence Results")
        lines.append("═══════════════════════════════════════")
        lines.append("")

        let successCount = results.filter { $0.2 }.count
        let totalCount = results.count

        for (step, result, success) in results {
            let icon = success ? "✓" : "✗"
            lines.append("\(icon) \(step): \(result)")
        }

        lines.append("")
        lines.append("═══════════════════════════════════════")
        lines.append("Result: \(successCount)/\(totalCount) steps passed")

        if successCount == totalCount {
            lines.append("Status: ALL TESTS PASSED ✓")
        } else {
            lines.append("Status: SOME TESTS FAILED ✗")
        }

        return lines.joined(separator: "\n")
    }
}
