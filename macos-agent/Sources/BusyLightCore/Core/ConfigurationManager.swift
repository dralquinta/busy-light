import Foundation

/// Manages persistent application configuration using UserDefaults.
/// Isolated to @MainActor so all access is on the main thread, matching AppKit requirements.
@MainActor
public class ConfigurationManager {
    public static let shared = ConfigurationManager()
    
    private let userDefaults: UserDefaults
    private let suiteName = "com.busylight.agent"
    private var configuration: AppConfiguration
    
    public init(userDefaults: UserDefaults? = nil) {
        if let userDefaults = userDefaults {
            self.userDefaults = userDefaults
        } else {
            // Use suite-based defaults for better organization
            self.userDefaults = UserDefaults.standard
        }
        self.configuration = AppConfiguration.defaultConfiguration
        loadConfiguration()
    }
    
    /// Loads configuration from UserDefaults, falling back to defaults on error.
    public func loadConfiguration() {
        configLogger.logEvent("Loading configuration")
        
        // Load each field individually for flexibility
        if let presenceStateString = userDefaults.string(forKey: AppConfiguration.CodingKeys.presenceState.rawValue),
           let presenceState = PresenceState(rawValue: presenceStateString) {
            configuration.presenceState = presenceState
        }
        
        configuration.deviceNetworkAddress = userDefaults.string(forKey: AppConfiguration.CodingKeys.deviceNetworkAddress.rawValue) ?? ""
        configuration.deviceNetworkPort = 80  // WLED default port (fixed)
        
        // Load network addresses array
        if let addresses = userDefaults.array(forKey: AppConfiguration.CodingKeys.deviceNetworkAddresses.rawValue) as? [String] {
            configuration.deviceNetworkAddresses = addresses
        } else if !configuration.deviceNetworkAddress.isEmpty {
            // Migration: copy legacy single address to array
            configuration.deviceNetworkAddresses = [configuration.deviceNetworkAddress]
            configLogger.logEvent("Migrated legacy deviceNetworkAddress to deviceNetworkAddresses")
        }
        
        // Load WLED configuration
        let presetAvailable = userDefaults.integer(forKey: AppConfiguration.CodingKeys.wledPresetAvailable.rawValue)
        configuration.wledPresetAvailable = presetAvailable != 0 ? presetAvailable : 1
        
        let presetTentative = userDefaults.integer(forKey: AppConfiguration.CodingKeys.wledPresetTentative.rawValue)
        configuration.wledPresetTentative = presetTentative != 0 ? presetTentative : 2
        
        let presetBusy = userDefaults.integer(forKey: AppConfiguration.CodingKeys.wledPresetBusy.rawValue)
        configuration.wledPresetBusy = presetBusy != 0 ? presetBusy : 3
        
        let presetAway = userDefaults.integer(forKey: AppConfiguration.CodingKeys.wledPresetAway.rawValue)
        configuration.wledPresetAway = presetAway != 0 ? presetAway : 4
        
        let presetUnknown = userDefaults.integer(forKey: AppConfiguration.CodingKeys.wledPresetUnknown.rawValue)
        configuration.wledPresetUnknown = presetUnknown != 0 ? presetUnknown : 5
        
        let presetOff = userDefaults.integer(forKey: AppConfiguration.CodingKeys.wledPresetOff.rawValue)
        configuration.wledPresetOff = presetOff != 0 ? presetOff : 6
        
        let timeout = userDefaults.integer(forKey: AppConfiguration.CodingKeys.wledHttpTimeout.rawValue)
        configuration.wledHttpTimeout = timeout != 0 ? timeout : 500
        
        let healthCheckInterval = userDefaults.integer(forKey: AppConfiguration.CodingKeys.wledHealthCheckInterval.rawValue)
        configuration.wledHealthCheckInterval = healthCheckInterval != 0 ? healthCheckInterval : 10
        
        // wledEnableDiscovery defaults to true
        if userDefaults.object(forKey: AppConfiguration.CodingKeys.wledEnableDiscovery.rawValue) != nil {
            configuration.wledEnableDiscovery = userDefaults.bool(forKey: AppConfiguration.CodingKeys.wledEnableDiscovery.rawValue)
        }
        
        configuration.launchOnStartup = userDefaults.bool(forKey: AppConfiguration.CodingKeys.launchOnStartup.rawValue)
        
        // showMenuBarText defaults to true
        if userDefaults.object(forKey: AppConfiguration.CodingKeys.showMenuBarText.rawValue) != nil {
            configuration.showMenuBarText = userDefaults.bool(forKey: AppConfiguration.CodingKeys.showMenuBarText.rawValue)
        }
        
        // State machine settings
        if let timeout = userDefaults.object(forKey: AppConfiguration.CodingKeys.manualOverrideTimeoutMinutes.rawValue) as? Int {
            configuration.manualOverrideTimeoutMinutes = timeout == -1 ? nil : timeout
        }
        
        configuration.stateStabilizationSeconds = userDefaults.integer(forKey: AppConfiguration.CodingKeys.stateStabilizationSeconds.rawValue)

        // Load meeting detection settings
        if userDefaults.object(forKey: AppConfiguration.CodingKeys.meetingDetectionEnabled.rawValue) != nil {
            configuration.meetingDetectionEnabled = userDefaults.bool(forKey: AppConfiguration.CodingKeys.meetingDetectionEnabled.rawValue)
        }
        if userDefaults.object(forKey: AppConfiguration.CodingKeys.meetingProviderZoomEnabled.rawValue) != nil {
            configuration.meetingProviderZoomEnabled = userDefaults.bool(forKey: AppConfiguration.CodingKeys.meetingProviderZoomEnabled.rawValue)
        }
        if userDefaults.object(forKey: AppConfiguration.CodingKeys.meetingProviderTeamsEnabled.rawValue) != nil {
            configuration.meetingProviderTeamsEnabled = userDefaults.bool(forKey: AppConfiguration.CodingKeys.meetingProviderTeamsEnabled.rawValue)
        }
        if userDefaults.object(forKey: AppConfiguration.CodingKeys.meetingProviderBrowserEnabled.rawValue) != nil {
            configuration.meetingProviderBrowserEnabled = userDefaults.bool(forKey: AppConfiguration.CodingKeys.meetingProviderBrowserEnabled.rawValue)
        }
        let rawThreshold = userDefaults.integer(forKey: AppConfiguration.CodingKeys.meetingConfidenceThreshold.rawValue)
        if rawThreshold != 0 {
            configuration.meetingConfidenceThreshold = rawThreshold
        }
        let rawInterval = userDefaults.double(forKey: AppConfiguration.CodingKeys.meetingPollIntervalSeconds.rawValue)
        if rawInterval > 0 {
            configuration.meetingPollIntervalSeconds = rawInterval
        }
        
        // Load calendar filtering settings
        if let enabledCalendars = userDefaults.array(forKey: AppConfiguration.CodingKeys.enabledCalendarTitles.rawValue) as? [String] {
            configuration.enabledCalendarTitles = enabledCalendars
        }
        
        // Load hotkey bindings
        if let savedBindings = userDefaults.dictionary(forKey: AppConfiguration.CodingKeys.hotkeyBindings.rawValue) as? [String: NSNumber] {
            var bindings: [String: UInt16] = [:]
            for (state, keyCode) in savedBindings {
                bindings[state] = keyCode.uint16Value
            }
            if !bindings.isEmpty {
                // Detect old function key bindings (F13=105, F14=107, F15=113, F16=106, F17=64)
                // and reset to new Ctrl+Cmd bindings if found
                let oldFunctionKeyCodes: Set<UInt16> = [105, 107, 113, 106, 64]
                let hasOldBindings = bindings.values.contains { oldFunctionKeyCodes.contains($0) }
                
                if hasOldBindings {
                    configLogger.logEvent("Detected old function key bindings, resetting to new Ctrl+Cmd defaults")
                    resetHotkeysToDefaults()
                } else {
                    configuration.hotkeyBindings = bindings
                }
            }
        }
        
        configLogger.logEvent("Configuration loaded successfully",
                            details: ["presenceState": configuration.presenceState.rawValue,
                        "deviceAddress": configuration.deviceNetworkAddress.isEmpty ? "(not set)" : configuration.deviceNetworkAddress,
                        "deviceAddresses": configuration.deviceNetworkAddresses.isEmpty ? "(none)" : configuration.deviceNetworkAddresses.joined(separator: ","),
                                    "hotkeyBindingsCount": String(configuration.hotkeyBindings.count)])
    }
    
