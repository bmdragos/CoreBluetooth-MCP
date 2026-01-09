import XCTest
@testable import CoreBluetooth_MCP

final class DataExtensionTests: XCTestCase {

    // MARK: - Hex String Conversion

    func testHexString_Empty() {
        let data = Data()
        XCTAssertEqual(data.hexString, "")
    }

    func testHexString_SingleByte() {
        let data = Data([0x42])
        XCTAssertEqual(data.hexString, "42")
    }

    func testHexString_MultipleBytes() {
        let data = Data([0x44, 0x00, 0x90, 0x03])
        XCTAssertEqual(data.hexString, "44 00 90 03")
    }

    func testHexString_LeadingZeros() {
        let data = Data([0x00, 0x01, 0x0F])
        XCTAssertEqual(data.hexString, "00 01 0F")
    }

    func testHexString_AllValues() {
        let data = Data([0x00, 0xFF, 0xAB, 0xCD])
        XCTAssertEqual(data.hexString, "00 FF AB CD")
    }
}
