import Foundation

/// Configuration settings persisted via UserDefaults.
public struct AppConfiguration: Codable, Sendable {
    public var presenceState: PresenceState = .available
    public var deviceNetworkAddress: String = ""
    public var deviceNetworkPort: Int = 8080
    public var launchOnStartup: Bool = false
    public var showMenuBarText: Bool = true
    
    // State machine configuration
    /// Manual override timeout in minutes (nil = no timeout, default 120 minutes)
    public var manualOverrideTimeoutMinutes: Int? = 120
    /// State stabilization delay in seconds to prevent flapping (default 0 = disabled)
    public var stateStabilizationSeconds: Int = 0
    
    public static let defaultConfiguration = AppConfiguration()
    
    public init() {}
    
    public enum CodingKeys: String, CodingKey {
        case presenceState = "app.presence_state"
        case deviceNetworkAddress = "app.device_network_address"
        case deviceNetworkPort = "app.device_network_port"
        case launchOnStartup = "app.launch_on_startup"
        case showMenuBarText = "app.show_menu_bar_text"
        case manualOverrideTimeoutMinutes = "app.manual_override_timeout"
        case stateStabilizationSeconds = "app.state_stabilization"
    }
}
