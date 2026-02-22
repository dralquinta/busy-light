import AppKit

/// Manages the menu bar status icon and dropdown menu.
/// Isolated to @MainActor because all NSStatusBar and menu operations must run on the main thread.
@MainActor
public class StatusMenuController {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var statusText: NSMenuItem?
    private var toggleMenuItem: NSMenuItem?
    private var resumeCalendarItem: NSMenuItem?
    private var deviceStatusItem: NSMenuItem?
    private var calendarStatusItem: NSMenuItem?

    /// The state currently shown in the menu bar icon and status text.
    private var currentDisplayState: PresenceState = .available

    /// Current operating mode (auto = calendar-driven, manual = user override)
    private var currentMode: OperatingMode = .auto

    /// Called when the user taps "Resume Calendar Control" so the app can
    /// trigger an immediate calendar rescan.
    public var onResumeCalendarControl: (@MainActor () -> Void)?
    
    /// Called when the user manually overrides the presence state
    public var onManualOverride: (@MainActor (PresenceState) -> Void)?

    /// Called when the user taps "Simulate Away" in the debug menu.
    public var onSimulateAway: (@MainActor () -> Void)?

    /// Called when the user taps "Simulate Return" in the debug menu.
    public var onSimulateReturn: (@MainActor () -> Void)?

    /// Called when the user taps "Scan Calendar Now" in the debug menu.
    public var onScanNow: (@MainActor () -> Void)?
    
    public init() {
        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        // Set initial button appearance with semaphore icon
        if let button = statusItem.button {
            button.title = "🟢"  // Green circle for available
            button.font = NSFont.systemFont(ofSize: 14)
        }
        
        statusItem.menu = menu
        
        uiLogger.logEvent("StatusMenuController initialized")
        
        setupMenu()
        updateMenuAppearance()
    }
    
