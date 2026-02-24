import Foundation

/// Configuration settings persisted via UserDefaults.
public struct AppConfiguration: Codable, Sendable {
    public var presenceState: PresenceState = .available
    
    // Legacy network configuration (deprecated, use deviceNetworkAddresses)
    public var deviceNetworkAddress: String = ""
    public var deviceNetworkPort: Int = 80  // WLED default port
    
    // Network configuration
    /// Multiple device IP addresses for broadcasting presence state
    public var deviceNetworkAddresses: [String] = []
    
    // WLED configuration
    /// WLED preset ID for Available state (default: 1)
    public var wledPresetAvailable: Int = 1
    /// WLED preset ID for Tentative state (default: 2)
    public var wledPresetTentative: Int = 2
    /// WLED preset ID for Busy state (default: 3)
    public var wledPresetBusy: Int = 3
    /// WLED preset ID for Away state (default: 4)
    public var wledPresetAway: Int = 4
    /// WLED preset ID for Unknown state (default: 5)
    public var wledPresetUnknown: Int = 5
    /// WLED preset ID for Off state (default: 6)
    public var wledPresetOff: Int = 6
    /// HTTP request timeout in milliseconds (default: 500ms)
    public var wledHttpTimeout: Int = 500
    /// Health check polling interval in seconds (default: 10s)
    public var wledHealthCheckInterval: Int = 10
    /// Enable Bonjour/mDNS device discovery (default: true)
    public var wledEnableDiscovery: Bool = true
    
    // UI configuration
    public var launchOnStartup: Bool = false
    public var showMenuBarText: Bool = true
    
    // State machine configuration
    /// Manual override timeout in minutes (nil = no timeout, default 30 minutes)
    public var manualOverrideTimeoutMinutes: Int? = 30
    /// State stabilization delay in seconds to prevent flapping (default 0 = disabled)
    public var stateStabilizationSeconds: Int = 0
    /// Hotkey bindings: maps presence states to Carbon virtual key codes
    /// Control+Cmd combinations: 1=available, 2=tentative, 3=busy, 6=away
    /// Defaults: Ctrl+Cmd+1=available, Ctrl+Cmd+2=tentative, Ctrl+Cmd+3=busy, Ctrl+Cmd+6=away
    /// Ctrl+Cmd+4 and Ctrl+Cmd+5 are handled separately (resume calendar and turn off)
    public var hotkeyBindings: [String: UInt16] = [
        PresenceState.available.rawValue: 18,    // 1 key (with modifiers: Control + Cmd)
        PresenceState.tentative.rawValue: 19,   // 2 key (with modifiers: Control + Cmd)
        PresenceState.busy.rawValue: 20,        // 3 key (with modifiers: Control + Cmd)
        PresenceState.away.rawValue: 22,        // 6 key (with modifiers: Control + Cmd)
    ]
    
    // MARK: - Meeting Detection Configuration

    /// Enable/disable unscheduled meeting detection (default: true)
    public var meetingDetectionEnabled: Bool = true
    /// Enable Zoom native-app detection (default: true)
    public var meetingProviderZoomEnabled: Bool = true
    /// Enable Microsoft Teams native-app detection (default: true)
    public var meetingProviderTeamsEnabled: Bool = true
    /// Enable Google Meet / Teams web / Zoom web browser detection (default: true)
    public var meetingProviderBrowserEnabled: Bool = true
    /// Minimum confidence threshold — meetings below this level are ignored.
    /// Stored as raw Int (MeetingConfidence.rawValue). Default: 3 (high).
    public var meetingConfidenceThreshold: Int = 3
    /// How often the meeting detectors are polled, in seconds (default: 3)
    public var meetingPollIntervalSeconds: Double = 3.0
    
    public init() {}
    
    public enum CodingKeys: String, CodingKey {
        case presenceState = "app.presence_state"
        case deviceNetworkAddress = "app.device_network_address"
        case deviceNetworkPort = "app.device_network_port"
        case deviceNetworkAddresses = "app.device_network_addresses"
        case wledPresetAvailable = "app.wled_preset_available"
        case wledPresetTentative = "app.wled_preset_tentative"
        case wledPresetBusy = "app.wled_preset_busy"
        case wledPresetAway = "app.wled_preset_away"
        case wledPresetUnknown = "app.wled_preset_unknown"
        case wledPresetOff = "app.wled_preset_off"
        case wledHttpTimeout = "app.wled_http_timeout"
        case wledHealthCheckInterval = "app.wled_health_check_interval"
        case wledEnableDiscovery = "app.wled_enable_discovery"
        case launchOnStartup = "app.launch_on_startup"
        case showMenuBarText = "app.show_menu_bar_text"
        case manualOverrideTimeoutMinutes = "app.manual_override_timeout"
        case stateStabilizationSeconds = "app.state_stabilization"
        case hotkeyBindings = "app.hotkey_bindings"
        case meetingDetectionEnabled = "app.meeting_detection_enabled"
        case meetingProviderZoomEnabled = "app.meeting_provider_zoom_enabled"
        case meetingProviderTeamsEnabled = "app.meeting_provider_teams_enabled"
        case meetingProviderBrowserEnabled = "app.meeting_provider_browser_enabled"
        case meetingConfidenceThreshold = "app.meeting_confidence_threshold"
        case meetingPollIntervalSeconds = "app.meeting_poll_interval_seconds"
    }
}
