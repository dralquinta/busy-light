import Testing
@testable import BusyLightCore

/// Tests that configuration persists correctly across simulated application restarts.
@MainActor
@Suite("Launch Persistence")
struct LaunchPersistenceTests {

    // Each test creates its own isolated UserDefaults suite and tears it down.
    private func makeDefaults() -> UserDefaults {
        let suiteName = "com.busylight.agent.test-\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        ud.removePersistentDomain(forName: suiteName)
        return ud
    }

    @Test("Settings persist across simulated restart")
    func configurationPersistsAcrossRestarts() {
        let ud = makeDefaults()

        // Simulate first launch: write config
        let config1 = ConfigurationManager(userDefaults: ud)
        config1.setPresenceState(.busy)
        config1.setDeviceNetworkAddress("192.168.1.100")
        config1.setDeviceNetworkPort(9000)

        // Simulate restart: fresh instance reads same UserDefaults
        let config2 = ConfigurationManager(userDefaults: ud)

        #expect(config2.getPresenceState() == .busy)
        #expect(config2.getDeviceNetworkAddress() == "192.168.1.100")
        #expect(config2.getDeviceNetworkPort() == 9000)
    }

    @Test("Default configuration when nothing is saved")
    func defaultConfigurationWhenNothingSaved() {
        let ud = makeDefaults()
        let config = ConfigurationManager(userDefaults: ud)

        #expect(config.getPresenceState() == .available)
        #expect(config.getDeviceNetworkAddress() == "")
        #expect(config.getDeviceNetworkPort() == 8080)
        #expect(config.getShowMenuBarText() == true)
    }

    @Test("Presence state can be toggled between all states")
    func presenceStateToggling() {
        let ud = makeDefaults()
        let config = ConfigurationManager(userDefaults: ud)

        config.setPresenceState(.busy)
        #expect(config.getPresenceState() == .busy)

        config.setPresenceState(.available)
        #expect(config.getPresenceState() == .available)

        config.setPresenceState(.away)
        #expect(config.getPresenceState() == .away)
    }
}

