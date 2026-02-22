import Foundation

/// Configuration settings persisted via UserDefaults.
public struct AppConfiguration: Codable, Sendable {
    public var presenceState: PresenceState = .available
    public var deviceNetworkAddress: String = ""
    public var deviceNetworkPort: Int = 8080
    public var launchOnStartup: Bool = false
    public var showMenuBarText: Bool = true
    
    // State machine configuration
    /// Manual override timeout in minutes (nil = no timeout, default 30 minutes)
    public var manualOverrideTimeoutMinutes: Int? = 30
    /// State stabilization delay in seconds to prevent flapping (default 0 = disabled)
    public var stateStabilizationSeconds: Int = 0
    /// Hotkey bindings: maps presence states to Carbon virtual key codes
    /// Control+Cmd combinations: 1=available, 2=tentative, 3=busy
    /// Defaults: Ctrl+Cmd+1=available, Ctrl+Cmd+2=tentative, Ctrl+Cmd+3=busy, F16=away, F17=off
    public var hotkeyBindings: [String: UInt16] = [
        PresenceState.available.rawValue: 18,    // 1 key (with modifiers: Control + Cmd)
        PresenceState.tentative.rawValue: 19,   // 2 key (with modifiers: Control + Cmd)
        PresenceState.busy.rawValue: 20,        // 3 key (with modifiers: Control + Cmd)
        PresenceState.away.rawValue: 106,        // F16
        PresenceState.off.rawValue: 64           // F17
    ]
    
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
        case hotkeyBindings = "app.hotkey_bindings"
    }
}
