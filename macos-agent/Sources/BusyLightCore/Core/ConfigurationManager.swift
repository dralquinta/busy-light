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
        configuration.deviceNetworkPort = userDefaults.integer(forKey: AppConfiguration.CodingKeys.deviceNetworkPort.rawValue)
        if configuration.deviceNetworkPort == 0 {
            configuration.deviceNetworkPort = 8080
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
                                    "hotkeyBindingsCount": String(configuration.hotkeyBindings.count)])
    }
    
    /// Saves current configuration to UserDefaults.
    public func saveConfiguration() {
        configLogger.logEvent("Saving configuration",
                            details: ["presenceState": configuration.presenceState.rawValue])
        
        userDefaults.set(configuration.presenceState.rawValue, forKey: AppConfiguration.CodingKeys.presenceState.rawValue)
        userDefaults.set(configuration.deviceNetworkAddress, forKey: AppConfiguration.CodingKeys.deviceNetworkAddress.rawValue)
        userDefaults.set(configuration.deviceNetworkPort, forKey: AppConfiguration.CodingKeys.deviceNetworkPort.rawValue)
        userDefaults.set(configuration.launchOnStartup, forKey: AppConfiguration.CodingKeys.launchOnStartup.rawValue)
        userDefaults.set(configuration.showMenuBarText, forKey: AppConfiguration.CodingKeys.showMenuBarText.rawValue)
        
        // State machine settings (use -1 to represent nil for timeout)
        let timeoutValue = configuration.manualOverrideTimeoutMinutes ?? -1
        userDefaults.set(timeoutValue, forKey: AppConfiguration.CodingKeys.manualOverrideTimeoutMinutes.rawValue)
        userDefaults.set(configuration.stateStabilizationSeconds, forKey: AppConfiguration.CodingKeys.stateStabilizationSeconds.rawValue)
        
        // Save hotkey bindings
        let bindingsDict = configuration.hotkeyBindings.mapValues { NSNumber(value: $0) }
        userDefaults.set(bindingsDict, forKey: AppConfiguration.CodingKeys.hotkeyBindings.rawValue)
        
        userDefaults.synchronize()
        configLogger.logEvent("Configuration saved", details: ["hotkeyBindingsCount": String(configuration.hotkeyBindings.count)])
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
        configuration.deviceNetworkAddress = address
        saveConfiguration()
    }
    
    public func getDeviceNetworkPort() -> Int {
        return configuration.deviceNetworkPort
    }
    
    public func setDeviceNetworkPort(_ port: Int) {
        configuration.deviceNetworkPort = port
        saveConfiguration()
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
}
