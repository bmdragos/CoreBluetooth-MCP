import XCTest
@testable import CoreBluetooth_MCP

final class HRSParsingTests: XCTestCase {

    // MARK: - Heart Rate Value Format

    func testParse_8BitHeartRate() {
        // flags=0x00: 8-bit HR, no contact, no energy, no RR
        // HR = 72 bpm
        let data = Data([0x00, 0x48])

        guard let result = HeartRateMeasurement.parse(from: data) else {
            XCTFail("Failed to parse data")
            return
        }

        XCTAssertEqual(result.heartRate, 72)
        XCTAssertNil(result.energyExpended)
        XCTAssertNil(result.rrIntervals)
    }

    func testParse_16BitHeartRate() {
        // flags=0x01: 16-bit HR
        // HR = 0x0100 = 256 bpm (edge case for athletes with very high HR)
        let data = Data([0x01, 0x00, 0x01])

        guard let result = HeartRateMeasurement.parse(from: data) else {
            XCTFail("Failed to parse data")
            return
        }

        XCTAssertEqual(result.heartRate, 256)
    }

    func testParse_16BitHeartRate_Normal() {
        // flags=0x01: 16-bit HR
        // HR = 0x0096 = 150 bpm
        let data = Data([0x01, 0x96, 0x00])

        guard let result = HeartRateMeasurement.parse(from: data) else {
            XCTFail("Failed to parse data")
            return
        }

        XCTAssertEqual(result.heartRate, 150)
    }

    // MARK: - Sensor Contact Status

    func testParse_SensorContactNotSupported() {
        // flags=0x00: bits 1-2 = 00 -> not supported
        let data = Data([0x00, 0x48])

        guard let result = HeartRateMeasurement.parse(from: data) else {
            XCTFail("Failed to parse data")
            return
        }

        XCTAssertEqual(result.sensorContact, .notSupported)
    }

    func testParse_SensorContactNotDetected() {
        // flags=0x04: bits 1-2 = 10 -> not detected
        let data = Data([0x04, 0x48])

        guard let result = HeartRateMeasurement.parse(from: data) else {
            XCTFail("Failed to parse data")
            return
        }

        XCTAssertEqual(result.sensorContact, .notDetected)
    }

    func testParse_SensorContactDetected() {
        // flags=0x06: bits 1-2 = 11 -> detected
        let data = Data([0x06, 0x48])

        guard let result = HeartRateMeasurement.parse(from: data) else {
            XCTFail("Failed to parse data")
            return
        }

        XCTAssertEqual(result.sensorContact, .detected)
    }

    // MARK: - Energy Expended

    func testParse_WithEnergyExpended() {
        // flags=0x08: energy present
        // HR = 120, Energy = 0x00C8 = 200 kJ
        let data = Data([0x08, 0x78, 0xC8, 0x00])

        guard let result = HeartRateMeasurement.parse(from: data) else {
            XCTFail("Failed to parse data")
            return
        }

        XCTAssertEqual(result.heartRate, 120)
        XCTAssertEqual(result.energyExpended, 200)
    }

    // MARK: - RR Intervals

    func testParse_WithRRIntervals() {
        // flags=0x10: RR intervals present
        // HR = 60, RR = 0x0400 = 1024 -> 1024/1024 = 1.0 second
        let data = Data([0x10, 0x3C, 0x00, 0x04])

        guard let result = HeartRateMeasurement.parse(from: data) else {
            XCTFail("Failed to parse data")
            return
        }

        XCTAssertEqual(result.heartRate, 60)
        XCTAssertNotNil(result.rrIntervals)
        XCTAssertEqual(result.rrIntervals!.count, 1)
        XCTAssertEqual(result.rrIntervals![0], 1.0, accuracy: 0.001)
    }

    func testParse_WithMultipleRRIntervals() {
        // flags=0x10: RR intervals present
        // HR = 80
        // RR1 = 0x0300 = 768 -> 768/1024 = 0.75s = 750ms
        // RR2 = 0x0320 = 800 -> 800/1024 = 0.78125s = 781ms
        let data = Data([0x10, 0x50, 0x00, 0x03, 0x20, 0x03])

        guard let result = HeartRateMeasurement.parse(from: data) else {
            XCTFail("Failed to parse data")
            return
        }

        XCTAssertEqual(result.heartRate, 80)
        XCTAssertNotNil(result.rrIntervals)
        XCTAssertEqual(result.rrIntervals!.count, 2)
        XCTAssertEqual(result.rrIntervals![0], 0.75, accuracy: 0.001)
        XCTAssertEqual(result.rrIntervals![1], 0.78125, accuracy: 0.001)
    }

