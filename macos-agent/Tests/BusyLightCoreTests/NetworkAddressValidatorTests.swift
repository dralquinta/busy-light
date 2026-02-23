import XCTest
@testable import BusyLightCore

final class NetworkAddressValidatorTests: XCTestCase {
    func testNormalizeIPv4AddressAcceptsValidAddresses() {
        XCTAssertEqual(NetworkAddressValidator.normalizeIPv4Address("192.168.1.42"), "192.168.1.42")
        XCTAssertEqual(NetworkAddressValidator.normalizeIPv4Address(" 10.0.0.1 "), "10.0.0.1")
        XCTAssertEqual(NetworkAddressValidator.normalizeIPv4Address("0.0.0.0"), "0.0.0.0")
        XCTAssertEqual(NetworkAddressValidator.normalizeIPv4Address("255.255.255.255"), "255.255.255.255")
    }

    func testNormalizeIPv4AddressRejectsInvalidAddresses() {
        XCTAssertNil(NetworkAddressValidator.normalizeIPv4Address(""))
        XCTAssertNil(NetworkAddressValidator.normalizeIPv4Address("192.168.1"))
        XCTAssertNil(NetworkAddressValidator.normalizeIPv4Address("192.168.1.1.1"))
        XCTAssertNil(NetworkAddressValidator.normalizeIPv4Address("256.1.1.1"))
        XCTAssertNil(NetworkAddressValidator.normalizeIPv4Address("1.1.1.a"))
        XCTAssertNil(NetworkAddressValidator.normalizeIPv4Address("1..1.1"))
    }
}
