import XCTest
@testable import BusyLightCore

@MainActor
final class ConfigurationManagerTests: XCTestCase {
    func testDeviceNetworkAddressesPersistAcrossInstances() {
        let suiteName = "BusyLightTests.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create UserDefaults suite")
            return
        }

        userDefaults.removePersistentDomain(forName: suiteName)

        let config = ConfigurationManager(userDefaults: userDefaults)
        config.setDeviceNetworkAddresses(["192.168.1.42"])
        config.setDeviceNetworkAddress("192.168.1.42")

        let reloaded = ConfigurationManager(userDefaults: userDefaults)
        XCTAssertEqual(reloaded.getDeviceNetworkAddresses(), ["192.168.1.42"])
        XCTAssertEqual(reloaded.getDeviceNetworkAddress(), "192.168.1.42")
    }
}
