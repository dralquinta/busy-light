import AppKit

/// Manages the menu bar status icon and dropdown menu.
/// Isolated to @MainActor because all NSStatusBar and menu operations must run on the main thread.
@MainActor
public class StatusMenuController {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var statusText: NSMenuItem?
    private var modeMenuItem: NSMenuItem?
    private var autoModeItem: NSMenuItem?
    private var manualModeItem: NSMenuItem?
    private var manualOverrideMenuItem: NSMenuItem?
    private var manualOverrideItems: [NSMenuItem] = []
    private var turnOffMenuItem: NSMenuItem?
    private var deviceStatusItem: NSMenuItem?
    private var deviceConnectedItem: NSMenuItem?
    private var deviceConnectionStatusItem: NSMenuItem?
    private var deviceLastSyncItem: NSMenuItem?
    private var calendarStatusItem: NSMenuItem?
    private var settingsItem: NSMenuItem?
    private var timeoutMenuItem: NSMenuItem?

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

    /// Called when the user configures a device address override.
    public var onConfigureDeviceAddress: (@MainActor (String) -> Void)?
    
    /// Called when the user wants to select which calendars to monitor.
    /// Returns (availableCalendars, currentlyEnabledTitles)
    public var onGetCalendarList: (@MainActor () -> (available: [(title: String, source: String)], enabled: [String]))?
    
    /// Called when the user updates the list of enabled calendars.
    public var onUpdateEnabledCalendars: (@MainActor ([String]) async -> Void)?

    /// Items in the Override Timeout submenu — kept for checkmark updates.
    private var timeoutMenuItems: [NSMenuItem] = []
    
    /// Items in the Calendar submenu — kept for checkmark updates.
    private var calendarMenuItems: [(menuItem: NSMenuItem, title: String)] = []
    private var calendarMenuItem: NSMenuItem?

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

        // Mode selection
        let modeMenu = NSMenu(title: "Mode")

