import Foundation
import CoreBluetooth

// MARK: - Heart Rate Service UUIDs

enum HRS {
    // Service
    static let serviceUUID = CBUUID(string: "180D")

    // Characteristics
    static let heartRateMeasurement = CBUUID(string: "2A37")
    static let bodySensorLocation = CBUUID(string: "2A38")
    static let heartRateControlPoint = CBUUID(string: "2A39")
}

// MARK: - Body Sensor Location

enum BodySensorLocation: UInt8 {
    case other = 0
    case chest = 1
    case wrist = 2
    case finger = 3
    case hand = 4
    case earLobe = 5
    case foot = 6

    var description: String {
        switch self {
        case .other: return "Other"
        case .chest: return "Chest"
        case .wrist: return "Wrist"
        case .finger: return "Finger"
        case .hand: return "Hand"
        case .earLobe: return "Ear Lobe"
        case .foot: return "Foot"
        }
    }
}

// MARK: - Heart Rate Measurement Parser

struct HeartRateMeasurement {
    let heartRate: Int              // bpm
    let sensorContact: SensorContact
    let energyExpended: Int?        // kJ
    let rrIntervals: [Double]?      // seconds

    enum SensorContact {
        case notSupported
        case notDetected
        case detected
    }

    static func parse(from data: Data) -> HeartRateMeasurement? {
        guard data.count >= 2 else { return nil }

        let flags = data[0]
        var offset = 1

        // Bit 0: Heart Rate Value Format
        let isHR16bit = (flags & 0x01) != 0

        // Bit 1-2: Sensor Contact Status
        let contactBits = (flags >> 1) & 0x03
        let sensorContact: SensorContact
        switch contactBits {
        case 0, 1: sensorContact = .notSupported
        case 2: sensorContact = .notDetected
        case 3: sensorContact = .detected
        default: sensorContact = .notSupported
        }

        // Bit 3: Energy Expended Present
        let energyPresent = (flags & 0x08) != 0

        // Bit 4: RR-Interval Present
        let rrPresent = (flags & 0x10) != 0

        // Parse heart rate
        let heartRate: Int
        if isHR16bit {
            guard offset + 2 <= data.count else { return nil }
            heartRate = Int(UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8))
            offset += 2
        } else {
            heartRate = Int(data[offset])
            offset += 1
        }

        // Parse energy expended (if present)
        var energyExpended: Int? = nil
        if energyPresent {
            guard offset + 2 <= data.count else { return nil }
            energyExpended = Int(UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8))
            offset += 2
        }

        // Parse RR-Intervals (if present)
        var rrIntervals: [Double]? = nil
        if rrPresent {
            var intervals: [Double] = []
            while offset + 2 <= data.count {
                let raw = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
                // RR-Interval is in 1/1024 seconds
                intervals.append(Double(raw) / 1024.0)
                offset += 2
            }
            if !intervals.isEmpty {
                rrIntervals = intervals
            }
        }

        return HeartRateMeasurement(
            heartRate: heartRate,
            sensorContact: sensorContact,
            energyExpended: energyExpended,
            rrIntervals: rrIntervals
        )
    }

    var summary: String {
        var parts = ["\(heartRate) bpm"]

        switch sensorContact {
        case .detected: break // Don't clutter output
        case .notDetected: parts.append("(no contact)")
        case .notSupported: break
        }

        if let energy = energyExpended {
            parts.append("\(energy) kJ")
        }

        if let rr = rrIntervals, !rr.isEmpty {
            let avgRR = rr.reduce(0, +) / Double(rr.count)
            parts.append(String(format: "RR: %.0fms", avgRR * 1000))
        }

        return parts.joined(separator: " | ")
    }
}
