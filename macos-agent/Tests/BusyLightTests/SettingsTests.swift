import Testing
@testable import BusyLightCore

/// Tests for application settings and device status model behaviour.
@MainActor
@Suite("Settings")
struct SettingsTests {

    private func makeDefaults() -> UserDefaults {
        let suiteName = "com.busylight.agent.test-\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        ud.removePersistentDomain(forName: suiteName)
        return ud
    }

    @Test("Device network address can be set and read back")
    func deviceNetworkAddressSettings() {
        let config = ConfigurationManager(userDefaults: makeDefaults())
        config.setDeviceNetworkAddress("ws://192.168.1.100:8080")
        #expect(config.getDeviceNetworkAddress() == "ws://192.168.1.100:8080")
    }

    @Test("Device network port can be set and read back")
    func deviceNetworkPortSettings() {
        let config = ConfigurationManager(userDefaults: makeDefaults())

        config.setDeviceNetworkPort(9000)
        #expect(config.getDeviceNetworkPort() == 9000)

        config.setDeviceNetworkPort(65535)
        #expect(config.getDeviceNetworkPort() == 65535)
    }

    @Test("Launch on startup defaults to false and is toggleable")
    func launchOnStartupSettings() {
        let config = ConfigurationManager(userDefaults: makeDefaults())

        #expect(config.getLaunchOnStartup() == false)
        config.setLaunchOnStartup(true)
        #expect(config.getLaunchOnStartup() == true)
    }

    @Test("Menu bar text visibility defaults to true and is toggleable")
    func menuBarTextVisibilitySettings() {
        let config = ConfigurationManager(userDefaults: makeDefaults())

        #expect(config.getShowMenuBarText() == true)
        config.setShowMenuBarText(false)
        #expect(config.getShowMenuBarText() == false)
    }

    @Test("All PresenceState cases have non-empty display names")
    func presenceStateDisplayNames() {
        #expect(PresenceState.available.displayName == "Available")
        #expect(PresenceState.busy.displayName == "Busy")
        #expect(PresenceState.away.displayName == "Away")

        for state in [PresenceState.available, .busy, .away] {
            #expect(!state.displayName.isEmpty)
        }
    }

    @Test("DeviceStatus represents each connection state correctly")
    func deviceStatusRepresentation() {
        let connected = DeviceStatus(connectionState: .connected)
        #expect(connected.displayText == "Device Connected")

        let disconnected = DeviceStatus(connectionState: .disconnected)
        #expect(disconnected.displayText == "Device Disconnected")

        let error = DeviceStatus(connectionState: .error, errorMessage: "Connection timeout")
        #expect(error.displayText == "Device Error")
        #expect(error.errorMessage == "Connection timeout")
    }
}