        autoModeItem = NSMenuItem(title: "Automatic", action: #selector(selectAutoMode), keyEquivalent: "")
        autoModeItem?.target = self
        modeMenu.addItem(autoModeItem!)

        manualModeItem = NSMenuItem(title: "Manual Override", action: #selector(selectManualMode), keyEquivalent: "")
        manualModeItem?.target = self
        modeMenu.addItem(manualModeItem!)

        modeMenuItem = NSMenuItem(title: "Mode", action: nil, keyEquivalent: "")
        modeMenuItem?.submenu = modeMenu
        menu.addItem(modeMenuItem!)

        // Manual override actions (shown only in manual mode)
        let manualOverrideMenu = NSMenu(title: "Manual Status")
        let manualStates: [PresenceState] = [.available, .tentative, .busy]
        manualOverrideItems = manualStates.map { state in
            let item = NSMenuItem(
                title: "Set \(state.displayName)",
                action: #selector(setManualOverride(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = state.rawValue
            manualOverrideMenu.addItem(item)
            return item
        }
        manualOverrideMenuItem = NSMenuItem(title: "Manual Status", action: nil, keyEquivalent: "")
        manualOverrideMenuItem?.submenu = manualOverrideMenu
        manualOverrideMenuItem?.isHidden = true
        menu.addItem(manualOverrideMenuItem!)

        // Turn Off item — suspends all syncing, visible in auto/manual mode
        turnOffMenuItem = NSMenuItem(title: "Turn Off BusyLight",
                                     action: #selector(turnOffSystem),
                                     keyEquivalent: "")
        turnOffMenuItem?.target = self
        menu.addItem(turnOffMenuItem!)
        
        // Resume Calendar Control - useful when browser meeting tab is still open but meeting has ended
        let resumeCalendarItem = NSMenuItem(title: "Resume Calendar Control",
                                           action: #selector(resumeCalendar),
                                           keyEquivalent: "")
        resumeCalendarItem.target = self
        resumeCalendarItem.keyEquivalentModifierMask = [.command, .control]
        resumeCalendarItem.keyEquivalent = "4"
        menu.addItem(resumeCalendarItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Device status
        deviceStatusItem = NSMenuItem(title: "Device: Offline", action: nil, keyEquivalent: "")
        menu.addItem(deviceStatusItem!)

        // Device configuration (inline items)
        deviceConnectedItem = NSMenuItem(title: "Connected to: Not configured", action: nil, keyEquivalent: "")
        menu.addItem(deviceConnectedItem!)

        deviceConnectionStatusItem = NSMenuItem(title: "Status: Unknown", action: nil, keyEquivalent: "")
        menu.addItem(deviceConnectionStatusItem!)

        deviceLastSyncItem = NSMenuItem(title: "Last sync: Not yet", action: nil, keyEquivalent: "")
        menu.addItem(deviceLastSyncItem!)

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
        timeoutMenuItem = NSMenuItem(title: "Override Timeout", action: nil, keyEquivalent: "")
        timeoutMenuItem?.submenu = timeoutMenu
        menu.addItem(timeoutMenuItem!)

        #if DEBUG
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

        let debugParent = NSMenuItem(title: "🐛 Debug", action: nil, keyEquivalent: "")
        debugParent.submenu = debugMenu
        menu.addItem(debugParent)
        #endif

        menu.addItem(NSMenuItem.separator())
        
        // Calendar selection submenu
        let calendarMenu = NSMenu(title: "Calendars")
        buildCalendarMenu(calendarMenu)
        
        calendarMenuItem = NSMenuItem(title: "Calendars", action: nil, keyEquivalent: "")
        calendarMenuItem?.submenu = calendarMenu
        menu.addItem(calendarMenuItem!)
        
        settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem?.target = self
        menu.addItem(settingsItem!)
        
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
    
    public func updatePresenceState(_ state: PresenceState, source: StateSource = .startup, reason: BusyReason = .unknown, mode: OperatingMode = .auto) {
        currentDisplayState = state
        
        // Build detailed status string
        var statusDetail = ""
        switch mode {
        case .auto:
            switch source {
            case .calendar:
                statusDetail = " (Calendar)"
            case .meeting:
                switch reason {
                case .zoom:
                    statusDetail = " (Zoom Meeting)"
                case .teams:
                    statusDetail = " (Teams Meeting)"
                case .meet:
                    statusDetail = " (Google Meet)"
                default:
                    statusDetail = " (Meeting)"
                }
            case .system:
                statusDetail = " (System)"
            case .startup:
                statusDetail = " (Automatic)"
            case .manual:
                statusDetail = " (Manual)"
            }
        case .manual:
            statusDetail = " (Manual Override)"
        case .off:
            statusDetail = " (Disabled)"
        }
        
        statusText?.title = "Status: \(state.displayName)\(statusDetail)"

        // Update button icon color based on state
        updateButtonAppearance(for: state)
        updateManualOverrideCheckmarks()

        uiLogger.logEvent("Presence state updated", details: [
            "state": state.rawValue,
            "source": source.rawValue,
            "reason": reason.rawValue,
            "mode": mode.rawValue
        ])
    }
    
    // Legacy method for compatibility
    @available(*, deprecated, message: "Use updatePresenceState(_:source:reason:mode:) instead")
    public func updatePresenceState(_ state: PresenceState) {
        updatePresenceState(state, source: .startup, reason: .unknown, mode: currentMode)
    }
    
    /// Called by the state machine when operating mode changes
    public func updateModeDisplay(_ mode: OperatingMode) {
        currentMode = mode
        
        // Update UI elements based on mode
        switch mode {
        case .off:
            calendarStatusItem?.title = "Calendar: Disabled"
            turnOffMenuItem?.isHidden = true
        case .manual:
            calendarStatusItem?.title = "Calendar: Overridden"
            turnOffMenuItem?.isHidden = false
        case .auto:
            // Show "Resuming…" until the first calendar scan delivers a result
            calendarStatusItem?.title = "Calendar: Resuming…"
            turnOffMenuItem?.isHidden = false
        }

        manualOverrideMenuItem?.isHidden = mode != .manual
        updateModeCheckmarks()
        updateTimeoutVisibility(for: mode)
        
        uiLogger.logEvent("Mode display updated", details: ["mode": mode.rawValue])
    }

    /// Called by `SystemPresenceMonitor` when the screen locks or the system sleeps.
    /// Forces the icon and menu to `.away` regardless of the current calendar state.
    /// DEPRECATED: State machine now handles this via .systemAway event
    public func applyAwayState() {
        calendarStatusItem?.title = "Calendar: Paused (screen locked)"
        updatePresenceState(.away, source: .system, reason: .unknown, mode: currentMode)
        updateButtonAppearance(for: .away)
        uiLogger.logEvent("system.presence.away.applied")
    }

    /// Called by `SystemPresenceMonitor` when the user returns.
    /// Clears the away override so the next calendar scan can restore the real icon.
    /// DEPRECATED: State machine now handles this via .systemReturned event
    public func clearAwayState() {
        currentMode = .auto
        calendarStatusItem?.title = "Calendar: Resuming…"
        updateModeCheckmarks()
        uiLogger.logEvent("system.presence.away.cleared")
    }

    /// Called by the calendar engine whenever it resolves a new availability state.
    /// Updates the UI and marks state as calendar-driven.
    /// DEPRECATED: State machine now handles this via .calendarUpdated event
    public func applyCalendarState(_ state: PresenceState) {
        currentMode = .auto
        if state == .available {
            calendarStatusItem?.title = "Calendar: Active"
        } else {
            calendarStatusItem?.title = "Calendar: \(state.displayName) ●"
        }
        updatePresenceState(state, source: .calendar, reason: .calendar, mode: currentMode)
        updateModeCheckmarks()
    }

    /// Called when the calendar engine starts or stops to update the menu label.
    public func setCalendarEngineStatus(_ label: String) {
        calendarStatusItem?.title = "Calendar: \(label)"
    }
    
    /// Refreshes the calendar submenu with current available calendars.
    /// Call this after calendar permissions are granted or calendars change.
    public func refreshCalendarMenu() {
        guard let submenu = calendarMenuItem?.submenu else { return }
        buildCalendarMenu(submenu)
    }
    
    public func updateDeviceStatus(_ status: DeviceStatus) {
        deviceStatusItem?.title = deviceStatusTitle(for: status)

        uiLogger.logEvent("Device status updated", details: ["state": status.connectionState.rawValue])
    }
    
    /// Updates device status display for multiple WLED devices.
    public func updateDeviceList(_ devices: [WLEDDevice]) {
        let onlineCount = devices.filter { $0.isOnline }.count
        let offlineCount = devices.count - onlineCount
        
        let statusText: String
        if devices.isEmpty {
            statusText = "Device: Configuration missing"
        } else if offlineCount == 0 {
            statusText = "Device: Online"
        } else if onlineCount == 0 {
            statusText = "Device: Offline"
        } else {
            statusText = "Devices: \(onlineCount) online, \(offlineCount) offline"
        }
        
        deviceStatusItem?.title = statusText
        deviceLastSyncItem?.title = "Last sync: \(formatLastSync(from: devices))"
        
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

    public func updateConfiguredDevice(address: String?, status: DeviceConnectionStatus) {
        if let address = address, !address.isEmpty {
            deviceConnectedItem?.title = "Connected to: \(address)"
            deviceConnectionStatusItem?.title = "Status: \(status.displayText)"
        } else {
            deviceConnectedItem?.title = "Connected to: Not configured"
            deviceConnectionStatusItem?.title = "Status: Configuration required"
        }

        if address == nil || address?.isEmpty == true {
            deviceStatusItem?.title = "Device: Configuration missing"
            deviceLastSyncItem?.title = "Last sync: Not yet"
        }

        uiLogger.logEvent("device.configured.status.updated", details: [
            "address": address?.isEmpty == false ? address! : "(none)",
            "status": status.rawValue
        ])
    }

    private func updateMenuAppearance() {
        let config = ConfigurationManager.shared
        let state = config.getPresenceState()
        updatePresenceState(state, source: .startup, reason: .unknown, mode: currentMode)

        updateConfiguredDevice(address: config.getDeviceNetworkAddresses().first, status: .unknown)

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

    @objc private func selectAutoMode() {
        onResumeCalendarControl?()
        uiLogger.logEvent("calendar.control.resume.requested", details: ["source": "mode_menu"])
    }

    @objc private func selectManualMode() {
        let state = preferredManualOverrideState()
        onManualOverride?(state)
        uiLogger.logEvent("manual.mode.requested", details: [
            "state": state.rawValue,
            "source": "mode_menu"
        ])
    }

    @objc private func turnOffSystem() {
        onTurnOff?()
        uiLogger.logEvent("system.off.requested", details: ["source": "menu"])
    }
    
    @objc private func resumeCalendar() {
        onResumeCalendarControl?()
        uiLogger.logEvent("resume.calendar.requested", details: ["source": "menu"])
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

    @objc private func setManualOverride(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let state = PresenceState(rawValue: rawValue) else { return }
        onManualOverride?(state)
        uiLogger.logEvent("manual.override.requested", details: [
            "state": state.rawValue,
            "source": "manual_menu"
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

    @objc private func openSettings() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "BusyLight Settings"
        alert.informativeText = "Configure the WLED host and preset IDs used for each status."
        alert.alertStyle = .informational

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8

        let addressField = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        addressField.stringValue = ConfigurationManager.shared.getDeviceNetworkAddresses().first ?? ""
        stack.addArrangedSubview(labeledRow(label: "WLED Host (IPv4)", field: addressField))

        let availableField = labeledNumericField(value: ConfigurationManager.shared.getWledPresetAvailable())
        stack.addArrangedSubview(labeledRow(label: "Preset: Available", field: availableField))

        let tentativeField = labeledNumericField(value: ConfigurationManager.shared.getWledPresetTentative())
        stack.addArrangedSubview(labeledRow(label: "Preset: Tentative", field: tentativeField))

        let busyField = labeledNumericField(value: ConfigurationManager.shared.getWledPresetBusy())
        stack.addArrangedSubview(labeledRow(label: "Preset: Busy", field: busyField))

        let awayField = labeledNumericField(value: ConfigurationManager.shared.getWledPresetAway())
        stack.addArrangedSubview(labeledRow(label: "Preset: Away", field: awayField))

        alert.accessoryView = stack
        alert.window.initialFirstResponder = addressField

        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        let rawInput = addressField.stringValue
        if !rawInput.isEmpty {
            guard let normalized = NetworkAddressValidator.normalizeIPv4Address(rawInput) else {
                showInvalidDeviceAddressAlert()
                return
            }
            onConfigureDeviceAddress?(normalized)
        }

        let presets = [availableField, tentativeField, busyField, awayField]
        for field in presets where !isValidPresetInput(field.stringValue) {
            showInvalidPresetAlert()
            return
        }

        if let available = Int(availableField.stringValue) {
            ConfigurationManager.shared.setWledPresetAvailable(available)
        }
        if let tentative = Int(tentativeField.stringValue) {
            ConfigurationManager.shared.setWledPresetTentative(tentative)
        }
        if let busy = Int(busyField.stringValue) {
            ConfigurationManager.shared.setWledPresetBusy(busy)
        }
        if let away = Int(awayField.stringValue) {
            ConfigurationManager.shared.setWledPresetAway(away)
        }
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
    
    /// Builds the calendar submenu with checkboxes for each calendar
    private func buildCalendarMenu(_ calendarMenu: NSMenu) {
        calendarMenu.removeAllItems()
        calendarMenuItems.removeAll()
        
        guard let (availableCalendars, enabledTitles) = onGetCalendarList?() else {
            let item = NSMenuItem(title: "No calendars available", action: nil, keyEquivalent: "")
            item.isEnabled = false
            calendarMenu.addItem(item)
            return
        }
        
        if availableCalendars.isEmpty {
            let item = NSMenuItem(title: "No calendars found", action: nil, keyEquivalent: "")
            item.isEnabled = false
            calendarMenu.addItem(item)
            return
        }
        
        // Add "All Calendars" option at the top
        let allItem = NSMenuItem(title: "All Calendars", action: #selector(toggleAllCalendars), keyEquivalent: "")
        allItem.target = self
        allItem.state = enabledTitles.isEmpty ? .on : .off
        calendarMenu.addItem(allItem)
        calendarMenu.addItem(NSMenuItem.separator())
        
        // Add individual calendar items
        for calendar in availableCalendars {
            let item = NSMenuItem(
                title: "\(calendar.title) (\(calendar.source))",
                action: #selector(toggleCalendar(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = calendar.title
            item.state = (enabledTitles.isEmpty || enabledTitles.contains(calendar.title)) ? .on : .off
            calendarMenu.addItem(item)
            calendarMenuItems.append((item, calendar.title))
        }
        
        uiLogger.logEvent("Calendar menu built", details: [
            "count": String(availableCalendars.count),
            "enabled": enabledTitles.isEmpty ? "all" : String(enabledTitles.count)
        ])
    }
    
    @objc private func toggleAllCalendars() {
        // Enable all calendars (empty array means all)
        Task {
            await onUpdateEnabledCalendars?([])
            // Rebuild menu to update checkmarks
            if let submenu = calendarMenuItem?.submenu {
                buildCalendarMenu(submenu)
            }
        }
    }
    
    @objc private func toggleCalendar(_ sender: NSMenuItem) {
        guard let toggledTitle = sender.representedObject as? String,
              let (availableCalendars, enabledTitles) = onGetCalendarList?() else { return }
        
        var newEnabledTitles = enabledTitles.isEmpty ? availableCalendars.map(\.title) : enabledTitles
        
        if newEnabledTitles.contains(toggledTitle) {
            // Uncheck this calendar
            newEnabledTitles.removeAll { $0 == toggledTitle }
        } else {
            // Check this calendar
            newEnabledTitles.append(toggledTitle)
        }
        
        // If all calendars are now selected, save empty array (means "all")
        let titlesToSave = newEnabledTitles.count == availableCalendars.count ? [] : newEnabledTitles
        
        Task {
            await onUpdateEnabledCalendars?(titlesToSave)
            // Rebuild menu to update checkmarks
            if let submenu = calendarMenuItem?.submenu {
                buildCalendarMenu(submenu)
            }
        }
    }

    @objc private func quitApp() {
        uiLogger.logEvent("Quit requested from menu")
        lifecycleLogger.logEvent("Application shutting down via menu")
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Menu Helpers

    private func updateModeCheckmarks() {
        autoModeItem?.state = currentMode == .auto ? .on : .off
        manualModeItem?.state = currentMode == .manual ? .on : .off
    }

    private func updateTimeoutVisibility(for mode: OperatingMode) {
        let shouldShow = mode == .manual
        timeoutMenuItem?.isHidden = !shouldShow
    }

    private func preferredManualOverrideState() -> PresenceState {
        switch currentDisplayState {
        case .available, .busy, .tentative:
            return currentDisplayState
        default:
            return .available
        }
    }

    private func updateManualOverrideCheckmarks() {
        for item in manualOverrideItems {
            guard let rawValue = item.representedObject as? String else { continue }
            item.state = rawValue == currentDisplayState.rawValue ? .on : .off
        }
    }

    private func deviceStatusTitle(for status: DeviceStatus) -> String {
        switch status.connectionState {
        case .connected:
            return "Device: Online"
        case .disconnected:
            return "Device: Offline"
        case .error:
            return "Device: Offline"
        }
    }

    private func formatLastSync(from devices: [WLEDDevice]) -> String {
        let lastSeen = devices.map { $0.lastSeen }.filter { $0 != Date.distantPast }.max()
        guard let lastSeen else { return "Not yet" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: lastSeen)
    }

    private func labeledNumericField(value: Int) -> NSTextField {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = String(value)
        return field
    }

    private func labeledRow(label: String, field: NSTextField) -> NSView {
        let labelView = NSTextField(labelWithString: label)
        labelView.font = NSFont.systemFont(ofSize: 12)
        labelView.alignment = .right
        labelView.frame = NSRect(x: 0, y: 0, width: 140, height: 24)

        let row = NSStackView(views: [labelView, field])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    private func isValidPresetInput(_ value: String) -> Bool {
        guard let number = Int(value) else { return false }
        return number >= 1 && number <= 250
    }

    private func showInvalidDeviceAddressAlert() {
        let alert = NSAlert()
        alert.messageText = "Invalid Device Address"
        alert.informativeText = "Please enter a valid IPv4 address (example: 192.168.1.42)."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showInvalidPresetAlert() {
        let alert = NSAlert()
        alert.messageText = "Invalid Preset ID"
        alert.informativeText = "Preset IDs must be numbers between 1 and 250."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
