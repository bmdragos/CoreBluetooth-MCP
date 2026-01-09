import Foundation
import CoreBluetooth

// MARK: - FTMS UUIDs

enum FTMS {
    // Service
    static let serviceUUID = CBUUID(string: "1826")

    // Characteristics
    static let indoorBikeData = CBUUID(string: "2AD2")
    static let fitnessMachineFeature = CBUUID(string: "2ACC")
    static let fitnessMachineControlPoint = CBUUID(string: "2AD9")
    static let fitnessMachineStatus = CBUUID(string: "2ADA")
    static let supportedPowerRange = CBUUID(string: "2AD8")
    static let supportedResistanceRange = CBUUID(string: "2AD6")
    static let trainingStatus = CBUUID(string: "2AD3")

    // Control Point Op Codes
    enum OpCode: UInt8 {
        case requestControl = 0x00
        case reset = 0x01
        case setTargetPower = 0x05
        case startOrResume = 0x07
        case stopOrPause = 0x08
        case setIndoorBikeSimulation = 0x11
        case responseCode = 0x80
    }

    // Result Codes
    enum ResultCode: UInt8 {
        case success = 0x01
        case notSupported = 0x02
        case invalidParameter = 0x03
        case operationFailed = 0x04
        case controlNotPermitted = 0x05
    }
}

// MARK: - Indoor Bike Data Parser

struct IndoorBikeData {
    let instantaneousSpeed: Double?      // km/h
    let averageSpeed: Double?            // km/h
    let instantaneousCadence: Double?    // rpm
    let averageCadence: Double?          // rpm
    let totalDistance: Int?              // meters
    let resistanceLevel: Int?
    let instantaneousPower: Int?         // watts
    let averagePower: Int?               // watts
    let totalEnergy: Int?                // kcal
    let energyPerHour: Int?              // kcal/h
    let energyPerMinute: Int?            // kcal/min
    let heartRate: Int?                  // bpm
    let metabolicEquivalent: Double?
    let elapsedTime: Int?                // seconds
    let remainingTime: Int?              // seconds

    static func parse(from data: Data) -> IndoorBikeData? {
        guard data.count >= 2 else { return nil }

        let flags = UInt16(data[0]) | (UInt16(data[1]) << 8)
        var offset = 2

        func readUInt16() -> UInt16? {
            guard offset + 2 <= data.count else { return nil }
            let value = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
            offset += 2
            return value
        }

        func readUInt8() -> UInt8? {
            guard offset + 1 <= data.count else { return nil }
            let value = data[offset]
            offset += 1
            return value
        }

        func readInt16() -> Int16? {
            guard offset + 2 <= data.count else { return nil }
            let value = Int16(bitPattern: UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8))
            offset += 2
            return value
        }

