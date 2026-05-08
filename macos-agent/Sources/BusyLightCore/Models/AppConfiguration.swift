import Foundation

/// Simple daily office-hours window used to decide whether automatic presence
/// should communicate to the light or leave it off.
public struct OfficeHoursConfiguration: Codable, Equatable, Sendable {
    private static let weekdayLabels: [(label: String, value: Int)] = [
        ("Sun", 1), ("Mon", 2), ("Tue", 3), ("Wed", 4), ("Thu", 5), ("Fri", 6), ("Sat", 7)
    ]

    public static let defaultConfiguration = OfficeHoursConfiguration(
        isEnabled: true,
        startMinuteOfDay: 9 * 60,
        endMinuteOfDay: 17 * 60,
        activeWeekdays: [2, 3, 4, 5, 6]
    )

    public var isEnabled: Bool = false
    public var startMinuteOfDay: Int = 9 * 60
    public var endMinuteOfDay: Int = 17 * 60
    public var activeWeekdays: Set<Int> = [2, 3, 4, 5, 6]

    public init(
        isEnabled: Bool = false,
        startMinuteOfDay: Int = 9 * 60,
        endMinuteOfDay: Int = 17 * 60,
        activeWeekdays: Set<Int> = [2, 3, 4, 5, 6]
    ) {
        self.isEnabled = isEnabled
        self.startMinuteOfDay = Self.normalizedMinute(startMinuteOfDay)
        self.endMinuteOfDay = Self.normalizedMinute(endMinuteOfDay)
        self.activeWeekdays = Self.normalizedWeekdays(activeWeekdays)
    }

    public func contains(minuteOfDay rawMinuteOfDay: Int) -> Bool {
        guard isEnabled else { return true }

        let minuteOfDay = Self.normalizedMinute(rawMinuteOfDay)
        if startMinuteOfDay == endMinuteOfDay {
            return true
        }

        if startMinuteOfDay < endMinuteOfDay {
            return minuteOfDay >= startMinuteOfDay && minuteOfDay < endMinuteOfDay
        }

        return minuteOfDay >= startMinuteOfDay || minuteOfDay < endMinuteOfDay
    }

    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let weekday = calendar.component(.weekday, from: date)
        let minuteOfDay = (components.hour ?? 0) * 60 + (components.minute ?? 0)

        guard isEnabled else { return true }

        if startMinuteOfDay == endMinuteOfDay {
            return activeWeekdays.contains(weekday)
        }

        if startMinuteOfDay < endMinuteOfDay {
            return activeWeekdays.contains(weekday) && contains(minuteOfDay: minuteOfDay)
        }

        if minuteOfDay >= startMinuteOfDay {
            return activeWeekdays.contains(weekday)
        }