    /// Saves current configuration to UserDefaults.
    public func saveConfiguration() {
        configLogger.logEvent("Saving configuration",
                            details: ["presenceState": configuration.presenceState.rawValue])
        
        userDefaults.set(configuration.presenceState.rawValue, forKey: AppConfiguration.CodingKeys.presenceState.rawValue)
        userDefaults.set(configuration.deviceNetworkAddress, forKey: AppConfiguration.CodingKeys.deviceNetworkAddress.rawValue)
        userDefaults.set(configuration.deviceNetworkPort, forKey: AppConfiguration.CodingKeys.deviceNetworkPort.rawValue)
        userDefaults.set(configuration.deviceNetworkAddresses, forKey: AppConfiguration.CodingKeys.deviceNetworkAddresses.rawValue)
        
        // Save WLED configuration
        userDefaults.set(configuration.wledPresetAvailable, forKey: AppConfiguration.CodingKeys.wledPresetAvailable.rawValue)
        userDefaults.set(configuration.wledPresetTentative, forKey: AppConfiguration.CodingKeys.wledPresetTentative.rawValue)
        userDefaults.set(configuration.wledPresetBusy, forKey: AppConfiguration.CodingKeys.wledPresetBusy.rawValue)
        userDefaults.set(configuration.wledPresetAway, forKey: AppConfiguration.CodingKeys.wledPresetAway.rawValue)
        userDefaults.set(configuration.wledPresetUnknown, forKey: AppConfiguration.CodingKeys.wledPresetUnknown.rawValue)
        userDefaults.set(configuration.wledPresetOff, forKey: AppConfiguration.CodingKeys.wledPresetOff.rawValue)
        userDefaults.set(configuration.wledHttpTimeout, forKey: AppConfiguration.CodingKeys.wledHttpTimeout.rawValue)
        userDefaults.set(configuration.wledHealthCheckInterval, forKey: AppConfiguration.CodingKeys.wledHealthCheckInterval.rawValue)
        userDefaults.set(configuration.wledEnableDiscovery, forKey: AppConfiguration.CodingKeys.wledEnableDiscovery.rawValue)
        
        userDefaults.set(configuration.launchOnStartup, forKey: AppConfiguration.CodingKeys.launchOnStartup.rawValue)
        userDefaults.set(configuration.showMenuBarText, forKey: AppConfiguration.CodingKeys.showMenuBarText.rawValue)
        
        // State machine settings (use -1 to represent nil for timeout)
        let timeoutValue = configuration.manualOverrideTimeoutMinutes ?? -1
        userDefaults.set(timeoutValue, forKey: AppConfiguration.CodingKeys.manualOverrideTimeoutMinutes.rawValue)
        userDefaults.set(configuration.stateStabilizationSeconds, forKey: AppConfiguration.CodingKeys.stateStabilizationSeconds.rawValue)
        
        // Save hotkey bindings
        let bindingsDict = configuration.hotkeyBindings.mapValues { NSNumber(value: $0) }
        userDefaults.set(bindingsDict, forKey: AppConfiguration.CodingKeys.hotkeyBindings.rawValue)

        // Save meeting detection settings
        userDefaults.set(configuration.meetingDetectionEnabled, forKey: AppConfiguration.CodingKeys.meetingDetectionEnabled.rawValue)
        userDefaults.set(configuration.meetingProviderZoomEnabled, forKey: AppConfiguration.CodingKeys.meetingProviderZoomEnabled.rawValue)
        userDefaults.set(configuration.meetingProviderTeamsEnabled, forKey: AppConfiguration.CodingKeys.meetingProviderTeamsEnabled.rawValue)
        userDefaults.set(configuration.meetingProviderBrowserEnabled, forKey: AppConfiguration.CodingKeys.meetingProviderBrowserEnabled.rawValue)
        userDefaults.set(configuration.meetingConfidenceThreshold, forKey: AppConfiguration.CodingKeys.meetingConfidenceThreshold.rawValue)
        userDefaults.set(configuration.meetingPollIntervalSeconds, forKey: AppConfiguration.CodingKeys.meetingPollIntervalSeconds.rawValue)
        
        // Save calendar filtering settings
        userDefaults.set(configuration.enabledCalendarTitles, forKey: AppConfiguration.CodingKeys.enabledCalendarTitles.rawValue)
        
        userDefaults.synchronize()
        configLogger.logEvent("Configuration saved", details: [
            "hotkeyBindingsCount": String(configuration.hotkeyBindings.count),
            "deviceAddresses": configuration.deviceNetworkAddresses.isEmpty ? "(none)" : configuration.deviceNetworkAddresses.joined(separator: ",")
        ])
    }
    