        func readUInt24() -> UInt32? {
            guard offset + 3 <= data.count else { return nil }
            let value = UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8) | (UInt32(data[offset + 2]) << 16)
            offset += 3
            return value
        }

        // Bit 0: More Data (0 = speed present)
        var instantaneousSpeed: Double? = nil
        if (flags & 0x0001) == 0 {
            if let raw = readUInt16() {
                instantaneousSpeed = Double(raw) / 100.0  // 0.01 km/h resolution
            }
        }

        // Bit 1: Average Speed Present
        var averageSpeed: Double? = nil
        if (flags & 0x0002) != 0 {
            if let raw = readUInt16() {
                averageSpeed = Double(raw) / 100.0
            }
        }

        // Bit 2: Instantaneous Cadence Present
        var instantaneousCadence: Double? = nil
        if (flags & 0x0004) != 0 {
            if let raw = readUInt16() {
                instantaneousCadence = Double(raw) / 2.0  // 0.5 rpm resolution
            }
        }

        // Bit 3: Average Cadence Present
        var averageCadence: Double? = nil
        if (flags & 0x0008) != 0 {
            if let raw = readUInt16() {
                averageCadence = Double(raw) / 2.0
            }
        }

        // Bit 4: Total Distance Present
        var totalDistance: Int? = nil
        if (flags & 0x0010) != 0 {
            if let raw = readUInt24() {
                totalDistance = Int(raw)  // meters
            }
        }

        // Bit 5: Resistance Level Present
        var resistanceLevel: Int? = nil
        if (flags & 0x0020) != 0 {
            if let raw = readInt16() {
                resistanceLevel = Int(raw)
            }
        }

        // Bit 6: Instantaneous Power Present
        var instantaneousPower: Int? = nil
        if (flags & 0x0040) != 0 {
            if let raw = readInt16() {
                instantaneousPower = Int(raw)  // watts
            }
        }

        // Bit 7: Average Power Present
        var averagePower: Int? = nil
        if (flags & 0x0080) != 0 {
            if let raw = readInt16() {
                averagePower = Int(raw)
            }
        }

        // Bit 8: Expended Energy Present
        var totalEnergy: Int? = nil
        var energyPerHour: Int? = nil
        var energyPerMinute: Int? = nil
        if (flags & 0x0100) != 0 {
            if let total = readUInt16() {
                totalEnergy = Int(total)
            }
            if let perHour = readUInt16() {
                energyPerHour = Int(perHour)
            }
            if let perMin = readUInt8() {
                energyPerMinute = Int(perMin)
            }
        }

        // Bit 9: Heart Rate Present
        var heartRate: Int? = nil
        if (flags & 0x0200) != 0 {
            if let raw = readUInt8() {
                heartRate = Int(raw)
            }
        }

        // Bit 10: Metabolic Equivalent Present
        var metabolicEquivalent: Double? = nil
        if (flags & 0x0400) != 0 {
            if let raw = readUInt8() {
                metabolicEquivalent = Double(raw) / 10.0
            }
        }

        // Bit 11: Elapsed Time Present
        var elapsedTime: Int? = nil
        if (flags & 0x0800) != 0 {
            if let raw = readUInt16() {
                elapsedTime = Int(raw)
            }
        }

        // Bit 12: Remaining Time Present
        var remainingTime: Int? = nil
        if (flags & 0x1000) != 0 {
            if let raw = readUInt16() {
                remainingTime = Int(raw)
            }
        }

        return IndoorBikeData(
            instantaneousSpeed: instantaneousSpeed,
            averageSpeed: averageSpeed,
            instantaneousCadence: instantaneousCadence,
            averageCadence: averageCadence,
            totalDistance: totalDistance,
            resistanceLevel: resistanceLevel,
            instantaneousPower: instantaneousPower,
            averagePower: averagePower,
            totalEnergy: totalEnergy,
            energyPerHour: energyPerHour,
            energyPerMinute: energyPerMinute,
            heartRate: heartRate,
            metabolicEquivalent: metabolicEquivalent,
            elapsedTime: elapsedTime,
            remainingTime: remainingTime
        )
    }

    func toJSON() -> String {
        var dict: [String: Any] = [:]

        if let v = instantaneousSpeed { dict["speed_kmh"] = v }
        if let v = averageSpeed { dict["avg_speed_kmh"] = v }
        if let v = instantaneousCadence { dict["cadence_rpm"] = v }
        if let v = averageCadence { dict["avg_cadence_rpm"] = v }
        if let v = totalDistance { dict["distance_m"] = v }
        if let v = resistanceLevel { dict["resistance"] = v }
        if let v = instantaneousPower { dict["power_watts"] = v }
        if let v = averagePower { dict["avg_power_watts"] = v }
        if let v = totalEnergy { dict["energy_kcal"] = v }
        if let v = heartRate { dict["heart_rate_bpm"] = v }
        if let v = elapsedTime { dict["elapsed_time_s"] = v }

        if let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        return "{}"
    }

    var summary: String {
        var parts: [String] = []
        if let p = instantaneousPower { parts.append("\(p)W") }
        if let c = instantaneousCadence { parts.append("\(Int(c))rpm") }
        if let s = instantaneousSpeed { parts.append(String(format: "%.1fkm/h", s)) }
        if let h = heartRate { parts.append("\(h)bpm") }
        return parts.isEmpty ? "No data" : parts.joined(separator: " | ")
    }
}

// MARK: - Feature Flags Parser

struct FTMSFeatures {
    let fitnessMachineFeatures: UInt32
    let targetSettingFeatures: UInt32