        return minuteOfDay < endMinuteOfDay && activeWeekdays.contains(Self.previousWeekday(before: weekday))
    }

    public static func normalizedMinute(_ minuteOfDay: Int) -> Int {
        return min(max(minuteOfDay, 0), (24 * 60) - 1)
    }

    public static func normalizedWeekdays(_ weekdays: Set<Int>) -> Set<Int> {
        return Set(weekdays.filter { (1...7).contains($0) })
    }

    public var scheduleDescription: String {
        let weekdayPart = Self.weekdayDescription(for: activeWeekdays)
        return "\(weekdayPart) \(Self.formattedMinute(startMinuteOfDay))-\(Self.formattedMinute(endMinuteOfDay))"
    }

    public static func parseSchedule(_ rawValue: String) -> OfficeHoursConfiguration? {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmedValue.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 2,
              let weekdays = parseWeekdays(String(parts[0])),
              let timeRange = parseTimeRange(String(parts[1])) else {
            return nil
        }

        return OfficeHoursConfiguration(
            isEnabled: true,
            startMinuteOfDay: timeRange.start,
            endMinuteOfDay: timeRange.end,
            activeWeekdays: weekdays
        )
    }

    public static func formattedMinute(_ minuteOfDay: Int) -> String {
        let normalized = normalizedMinute(minuteOfDay)
        return String(format: "%02d:%02d", normalized / 60, normalized % 60)
    }

    private static func previousWeekday(before weekday: Int) -> Int {
        return weekday == 1 ? 7 : weekday - 1
    }

    private static func parseWeekdays(_ rawValue: String) -> Set<Int>? {
        let groups = rawValue.split(separator: ",", omittingEmptySubsequences: true)
        guard !groups.isEmpty else { return nil }

        var weekdays = Set<Int>()
        for group in groups {
            let rangeParts = group.split(separator: "-", omittingEmptySubsequences: true)
            if rangeParts.count == 1 {
                guard let weekday = weekdayValue(String(rangeParts[0])) else { return nil }
                weekdays.insert(weekday)
            } else if rangeParts.count == 2 {
                guard let start = weekdayValue(String(rangeParts[0])),
                      let end = weekdayValue(String(rangeParts[1])) else {
                    return nil
                }

                var current = start
                while true {
                    weekdays.insert(current)
                    if current == end { break }
                    current = current == 7 ? 1 : current + 1
                }
            } else {
                return nil
            }
        }

        return weekdays.isEmpty ? nil : weekdays
    }

    private static func parseTimeRange(_ rawValue: String) -> (start: Int, end: Int)? {
        let timeParts = rawValue.split(separator: "-", omittingEmptySubsequences: true)
        guard timeParts.count == 2,
              let start = parseTime(String(timeParts[0])),
              let end = parseTime(String(timeParts[1])) else {
            return nil
        }

        return (start, end)
    }

    private static func parseTime(_ rawValue: String) -> Int? {
        let parts = rawValue.split(separator: ":", omittingEmptySubsequences: true)
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else {
            return nil
        }

        return hour * 60 + minute
    }

    private static func weekdayValue(_ rawValue: String) -> Int? {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return weekdayLabels.first { item in
            item.label.lowercased() == normalized
        }?.value
    }

    private static func weekdayDescription(for weekdays: Set<Int>) -> String {
        let normalizedWeekdays = weekdayLabels.filter { weekdays.contains($0.value) }
        guard !normalizedWeekdays.isEmpty else { return "Mon-Fri" }

        if weekdays == [2, 3, 4, 5, 6] {
            return "Mon-Fri"
        }

        if weekdays == [1, 2, 3, 4, 5, 6, 7] {
            return "Sun-Sat"
        }

        return normalizedWeekdays.map(\.label).joined(separator: ",")
    }
}

/// Configuration settings persisted via UserDefaults.
public struct AppConfiguration: Codable, Sendable {
    public static let minimumWledHttpTimeout = 2_500
    public static let defaultWledHttpTimeout = minimumWledHttpTimeout

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
    /// HTTP request timeout in milliseconds (default: 2500ms)
    public var wledHttpTimeout: Int = defaultWledHttpTimeout
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
    /// Daily office-hours window. When enabled, automatic presence is off outside this window.
    public var officeHours: OfficeHoursConfiguration = .defaultConfiguration
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
    
    // MARK: - Calendar Filtering Configuration
    
    /// List of calendar titles enabled for presence detection
    /// Empty array means all calendars are included (default behavior)
    public var enabledCalendarTitles: [String] = []
    
    public init() {}

    public static func normalizedWledHttpTimeout(_ milliseconds: Int) -> Int {
        let requested = milliseconds > 0 ? milliseconds : defaultWledHttpTimeout
        return max(requested, minimumWledHttpTimeout)
    }
    
    /// Default configuration with all default values
    public static let defaultConfiguration = AppConfiguration()
    
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
        case officeHours = "app.office_hours"
        case hotkeyBindings = "app.hotkey_bindings"
        case meetingDetectionEnabled = "app.meeting_detection_enabled"
        case meetingProviderZoomEnabled = "app.meeting_provider_zoom_enabled"
        case meetingProviderTeamsEnabled = "app.meeting_provider_teams_enabled"
        case meetingProviderBrowserEnabled = "app.meeting_provider_browser_enabled"
        case meetingConfidenceThreshold = "app.meeting_confidence_threshold"
        case meetingPollIntervalSeconds = "app.meeting_poll_interval_seconds"
        case enabledCalendarTitles = "app.enabled_calendar_titles"
    }
}