    // MARK: - Configuration Access
    
    public func getPresenceState() -> PresenceState {
        return configuration.presenceState
    }
    
    public func setPresenceState(_ state: PresenceState) {
        configuration.presenceState = state
        saveConfiguration()
    }
    
    public func getDeviceNetworkAddress() -> String {
        return configuration.deviceNetworkAddress
    }
    
    public func setDeviceNetworkAddress(_ address: String) {
        let previous = configuration.deviceNetworkAddress
        configuration.deviceNetworkAddress = address
        saveConfiguration()
        configLogger.logEvent("device.address.updated", details: [
            "previous": previous.isEmpty ? "(none)" : previous,
            "new": address.isEmpty ? "(none)" : address
        ])
    }
    
    public func getDeviceNetworkPort() -> Int {
        return 80
    }
    
    public func setDeviceNetworkPort(_ port: Int) {
        configuration.deviceNetworkPort = 80
        saveConfiguration()
    }
    
    public func getDeviceNetworkAddresses() -> [String] {
        return configuration.deviceNetworkAddresses
    }
    
    public func setDeviceNetworkAddresses(_ addresses: [String]) {
        let previous = configuration.deviceNetworkAddresses
        configuration.deviceNetworkAddresses = addresses
        saveConfiguration()
        configLogger.logEvent("device.addresses.updated", details: [
            "previous": previous.isEmpty ? "(none)" : previous.joined(separator: ","),
            "new": addresses.isEmpty ? "(none)" : addresses.joined(separator: ",")
        ])
    }
    
