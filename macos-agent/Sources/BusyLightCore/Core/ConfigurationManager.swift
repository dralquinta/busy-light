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
        
        configLogger.logEvent("Configuration loaded successfully",
                            details: ["presenceState": configuration.presenceState.rawValue,
                                    "deviceAddress": configuration.deviceNetworkAddress.isEmpty ? "(not set)" : configuration.deviceNetworkAddress])
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
        
        userDefaults.synchronize()
        configLogger.logEvent("Configuration saved")
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
    
    public func setShowMenuBarText(_ show: Bool) {
        configuration.showMenuBarText = show
        saveConfiguration()
    }
}