    // MARK: - All Fields Combined

    func testParse_AllFields() {
        // flags=0x1E: 8-bit HR, contact detected (11), energy present, RR present
        // HR = 85
        // Energy = 0x012C = 300 kJ
        // RR = 0x02D0 = 720 -> 720/1024 = 0.703125s
        let data = Data([0x1E, 0x55, 0x2C, 0x01, 0xD0, 0x02])

        guard let result = HeartRateMeasurement.parse(from: data) else {
            XCTFail("Failed to parse data")
            return
        }

        XCTAssertEqual(result.heartRate, 85)
        XCTAssertEqual(result.sensorContact, .detected)
        XCTAssertEqual(result.energyExpended, 300)
        XCTAssertNotNil(result.rrIntervals)
        XCTAssertEqual(result.rrIntervals![0], 0.703125, accuracy: 0.001)
    }

    // MARK: - Edge Cases

    func testParse_TooShort() {
        let data = Data([0x00])  // Only flags, no HR value
        XCTAssertNil(HeartRateMeasurement.parse(from: data))
    }

    func testParse_EmptyData() {
        let data = Data()
        XCTAssertNil(HeartRateMeasurement.parse(from: data))
    }

    func testParse_16BitTooShort() {
        // flags=0x01 means 16-bit HR, but only 1 byte of HR data
        let data = Data([0x01, 0x50])
        XCTAssertNil(HeartRateMeasurement.parse(from: data))
    }

    // MARK: - Summary Output

    func testSummary_BasicHR() {
        let data = Data([0x00, 0x48])  // 72 bpm
        guard let result = HeartRateMeasurement.parse(from: data) else {
            XCTFail("Failed to parse data")
            return
        }

        let summary = result.summary
        XCTAssertTrue(summary.contains("72 bpm"))
    }

    func testSummary_NoContact() {
        let data = Data([0x04, 0x48])  // not detected
        guard let result = HeartRateMeasurement.parse(from: data) else {
            XCTFail("Failed to parse data")
            return
        }

        let summary = result.summary
        XCTAssertTrue(summary.contains("no contact"))
    }

    func testSummary_WithEnergy() {
        let data = Data([0x08, 0x78, 0xC8, 0x00])  // 120 bpm, 200 kJ
        guard let result = HeartRateMeasurement.parse(from: data) else {
            XCTFail("Failed to parse data")
            return
        }

        let summary = result.summary
        XCTAssertTrue(summary.contains("120 bpm"))
        XCTAssertTrue(summary.contains("200 kJ"))
    }

    func testSummary_WithRRInterval() {
        let data = Data([0x10, 0x3C, 0x00, 0x04])  // 60 bpm, 1000ms RR
        guard let result = HeartRateMeasurement.parse(from: data) else {
            XCTFail("Failed to parse data")
            return
        }

        let summary = result.summary
        XCTAssertTrue(summary.contains("60 bpm"))
        XCTAssertTrue(summary.contains("RR:"))
    }

    // MARK: - Body Sensor Location

    func testBodySensorLocation_Values() {
        XCTAssertEqual(BodySensorLocation.chest.description, "Chest")
        XCTAssertEqual(BodySensorLocation.wrist.description, "Wrist")
        XCTAssertEqual(BodySensorLocation.finger.description, "Finger")
        XCTAssertEqual(BodySensorLocation.earLobe.description, "Ear Lobe")
        XCTAssertEqual(BodySensorLocation.foot.description, "Foot")
        XCTAssertEqual(BodySensorLocation.other.description, "Other")
    }

    func testBodySensorLocation_RawValues() {
        XCTAssertEqual(BodySensorLocation(rawValue: 0), .other)
        XCTAssertEqual(BodySensorLocation(rawValue: 1), .chest)
        XCTAssertEqual(BodySensorLocation(rawValue: 2), .wrist)
        XCTAssertEqual(BodySensorLocation(rawValue: 6), .foot)
        XCTAssertNil(BodySensorLocation(rawValue: 99))  // Invalid
    }
}