    // MARK: - WLED Configuration
    
    public func getWledPresetAvailable() -> Int {
        return configuration.wledPresetAvailable
    }
    
    public func setWledPresetAvailable(_ presetId: Int) {
        configuration.wledPresetAvailable = presetId
        saveConfiguration()
    }
    
    public func getWledPresetTentative() -> Int {
        return configuration.wledPresetTentative
    }
    
    public func setWledPresetTentative(_ presetId: Int) {
        configuration.wledPresetTentative = presetId
        saveConfiguration()
    }
    
    public func getWledPresetBusy() -> Int {
        return configuration.wledPresetBusy
    }
    
    public func setWledPresetBusy(_ presetId: Int) {
        configuration.wledPresetBusy = presetId
        saveConfiguration()
    }
    
    public func getWledPresetAway() -> Int {
        return configuration.wledPresetAway
    }
    
    public func setWledPresetAway(_ presetId: Int) {
        configuration.wledPresetAway = presetId
        saveConfiguration()
    }
    
    public func getWledPresetUnknown() -> Int {
        return configuration.wledPresetUnknown
    }
    
    public func setWledPresetUnknown(_ presetId: Int) {
        configuration.wledPresetUnknown = presetId
        saveConfiguration()
    }
    
    public func getWledPresetOff() -> Int {
        return configuration.wledPresetOff
    }
    
    public func setWledPresetOff(_ presetId: Int) {
        configuration.wledPresetOff = presetId
        saveConfiguration()
    }
    
    public func getWledHttpTimeout() -> Int {
        return configuration.wledHttpTimeout
    }
    
    public func setWledHttpTimeout(_ milliseconds: Int) {
        configuration.wledHttpTimeout = milliseconds
        saveConfiguration()
    }
    
    public func getWledHealthCheckInterval() -> Int {
        return configuration.wledHealthCheckInterval
    }
    
    public func setWledHealthCheckInterval(_ seconds: Int) {
        configuration.wledHealthCheckInterval = seconds
        saveConfiguration()
    }
    
    public func getWledEnableDiscovery() -> Bool {
        return configuration.wledEnableDiscovery
    }
    
    public func setWledEnableDiscovery(_ enabled: Bool) {
        configuration.wledEnableDiscovery = enabled
        saveConfiguration()
    }
    
    /// Returns the WLED preset ID for a given presence state.
    public func getWledPreset(for state: PresenceState) -> Int {
        switch state {
        case .available:
            return configuration.wledPresetAvailable
        case .tentative:
            return configuration.wledPresetTentative
        case .busy:
            return configuration.wledPresetBusy
        case .away:
            return configuration.wledPresetAway
        case .unknown:
            return configuration.wledPresetUnknown
        case .off:
            return configuration.wledPresetOff
        }
    }
    
    public func getLaunchOnStartup() -> Bool {
        return configuration.launchOnStartup
    }
    
    public func setLaunchOnStartup(_ launch: Bool) {
        configuration.launchOnStartup = launch
        saveConfiguration()
    }
    
    public func getShowMenuBarText() -> Bool {
        return configuration.showMenuBarText
    }
    
    // MARK: - State Machine Configuration
    
    public func getManualOverrideTimeoutMinutes() -> Int? {
        return configuration.manualOverrideTimeoutMinutes
    }
    