    private func setupMenu() {
        // Status display (read-only)
        statusText = NSMenuItem(title: "Status: Available", action: nil, keyEquivalent: "")
        menu.addItem(statusText!)
        
        menu.addItem(NSMenuItem.separator())
        
        // Toggle presence state
        toggleMenuItem = NSMenuItem(title: "Mark as Busy", action: #selector(togglePresenceState), keyEquivalent: "")
        toggleMenuItem?.target = self
        menu.addItem(toggleMenuItem!)

        // Resume calendar control (hidden until a manual override is active)
        resumeCalendarItem = NSMenuItem(title: "Resume Calendar Control",
                                        action: #selector(resumeCalendarControl),
                                        keyEquivalent: "")
        resumeCalendarItem?.target = self
        resumeCalendarItem?.isHidden = true
        menu.addItem(resumeCalendarItem!)
        
        // Device status
        deviceStatusItem = NSMenuItem(title: "Device: Disconnected", action: nil, keyEquivalent: "")
        menu.addItem(deviceStatusItem!)

        // Calendar engine status
        calendarStatusItem = NSMenuItem(title: "Calendar: Starting…", action: nil, keyEquivalent: "")
        menu.addItem(calendarStatusItem!)
        
        menu.addItem(NSMenuItem.separator())

        // Debug submenu — helps verify away/return transitions without locking
        let debugMenu = NSMenu(title: "Debug")

        let scanNowItem = NSMenuItem(title: "Scan Calendar Now",
                                     action: #selector(scanCalendarNow), keyEquivalent: "")
        scanNowItem.target = self
        debugMenu.addItem(scanNowItem)

        debugMenu.addItem(NSMenuItem.separator())

        let simulateAwayItem = NSMenuItem(title: "Simulate Screen Lock (Away)",
                                          action: #selector(simulateAway), keyEquivalent: "")
        simulateAwayItem.target = self
        debugMenu.addItem(simulateAwayItem)

        let simulateReturnItem = NSMenuItem(title: "Simulate Screen Unlock (Return)",
                                            action: #selector(simulateReturn), keyEquivalent: "")
        simulateReturnItem.target = self
        debugMenu.addItem(simulateReturnItem)

        let debugParent = NSMenuItem(title: "Debug", action: nil, keyEquivalent: "")
        debugParent.submenu = debugMenu
        menu.addItem(debugParent)

        menu.addItem(NSMenuItem.separator())
        let preferencesItem = NSMenuItem(title: "Preferences", action: #selector(openPreferences), keyEquivalent: ",")
        preferencesItem.target = self
        menu.addItem(preferencesItem)
        
        // Quit
        let quitItem = NSMenuItem(title: "Quit BusyLight", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        uiLogger.logEvent("Menu structure initialized")
    }
    
    public func updatePresenceState(_ state: PresenceState) {
        currentDisplayState = state
        statusText?.title = "Status: \(state.displayName)"

        // Toggle label: always offers the opposite of the current displayed state.
        let toggleTarget: PresenceState = state == .available ? .busy : .available
        let prefix = currentMode == .manual ? "Manually " : ""
        toggleMenuItem?.title = "\(prefix)Mark as \(toggleTarget.displayName)"

        // Update button icon color based on state
        updateButtonAppearance(for: state)

        uiLogger.logEvent("Presence state updated", details: ["state": state.rawValue])
    }
    
    /// Called by the state machine when operating mode changes
    public func updateModeDisplay(_ mode: OperatingMode) {
        currentMode = mode
        
        // Update UI elements based on mode
        if mode == .manual {
            calendarStatusItem?.title = "Calendar: Overridden"
            resumeCalendarItem?.isHidden = false
        } else {
            calendarStatusItem?.title = "Calendar: Active"
            resumeCalendarItem?.isHidden = true
        }
        
        // Update toggle button prefix
        let toggleTarget: PresenceState = currentDisplayState == .available ? .busy : .available
        let prefix = mode == .manual ? "Manually " : ""
        toggleMenuItem?.title = "\(prefix)Mark as \(toggleTarget.displayName)"
        
        uiLogger.logEvent("Mode display updated", details: ["mode": mode.rawValue])
    }

    /// Called by `SystemPresenceMonitor` when the screen locks or the system sleeps.
    /// Forces the icon and menu to `.away` regardless of the current calendar state.
    /// DEPRECATED: State machine now handles this via .systemAway event
    public func applyAwayState() {
        calendarStatusItem?.title = "Calendar: Paused (screen locked)"
        updatePresenceState(.away)
        updateButtonAppearance(for: .away)
        uiLogger.logEvent("system.presence.away.applied")
    }

    /// Called by `SystemPresenceMonitor` when the user returns.
    /// Clears the away override so the next calendar scan can restore the real icon.
    /// DEPRECATED: State machine now handles this via .systemReturned event
    public func clearAwayState() {
        currentMode = .auto
        resumeCalendarItem?.isHidden = true
        calendarStatusItem?.title = "Calendar: Resuming…"
        uiLogger.logEvent("system.presence.away.cleared")
    }

    /// Called by the calendar engine whenever it resolves a new availability state.
    /// Updates the UI and marks state as calendar-driven.
    /// DEPRECATED: State machine now handles this via .calendarUpdated event
    public func applyCalendarState(_ state: PresenceState) {
        currentMode = .auto
        resumeCalendarItem?.isHidden = true
        if state == .available {
            calendarStatusItem?.title = "Calendar: Active"
        } else {
            calendarStatusItem?.title = "Calendar: \(state.displayName) ●"
        }
        updatePresenceState(state)
    }

    /// Called when the calendar engine starts or stops to update the menu label.
    public func setCalendarEngineStatus(_ label: String) {
        calendarStatusItem?.title = "Calendar: \(label)"
    }
    
    public func updateDeviceStatus(_ status: DeviceStatus) {
        deviceStatusItem?.title = "Device: \(status.displayText)"

        if let error = status.errorMessage {
            deviceStatusItem?.title = "Device: \(status.displayText) - \(error)"
        }

        uiLogger.logEvent("Device status updated", details: ["state": status.connectionState.rawValue])
    }

    private func updateMenuAppearance() {
        let config = ConfigurationManager.shared
        let state = config.getPresenceState()
        updatePresenceState(state)

        // Initialize device status as disconnected (will be updated later)
        let initialStatus = DeviceStatus(connectionState: .disconnected)
        updateDeviceStatus(initialStatus)
    }

    private func updateButtonAppearance(for state: PresenceState) {
        guard let button = statusItem.button else { return }

        switch state {
        case .available:
            button.title = "🟢"
        case .busy:
            button.title = "🔴"
        case .away:
            button.title = "⚪"
        case .tentative:
            button.title = "🟠"
        case .unknown:
            button.title = "⚫"
        }
    }

    // MARK: - Action Handlers

    @objc private func togglePresenceState() {
        let newState: PresenceState = currentDisplayState == .available ? .busy : .available
        onManualOverride?(newState)
        uiLogger.logEvent("Presence state toggle requested",
                          details: ["from": currentDisplayState.rawValue, "to": newState.rawValue,
                                    "source": "manual"])
    }

    @objc private func resumeCalendarControl() {
        onResumeCalendarControl?()
        uiLogger.logEvent("calendar.control.resume.requested", details: ["source": "manual"])
    }

    @objc private func simulateAway() {
        onSimulateAway?()
    }

    @objc private func simulateReturn() {
        onSimulateReturn?()
    }

    @objc private func scanCalendarNow() {
        calendarStatusItem?.title = "Calendar: Scanning…"
        onScanNow?()
        uiLogger.logEvent("calendar.scan.manual", details: ["source": "debug_menu"])
    }

    @objc private func openPreferences() {
        uiLogger.logEvent("Preferences requested (not yet implemented)")
    }

    @objc private func quitApp() {
        uiLogger.logEvent("Quit requested from menu")
        lifecycleLogger.logEvent("Application shutting down via menu")
        NSApplication.shared.terminate(nil)
    }
}