    var supportedFeatures: [String] {
        var features: [String] = []

        // Fitness Machine Features (first 4 bytes)
        if fitnessMachineFeatures & 0x0001 != 0 { features.append("Average Speed") }
        if fitnessMachineFeatures & 0x0002 != 0 { features.append("Cadence") }
        if fitnessMachineFeatures & 0x0004 != 0 { features.append("Total Distance") }
        if fitnessMachineFeatures & 0x0008 != 0 { features.append("Inclination") }
        if fitnessMachineFeatures & 0x0010 != 0 { features.append("Elevation Gain") }
        if fitnessMachineFeatures & 0x0020 != 0 { features.append("Pace") }
        if fitnessMachineFeatures & 0x0040 != 0 { features.append("Step Count") }
        if fitnessMachineFeatures & 0x0080 != 0 { features.append("Resistance Level") }
        if fitnessMachineFeatures & 0x0100 != 0 { features.append("Stride Count") }
        if fitnessMachineFeatures & 0x0200 != 0 { features.append("Expended Energy") }
        if fitnessMachineFeatures & 0x0400 != 0 { features.append("Heart Rate") }
        if fitnessMachineFeatures & 0x0800 != 0 { features.append("Metabolic Equivalent") }
        if fitnessMachineFeatures & 0x1000 != 0 { features.append("Elapsed Time") }
        if fitnessMachineFeatures & 0x2000 != 0 { features.append("Remaining Time") }
        if fitnessMachineFeatures & 0x4000 != 0 { features.append("Power Measurement") }
        if fitnessMachineFeatures & 0x8000 != 0 { features.append("Force on Belt / Power Output") }
        if fitnessMachineFeatures & 0x10000 != 0 { features.append("User Data Retention") }

        return features
    }

    var supportedTargetSettings: [String] {
        var settings: [String] = []

        // Target Setting Features (second 4 bytes)
        if targetSettingFeatures & 0x0001 != 0 { settings.append("Speed Target") }
        if targetSettingFeatures & 0x0002 != 0 { settings.append("Inclination Target") }
        if targetSettingFeatures & 0x0004 != 0 { settings.append("Resistance Target") }
        if targetSettingFeatures & 0x0008 != 0 { settings.append("Power Target") }
        if targetSettingFeatures & 0x0010 != 0 { settings.append("Heart Rate Target") }
        if targetSettingFeatures & 0x0020 != 0 { settings.append("Targeted Expended Energy") }
        if targetSettingFeatures & 0x0040 != 0 { settings.append("Targeted Step Number") }
        if targetSettingFeatures & 0x0080 != 0 { settings.append("Targeted Stride Number") }
        if targetSettingFeatures & 0x0100 != 0 { settings.append("Targeted Distance") }
        if targetSettingFeatures & 0x0200 != 0 { settings.append("Targeted Training Time") }
        if targetSettingFeatures & 0x0400 != 0 { settings.append("Targeted Time in Two HR Zones") }
        if targetSettingFeatures & 0x0800 != 0 { settings.append("Targeted Time in Three HR Zones") }
        if targetSettingFeatures & 0x1000 != 0 { settings.append("Targeted Time in Five HR Zones") }
        if targetSettingFeatures & 0x2000 != 0 { settings.append("Indoor Bike Simulation") }
        if targetSettingFeatures & 0x4000 != 0 { settings.append("Wheel Circumference") }
        if targetSettingFeatures & 0x8000 != 0 { settings.append("Spin Down Control") }
        if targetSettingFeatures & 0x10000 != 0 { settings.append("Targeted Cadence") }

        return settings
    }

    static func parse(from data: Data) -> FTMSFeatures? {
        guard data.count >= 8 else { return nil }

        let fitness = UInt32(data[0]) | (UInt32(data[1]) << 8) | (UInt32(data[2]) << 16) | (UInt32(data[3]) << 24)
        let target = UInt32(data[4]) | (UInt32(data[5]) << 8) | (UInt32(data[6]) << 16) | (UInt32(data[7]) << 24)

        return FTMSFeatures(fitnessMachineFeatures: fitness, targetSettingFeatures: target)
    }
}
