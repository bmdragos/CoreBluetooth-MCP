import XCTest
@testable import CoreBluetooth_MCP

final class FTMSParsingTests: XCTestCase {

    // MARK: - Indoor Bike Data Parsing

    func testParseIndoorBikeData_PowerAndCadence() {
        // Real data from Lode Bike: flags=0x0044 (speed + cadence + power)
        // 44 00 | 90 03 | 98 00 | 64 00
        // flags | speed  | cadence | power
        let data = Data([0x44, 0x00, 0x90, 0x03, 0x98, 0x00, 0x64, 0x00])

        guard let result = IndoorBikeData.parse(from: data) else {
            XCTFail("Failed to parse data")
            return
        }

        XCTAssertEqual(result.instantaneousSpeed!, 9.12, accuracy: 0.01)  // 0x0390 = 912 -> 9.12 km/h
        XCTAssertEqual(result.instantaneousCadence!, 76.0, accuracy: 0.1)  // 0x0098 = 152 -> 76 rpm
        XCTAssertEqual(result.instantaneousPower, 100)  // 0x0064 = 100W
    }

    func testParseIndoorBikeData_SpeedOnly() {
        // flags=0x0000 means only speed present (bit 0 = 0 means speed IS present)
        let data = Data([0x00, 0x00, 0xE8, 0x03])

        guard let result = IndoorBikeData.parse(from: data) else {
            XCTFail("Failed to parse data")
            return
        }

        XCTAssertEqual(result.instantaneousSpeed!, 10.0, accuracy: 0.01)
        XCTAssertNil(result.instantaneousCadence)
        XCTAssertNil(result.instantaneousPower)
    }

    func testParseIndoorBikeData_AllFields() {
        // flags=0x0FFE - bit 0=0 means speed present, bits 1-11 = other fields
        var data = Data([0xFE, 0x0F])  // flags
        data.append(contentsOf: [0xF4, 0x01])  // speed: 500 -> 5.00 km/h
        data.append(contentsOf: [0xE8, 0x03])  // avg speed: 1000 -> 10.00 km/h
        data.append(contentsOf: [0xB4, 0x00])  // cadence: 180 -> 90 rpm
        data.append(contentsOf: [0xAA, 0x00])  // avg cadence: 170 -> 85 rpm
        data.append(contentsOf: [0x10, 0x27, 0x00])  // distance: 10000m
        data.append(contentsOf: [0x0A, 0x00])  // resistance: 10
        data.append(contentsOf: [0xC8, 0x00])  // power: 200W
        data.append(contentsOf: [0xBE, 0x00])  // avg power: 190W
        data.append(contentsOf: [0x64, 0x00])  // total energy: 100 kcal
        data.append(contentsOf: [0xF4, 0x01])  // energy/hour: 500 kcal/h
        data.append(contentsOf: [0x08])        // energy/min: 8 kcal/min
        data.append(contentsOf: [0x8C])        // heart rate: 140 bpm
        data.append(contentsOf: [0x50])        // MET: 80 -> 8.0
        data.append(contentsOf: [0x58, 0x02])  // elapsed: 600s

        guard let result = IndoorBikeData.parse(from: data) else {
            XCTFail("Failed to parse data")
            return
        }

        XCTAssertEqual(result.instantaneousSpeed!, 5.0, accuracy: 0.01)
        XCTAssertEqual(result.averageSpeed!, 10.0, accuracy: 0.01)
        XCTAssertEqual(result.instantaneousCadence!, 90.0, accuracy: 0.1)
        XCTAssertEqual(result.averageCadence!, 85.0, accuracy: 0.1)
        XCTAssertEqual(result.totalDistance, 10000)
        XCTAssertEqual(result.resistanceLevel, 10)
        XCTAssertEqual(result.instantaneousPower, 200)
        XCTAssertEqual(result.averagePower, 190)
        XCTAssertEqual(result.totalEnergy, 100)
        XCTAssertEqual(result.energyPerHour, 500)
        XCTAssertEqual(result.energyPerMinute, 8)
        XCTAssertEqual(result.heartRate, 140)
        XCTAssertEqual(result.metabolicEquivalent!, 8.0, accuracy: 0.1)
        XCTAssertEqual(result.elapsedTime, 600)
    }

    func testParseIndoorBikeData_TooShort() {
        let data = Data([0x44])  // Only 1 byte, need at least 2 for flags
        XCTAssertNil(IndoorBikeData.parse(from: data))
    }

    func testParseIndoorBikeData_EmptyData() {
        let data = Data()
        XCTAssertNil(IndoorBikeData.parse(from: data))
    }

    // MARK: - FTMS Features Parsing

    func testParseFTMSFeatures_PowerTarget() {
        // Lode Bike features: supports power target
        let data = Data([0x02, 0x40, 0x00, 0x00, 0x08, 0x00, 0x00, 0x00])

        guard let result = FTMSFeatures.parse(from: data) else {
            XCTFail("Failed to parse features")
            return
        }

        XCTAssertTrue(result.supportedTargetSettings.contains("Power Target"))
    }

    func testParseFTMSFeatures_AllCommonFeatures() {
        // Features: cadence + power measurement
        // Target: resistance + power + simulation
        let data = Data([
            0x06, 0x44, 0x00, 0x00,
            0x0C, 0x20, 0x00, 0x00
        ])

        guard let result = FTMSFeatures.parse(from: data) else {
            XCTFail("Failed to parse features")
            return
        }

        XCTAssertTrue(result.supportedFeatures.contains("Cadence"))
        XCTAssertTrue(result.supportedFeatures.contains("Power Measurement"))
        XCTAssertTrue(result.supportedTargetSettings.contains("Power Target"))
        XCTAssertTrue(result.supportedTargetSettings.contains("Resistance Target"))
        XCTAssertTrue(result.supportedTargetSettings.contains("Indoor Bike Simulation"))
    }

    func testParseFTMSFeatures_TooShort() {
        let data = Data([0x02, 0x40, 0x00, 0x00])  // Only 4 bytes, need 8
        XCTAssertNil(FTMSFeatures.parse(from: data))
    }

    // MARK: - Indoor Bike Data Summary

    func testIndoorBikeDataSummary() {
        let data = Data([0x44, 0x00, 0x90, 0x03, 0x98, 0x00, 0x64, 0x00])
        guard let result = IndoorBikeData.parse(from: data) else {
            XCTFail("Failed to parse data")
            return
        }

        let summary = result.summary

        XCTAssertTrue(summary.contains("100W"))
        XCTAssertTrue(summary.contains("76rpm"))
        XCTAssertTrue(summary.contains("km/h"))
    }

    func testIndoorBikeDataJSON() {
        let data = Data([0x44, 0x00, 0x90, 0x03, 0x98, 0x00, 0x64, 0x00])
        guard let result = IndoorBikeData.parse(from: data) else {
            XCTFail("Failed to parse data")
            return
        }

        let json = result.toJSON()

        XCTAssertTrue(json.contains("power_watts"))
        XCTAssertTrue(json.contains("100"))
        XCTAssertTrue(json.contains("cadence_rpm"))
    }
}
