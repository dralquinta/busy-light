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
    private var turnOffMenuItem: NSMenuItem?
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

    /// Called when the user selects "Turn Off BusyLight" to suspend all syncing.
    public var onTurnOff: (@MainActor () -> Void)?

    /// Called when the user selects a new override timeout. Passes `nil` for "Never".
    public var onTimeoutChanged: (@MainActor (Int?) -> Void)?

    /// Called when the user wants to see hotkey debug information
    public var onShowHotkeyDebugInfo: (@MainActor () -> String)?

    /// Items in the Override Timeout submenu — kept for checkmark updates.
    private var timeoutMenuItems: [NSMenuItem] = []

    /// Timeout options shown in the menu: (label, minutes — nil means never)
    private let timeoutOptions: [(label: String, minutes: Int?)] = [
        ("15 minutes",  15),
        ("30 minutes",  30),
        ("60 minutes",  60),
        ("2 hours",    120),
        ("4 hours",    240),
        ("Never",      nil)
    ]
    
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

        // Turn Off item — suspends all syncing, visible in auto/manual mode
        turnOffMenuItem = NSMenuItem(title: "Turn Off BusyLight",
                                     action: #selector(turnOffSystem),
                                     keyEquivalent: "")
        turnOffMenuItem?.target = self
        menu.addItem(turnOffMenuItem!)
        
        // Device status
        deviceStatusItem = NSMenuItem(title: "Device: Disconnected", action: nil, keyEquivalent: "")
        menu.addItem(deviceStatusItem!)

        // Calendar engine status
        calendarStatusItem = NSMenuItem(title: "Calendar: Starting…", action: nil, keyEquivalent: "")
        menu.addItem(calendarStatusItem!)
        
        menu.addItem(NSMenuItem.separator())

        // Override Timeout submenu
        let timeoutMenu = NSMenu(title: "Override Timeout")
        timeoutMenuItems = timeoutOptions.map { option in
            let item = NSMenuItem(
                title: option.label,
                action: #selector(selectOverrideTimeout(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = option.minutes as AnyObject?
            timeoutMenu.addItem(item)
            return item
        }
        let timeoutParent = NSMenuItem(title: "Override Timeout", action: nil, keyEquivalent: "")
        timeoutParent.submenu = timeoutMenu
        menu.addItem(timeoutParent)

        menu.addItem(NSMenuItem.separator())

        // Debug submenu — helps verify away/return and manual override transitions without locking
        let debugMenu = NSMenu(title: "Debug")

        let scanNowItem = NSMenuItem(title: "Scan Calendar Now",
                                     action: #selector(scanCalendarNow), keyEquivalent: "")
        scanNowItem.target = self
        debugMenu.addItem(scanNowItem)

        debugMenu.addItem(NSMenuItem.separator())

        // Hotkey manager debug info
        let hotkeyDebugItem = NSMenuItem(title: "Hotkey Debug Info",
                                         action: #selector(showHotkeyDebugInfo),
                                         keyEquivalent: "")
        hotkeyDebugItem.target = self
        debugMenu.addItem(hotkeyDebugItem)

        debugMenu.addItem(NSMenuItem.separator())

        // System away simulation
        let simulateAwayItem = NSMenuItem(title: "Simulate Screen Lock (Away)",
                                          action: #selector(simulateAway), keyEquivalent: "")
        simulateAwayItem.target = self
        debugMenu.addItem(simulateAwayItem)

        let simulateReturnItem = NSMenuItem(title: "Simulate Screen Unlock (Return)",
                                            action: #selector(simulateReturn), keyEquivalent: "")
        simulateReturnItem.target = self
        debugMenu.addItem(simulateReturnItem)

        debugMenu.addItem(NSMenuItem.separator())

        // Manual override simulation submenu
        let overrideMenu = NSMenu(title: "Simulate Manual Override")

        for state in [PresenceState.available, .busy, .tentative, .away] {
            let item = NSMenuItem(
                title: "Override → \(state.displayName)",
                action: #selector(simulateManualOverride(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = state.rawValue
            overrideMenu.addItem(item)
        }

        overrideMenu.addItem(NSMenuItem.separator())

        let clearOverrideItem = NSMenuItem(title: "Clear Override (Resume Calendar)",
                                            action: #selector(simulateClearOverride), keyEquivalent: "")
        clearOverrideItem.target = self
        overrideMenu.addItem(clearOverrideItem)

        let overrideParent = NSMenuItem(title: "Simulate Manual Override", action: nil, keyEquivalent: "")
        overrideParent.submenu = overrideMenu
        debugMenu.addItem(overrideParent)

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

        // Reflect the persisted timeout in the checkmarks
        refreshTimeoutCheckmarks(current: ConfigurationManager.shared.getManualOverrideTimeoutMinutes())
    }

    /// Updates checkmarks in the Override Timeout submenu to reflect `current`.
    public func refreshTimeoutCheckmarks(current: Int?) {
        for item in timeoutMenuItems {
            let itemMinutes = item.representedObject as? Int
            item.state = (itemMinutes == current) ? .on : .off
        }
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
        switch mode {
        case .off:
            calendarStatusItem?.title = "Calendar: Disabled"
            resumeCalendarItem?.isHidden = false
            turnOffMenuItem?.isHidden = true
        case .manual:
            calendarStatusItem?.title = "Calendar: Overridden"
            resumeCalendarItem?.isHidden = false
            turnOffMenuItem?.isHidden = false
        case .auto:
            // Show "Resuming…" until the first calendar scan delivers a result
            calendarStatusItem?.title = "Calendar: Resuming…"
            resumeCalendarItem?.isHidden = true
            turnOffMenuItem?.isHidden = false
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
    
    /// Updates device status display for multiple WLED devices.
    public func updateDeviceList(_ devices: [WLEDDevice]) {
        let onlineCount = devices.filter { $0.isOnline }.count
        let offlineCount = devices.count - onlineCount
        
        let statusText: String
        if devices.isEmpty {
            statusText = "Devices: None configured"
        } else if offlineCount == 0 {
            statusText = "Devices: \(onlineCount) online ●"
        } else if onlineCount == 0 {
            statusText = "Devices: All offline"
        } else {
            statusText = "Devices: \(onlineCount) online, \(offlineCount) offline"
        }
        
        deviceStatusItem?.title = statusText
        
        // Build tooltip with individual device details
        var tooltip = "WLED Devices:\n"
        if devices.isEmpty {
            tooltip += "  No devices configured\n"
            tooltip += "  Configure via UserDefaults or enable discovery"
        } else {
            for device in devices {
                let status = device.isOnline ? "●" : "○"
                let name = device.name ?? device.address
                tooltip += "  \(status) \(name) (\(device.address):\(device.port))\n"
            }
        }
        
        deviceStatusItem?.toolTip = tooltip
        
        uiLogger.logEvent("Device list updated", details: [
            "total": String(devices.count),
            "online": String(onlineCount),
            "offline": String(offlineCount)
        ])
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
        case .off:
            button.title = "⬛"
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

    @objc private func turnOffSystem() {
        onTurnOff?()
        uiLogger.logEvent("system.off.requested", details: ["source": "menu"])
    }

    @objc private func simulateAway() {
        onSimulateAway?()
    }

    @objc private func simulateReturn() {
        onSimulateReturn?()
    }

    @objc private func selectOverrideTimeout(_ sender: NSMenuItem) {
        // representedObject is nil for "Never", or an Int for a minute count
        let minutes = sender.representedObject as? Int
        refreshTimeoutCheckmarks(current: minutes)
        onTimeoutChanged?(minutes)
        uiLogger.logEvent("override.timeout.changed", details: [
            "minutes": minutes.map { String($0) } ?? "never"
        ])
    }

    @objc private func simulateManualOverride(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let state = PresenceState(rawValue: rawValue) else { return }
        onManualOverride?(state)
        uiLogger.logEvent("debug.manual.override.simulated", details: ["state": state.rawValue])
    }

    @objc private func simulateClearOverride() {
        onResumeCalendarControl?()
        uiLogger.logEvent("debug.manual.override.cleared")
    }

    @objc private func scanCalendarNow() {
        calendarStatusItem?.title = "Calendar: Scanning…"
        onScanNow?()
        uiLogger.logEvent("calendar.scan.manual", details: ["source": "debug_menu"])
    }

    @objc private func openPreferences() {
        uiLogger.logEvent("Preferences requested (not yet implemented)")
    }



    @objc private func showHotkeyDebugInfo() {
        guard let debugInfo = onShowHotkeyDebugInfo?() else {
            uiLogger.logEvent("Hotkey debug info not available")
            return
        }
        
        // Log the debug info
        uiLogger.logEvent("hotkey.debug.info", details: ["info": debugInfo])
        
        // Show in a simple alert
        let alert = NSAlert()
        alert.messageText = "Hotkey Manager Debug Info"
        alert.informativeText = debugInfo
        alert.addButton(withTitle: "OK")
        alert.alertStyle = .informational
        alert.runModal()
    }

    @objc private func quitApp() {
        uiLogger.logEvent("Quit requested from menu")
        lifecycleLogger.logEvent("Application shutting down via menu")
        NSApplication.shared.terminate(nil)
    }
    

}