    public func setManualOverrideTimeoutMinutes(_ minutes: Int?) {
        configuration.manualOverrideTimeoutMinutes = minutes
        saveConfiguration()
    }
    
    public func getStateStabilizationSeconds() -> Int {
        return configuration.stateStabilizationSeconds
    }
    
    public func setStateStabilizationSeconds(_ seconds: Int) {
        configuration.stateStabilizationSeconds = seconds
        saveConfiguration()
    }
    
    public func setShowMenuBarText(_ show: Bool) {
        configuration.showMenuBarText = show
        saveConfiguration()
    }
    
    // MARK: - Hotkey Configuration
    
    /// Resets hotkey bindings to default Ctrl+Cmd values and saves to UserDefaults.
    /// Called when old function key bindings are detected.
    public func resetHotkeysToDefaults() {
        configuration.hotkeyBindings = AppConfiguration.defaultConfiguration.hotkeyBindings
        
        // Save the reset bindings back to UserDefaults
        let bindingsDict = configuration.hotkeyBindings.mapValues { NSNumber(value: $0) }
        userDefaults.set(bindingsDict, forKey: AppConfiguration.CodingKeys.hotkeyBindings.rawValue)
        userDefaults.synchronize()
        
        configLogger.logEvent("resetHotkeysToDefaults", details: [
            "bindingsCount": String(configuration.hotkeyBindings.count),
            "bindings": configuration.hotkeyBindings.description
        ])
    }
    
    /// Retrieves the current hotkey bindings (state -> key code mapping).
    /// Returns default bindings if none have been configured.
    public func getHotkeyBindings() -> [PresenceState: UInt16] {
        var result: [PresenceState: UInt16] = [:]
        for (stateString, keyCode) in configuration.hotkeyBindings {
            if let state = PresenceState(rawValue: stateString) {
                result[state] = keyCode
            }
        }
        return result
    }
    
    /// Updates hotkey bindings and persists to UserDefaults.
    public func setHotkeyBindings(_ bindings: [PresenceState: UInt16]) {
        var stringKeyedBindings: [String: UInt16] = [:]
        for (state, keyCode) in bindings {
            stringKeyedBindings[state.rawValue] = keyCode
        }
        configuration.hotkeyBindings = stringKeyedBindings
        saveConfiguration()
        
        configLogger.logEvent("hotkey.bindings.saved", details: [
            "bindingsCount": String(bindings.count)
        ])
    }

    // MARK: - Meeting Detection Configuration

    public func getMeetingDetectionEnabled() -> Bool {
        return configuration.meetingDetectionEnabled
    }

    public func setMeetingDetectionEnabled(_ enabled: Bool) {
        configuration.meetingDetectionEnabled = enabled
        saveConfiguration()
    }

    public func getMeetingProviderZoomEnabled() -> Bool {
        return configuration.meetingProviderZoomEnabled
    }

    public func setMeetingProviderZoomEnabled(_ enabled: Bool) {
        configuration.meetingProviderZoomEnabled = enabled
        saveConfiguration()
    }

    public func getMeetingProviderTeamsEnabled() -> Bool {
        return configuration.meetingProviderTeamsEnabled
    }

    public func setMeetingProviderTeamsEnabled(_ enabled: Bool) {
        configuration.meetingProviderTeamsEnabled = enabled
        saveConfiguration()
    }

    public func getMeetingProviderBrowserEnabled() -> Bool {
        return configuration.meetingProviderBrowserEnabled
    }

    public func setMeetingProviderBrowserEnabled(_ enabled: Bool) {
        configuration.meetingProviderBrowserEnabled = enabled
        saveConfiguration()
    }

    public func getMeetingConfidenceThreshold() -> MeetingConfidence {
        return MeetingConfidence(rawValue: configuration.meetingConfidenceThreshold) ?? .high
    }

    public func setMeetingConfidenceThreshold(_ threshold: MeetingConfidence) {
        configuration.meetingConfidenceThreshold = threshold.rawValue
        saveConfiguration()
    }

    public func getMeetingPollIntervalSeconds() -> Double {
        return configuration.meetingPollIntervalSeconds
    }

    public func setMeetingPollIntervalSeconds(_ seconds: Double) {
        configuration.meetingPollIntervalSeconds = max(1.0, seconds)
        saveConfiguration()
    }    
    // MARK: - Calendar Filtering
    
    public func getEnabledCalendarTitles() -> [String] {
        return configuration.enabledCalendarTitles
    }
    
    public func setEnabledCalendarTitles(_ titles: [String]) {
        configuration.enabledCalendarTitles = titles
        saveConfiguration()
    }}
