import AppKit

public enum SignalFeedback: Equatable {
    case sending(PresenceState)
    case sent(state: PresenceState, deliveredCount: Int, totalCount: Int, date: Date)
    case failed(state: PresenceState, deliveredCount: Int, totalCount: Int, date: Date)
}

private struct OfficeHoursEditorControls {
    let view: NSView
    let enabledButton: NSButton
    let dayButtons: [(button: NSButton, weekday: Int)]
    let fromPopup: NSPopUpButton
    let toPopup: NSPopUpButton
    let allDayButton: NSButton
}

/// Manages the menu bar status icon and dropdown menu.
/// Isolated to @MainActor because all NSStatusBar and menu operations must run on the main thread.
@MainActor
public class StatusMenuController {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var statusText: NSMenuItem?
    private var deviceSummaryItem: NSMenuItem?
    private var signalFeedbackItem: NSMenuItem?
    private var modeMenuItem: NSMenuItem?
    private var autoModeItem: NSMenuItem?
    private var manualModeItem: NSMenuItem?
    private var manualOverrideMenuItem: NSMenuItem?
    private var manualOverrideItems: [NSMenuItem] = []
    private var turnOffMenuItem: NSMenuItem?
    private var deviceStatusItem: NSMenuItem?
    private var deviceConnectedItem: NSMenuItem?
    private var deviceLastSyncItem: NSMenuItem?
    private var calendarStatusItem: NSMenuItem?
    private var settingsItem: NSMenuItem?
    private var timeoutMenuItem: NSMenuItem?

    /// The state currently shown in the menu bar icon and status text.
    private var currentDisplayState: PresenceState = .available

    /// Current operating mode (auto = calendar-driven, manual = user override)
    private var currentMode: OperatingMode = .auto

    private let deviceConfigurationSectionTitle = "Device Configuration"
    private let officeHoursSectionTitle = "Office Hours"
    private let officeHoursEditorSize = NSSize(width: 448, height: 118)
    private let officeHoursDayOptions: [(label: String, weekday: Int)] = [
        ("M", 2), ("T", 3), ("W", 4), ("T", 5), ("F", 6), ("S", 7), ("S", 1)
    ]
    private let officeHoursTimeControlLabels = ["from", "to", "All day"]

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

    /// Called when the user changes office-hours settings.
    public var onOfficeHoursChanged: (@MainActor () -> Void)?
    
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

        deviceSummaryItem = NSMenuItem(title: "Devices: Searching (0 online)", action: nil, keyEquivalent: "")
        menu.addItem(deviceSummaryItem!)

        signalFeedbackItem = NSMenuItem(title: "Signal: Waiting", action: nil, keyEquivalent: "")
        menu.addItem(signalFeedbackItem!)
        
        menu.addItem(NSMenuItem.separator())

        // Status control
        let controlMenu = NSMenu(title: "Control")

        autoModeItem = NSMenuItem(title: "Automatic Calendar Control", action: #selector(selectAutoMode), keyEquivalent: "")
        autoModeItem?.target = self
        autoModeItem?.keyEquivalentModifierMask = [.command, .control]
        autoModeItem?.keyEquivalent = "4"
        controlMenu.addItem(autoModeItem!)

        manualModeItem = NSMenuItem(title: "Manual Override", action: #selector(selectManualMode), keyEquivalent: "")
        manualModeItem?.target = self
        controlMenu.addItem(manualModeItem!)

        // Turn Off item — suspends all syncing, visible in auto/manual mode
        turnOffMenuItem = NSMenuItem(title: "Turn Off BusyLight",
                                     action: #selector(turnOffSystem),
                                     keyEquivalent: "")
        turnOffMenuItem?.target = self
        controlMenu.addItem(turnOffMenuItem!)

        modeMenuItem = NSMenuItem(title: "Control", action: nil, keyEquivalent: "")
        modeMenuItem?.submenu = controlMenu
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
        
        menu.addItem(NSMenuItem.separator())

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
        
        let settingsMenu = NSMenu(title: "Settings")

        let devicesMenu = NSMenu(title: "Devices")
        deviceStatusItem = NSMenuItem(title: "Device: Searching", action: nil, keyEquivalent: "")
        devicesMenu.addItem(deviceStatusItem!)

        deviceConnectedItem = NSMenuItem(title: "Connected to: Searching", action: nil, keyEquivalent: "")
        devicesMenu.addItem(deviceConnectedItem!)

        deviceLastSyncItem = NSMenuItem(title: "Last sync: Not yet", action: nil, keyEquivalent: "")
        devicesMenu.addItem(deviceLastSyncItem!)

        devicesMenu.addItem(NSMenuItem.separator())

        let configureDevicesItem = NSMenuItem(title: "Configure Devices...", action: #selector(openSettings), keyEquivalent: "")
        configureDevicesItem.target = self
        devicesMenu.addItem(configureDevicesItem)

        let devicesItem = NSMenuItem(title: "Devices", action: nil, keyEquivalent: "")
        devicesItem.submenu = devicesMenu
        settingsMenu.addItem(devicesItem)
        settingsMenu.addItem(NSMenuItem.separator())

        let officeHoursItem = NSMenuItem(title: "Office Hours...", action: #selector(openOfficeHoursSettings), keyEquivalent: "")
        officeHoursItem.target = self
        settingsMenu.addItem(officeHoursItem)

        let preferencesItem = NSMenuItem(title: "Preferences…", action: #selector(openSettings), keyEquivalent: ",")
        preferencesItem.target = self
        settingsMenu.addItem(preferencesItem)

        settingsItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        settingsItem?.submenu = settingsMenu
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
            case .officeHours:
                statusDetail = " (Office Hours)"
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

    public func updateSignalFeedback(_ feedback: SignalFeedback) {
        switch feedback {
        case .sending(let state):
            signalFeedbackItem?.title = "Signal: Sending \(state.displayName)..."
        case .sent(let state, let deliveredCount, let totalCount, _):
            signalFeedbackItem?.title = "Signal: Sent \(state.displayName) (\(deliveredCount)/\(totalCount))"
        case .failed(let state, let deliveredCount, let totalCount, _):
            signalFeedbackItem?.title = "Signal: Failed \(state.displayName) (\(deliveredCount)/\(totalCount))"
        }
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
        let onlineDevices = devices.filter { $0.isOnline }
        let onlineCount = onlineDevices.count
        let offlineCount = devices.count - onlineCount
        
        let statusText: String
        if onlineDevices.isEmpty {
            statusText = "Device: Searching"
        } else if onlineCount == 1 {
            statusText = "Device: Online"
        } else {
            statusText = "Devices: \(onlineCount) online"
        }
        
        deviceStatusItem?.title = statusText
        deviceSummaryItem?.title = deviceSummaryTitle(onlineCount: onlineCount)
        deviceLastSyncItem?.title = "Last sync: \(formatLastSync(from: onlineDevices))"
        
        // Build tooltip with individual device details
        var tooltip = "WLED Devices:\n"
        if onlineDevices.isEmpty {
            tooltip += "  No online WLED devices found\n"
            tooltip += "  Scanning local network"
        } else {
            for device in onlineDevices {
                let status = "●"
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
        } else {
            deviceConnectedItem?.title = "Connected to: Searching"
        }

        if address == nil || address?.isEmpty == true {
            deviceStatusItem?.title = "Device: Searching"
            deviceSummaryItem?.title = deviceSummaryTitle(onlineCount: 0)
            deviceLastSyncItem?.title = "Last sync: Not yet"
        }

        uiLogger.logEvent("device.configured.status.updated", details: [
            "address": address?.isEmpty == false ? address! : "(none)",
            "status": status.rawValue
        ])
    }

    private func updateMenuAppearance() {
        let state = ConfigurationManager.shared.getPresenceState()
        updatePresenceState(state, source: .startup, reason: .unknown, mode: currentMode)

        updateDeviceList([])
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

        stack.addArrangedSubview(sectionHeader(title: deviceConfigurationSectionTitle))

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

        stack.addArrangedSubview(sectionDivider())
        stack.addArrangedSubview(sectionHeader(title: officeHoursSectionTitle))

        let officeHours = ConfigurationManager.shared.getOfficeHoursConfiguration()
        let officeHoursEditor = makeOfficeHoursEditor(configuration: officeHours)
        stack.addArrangedSubview(officeHoursEditor.view)

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

        guard let updatedOfficeHours = officeHoursConfiguration(from: officeHoursEditor) else {
            showInvalidOfficeHoursAlert()
            return
        }

        ConfigurationManager.shared.setOfficeHoursConfiguration(updatedOfficeHours)
        onOfficeHoursChanged?()
    }

    @objc private func openOfficeHoursSettings() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Office Hours"
        alert.informativeText = "Outside office hours, BusyLight turns the light off unless you send a manual override."
        alert.alertStyle = .informational

        let officeHours = ConfigurationManager.shared.getOfficeHoursConfiguration()
        let officeHoursEditor = makeOfficeHoursEditor(configuration: officeHours)

        alert.accessoryView = officeHoursEditor.view
        alert.window.initialFirstResponder = officeHoursEditor.fromPopup
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        guard let updatedOfficeHours = officeHoursConfiguration(from: officeHoursEditor) else {
            showInvalidOfficeHoursAlert()
            return
        }

        ConfigurationManager.shared.setOfficeHoursConfiguration(updatedOfficeHours)
        onOfficeHoursChanged?()
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
            return "Device: Searching"
        case .error:
            return "Device: Searching"
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

    private func deviceSummaryTitle(onlineCount: Int) -> String {
        let status = onlineCount > 0 ? "Online" : "Searching"
        return "Devices: \(status) (\(onlineCount) online)"
    }

    private var officeHoursTimeOptions: [(label: String, minute: Int)] {
        return stride(from: 0, to: 24 * 60, by: 30).map { minute in
            (displayTimeLabel(for: minute), minute)
        }
    }

    private func makeOfficeHoursEditor(configuration officeHours: OfficeHoursConfiguration) -> OfficeHoursEditorControls {
        let container = NSView(frame: NSRect(origin: .zero, size: officeHoursEditorSize))
        container.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: officeHoursEditorSize.width),
            container.heightAnchor.constraint(equalToConstant: officeHoursEditorSize.height),
        ])

        let enabledButton = NSButton(checkboxWithTitle: "On", target: nil, action: nil)
        enabledButton.frame = NSRect(x: 0, y: 82, width: 62, height: 24)
        enabledButton.state = officeHours.isEnabled ? .on : .off
        container.addSubview(enabledButton)

        var dayButtons: [(button: NSButton, weekday: Int)] = []
        for (index, option) in officeHoursDayOptions.enumerated() {
            let button = NSButton(title: option.label, target: nil, action: nil)
            button.setButtonType(.pushOnPushOff)
            button.bezelStyle = .rounded
            button.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            button.frame = NSRect(x: 70 + (index * 38), y: 79, width: 32, height: 30)
            button.state = officeHours.activeWeekdays.contains(option.weekday) ? .on : .off
            container.addSubview(button)
            dayButtons.append((button, option.weekday))
        }

        let fromLabel = NSTextField(labelWithString: officeHoursTimeControlLabels[0])
        fromLabel.frame = NSRect(x: 0, y: 42, width: 38, height: 22)
        container.addSubview(fromLabel)

        let fromPopup = makeOfficeHoursTimePopup(selectedMinute: officeHours.startMinuteOfDay)
        fromPopup.frame = NSRect(x: 44, y: 38, width: 116, height: 28)
        container.addSubview(fromPopup)

        let toLabel = NSTextField(labelWithString: officeHoursTimeControlLabels[1])
        toLabel.frame = NSRect(x: 176, y: 42, width: 20, height: 22)
        container.addSubview(toLabel)

        let toPopup = makeOfficeHoursTimePopup(selectedMinute: officeHours.endMinuteOfDay)
        toPopup.frame = NSRect(x: 202, y: 38, width: 116, height: 28)
        container.addSubview(toPopup)

        let allDayButton = NSButton(checkboxWithTitle: officeHoursTimeControlLabels[2], target: nil, action: nil)
        allDayButton.frame = NSRect(x: 334, y: 40, width: 92, height: 24)
        allDayButton.state = officeHours.startMinuteOfDay == officeHours.endMinuteOfDay ? .on : .off
        container.addSubview(allDayButton)

        return OfficeHoursEditorControls(
            view: container,
            enabledButton: enabledButton,
            dayButtons: dayButtons,
            fromPopup: fromPopup,
            toPopup: toPopup,
            allDayButton: allDayButton
        )
    }

    private func makeOfficeHoursTimePopup(selectedMinute: Int) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        for option in officeHoursTimeOptions {
            popup.addItem(withTitle: option.label)
            popup.lastItem?.tag = option.minute
        }

        selectOfficeHoursTime(closestOfficeHoursTimeOption(to: selectedMinute), in: popup)
        return popup
    }

    private func officeHoursConfiguration(from editor: OfficeHoursEditorControls) -> OfficeHoursConfiguration? {
        let activeWeekdays = Set(editor.dayButtons.compactMap { item in
            item.button.state == .on ? item.weekday : nil
        })
        guard !activeWeekdays.isEmpty else { return nil }

        let isAllDay = editor.allDayButton.state == .on
        let startMinute = isAllDay ? 0 : selectedOfficeHoursTime(from: editor.fromPopup)
        let endMinute = isAllDay ? 0 : selectedOfficeHoursTime(from: editor.toPopup)

        return OfficeHoursConfiguration(
            isEnabled: editor.enabledButton.state == .on,
            startMinuteOfDay: startMinute,
            endMinuteOfDay: endMinute,
            activeWeekdays: activeWeekdays
        )
    }

    private func selectedOfficeHoursTime(from popup: NSPopUpButton) -> Int {
        return OfficeHoursConfiguration.normalizedMinute(popup.selectedItem?.tag ?? 0)
    }

    private func selectOfficeHoursTime(_ minute: Int, in popup: NSPopUpButton) {
        guard let item = popup.itemArray.first(where: { $0.tag == minute }) else {
            popup.selectItem(at: 0)
            return
        }

        popup.select(item)
    }

    private func closestOfficeHoursTimeOption(to minute: Int) -> Int {
        let normalized = OfficeHoursConfiguration.normalizedMinute(minute)
        let rounded = ((normalized + 15) / 30) * 30
        return min(rounded, (23 * 60) + 30)
    }

    private func displayTimeLabel(for minute: Int) -> String {
        let hour = minute / 60
        let minutePart = minute % 60
        let suffix = hour < 12 ? "AM" : "PM"
        let hourPart = hour % 12 == 0 ? 12 : hour % 12
        return String(format: "%d:%02d %@", hourPart, minutePart, suffix)
    }

    private func labeledNumericField(value: Int) -> NSTextField {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = String(value)
        return field
    }

    private func sectionHeader(title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.boldSystemFont(ofSize: 12)
        label.alignment = .left
        return label
    }

    private func sectionDivider() -> NSBox {
        let divider = NSBox()
        divider.boxType = .separator
        return divider
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

    private func showInvalidOfficeHoursAlert() {
        let alert = NSAlert()
        alert.messageText = "Invalid Office Hours"
        alert.informativeText = "Select at least one weekday."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    #if DEBUG
    func menuTitlesForTesting(path: [String] = []) -> [String] {
        guard let menu = menuForTesting(at: path) else { return [] }
        return menu.items
            .filter { !$0.isSeparatorItem }
            .map(\.title)
    }

    func keyEquivalentForTesting(path: [String]) -> String? {
        guard let item = menuItemForTesting(at: path) else { return nil }
        return item.keyEquivalent
    }

    func settingsSectionTitlesForTesting() -> [String] {
        return [deviceConfigurationSectionTitle, officeHoursSectionTitle]
    }

    func officeHoursDayLabelsForTesting() -> [String] {
        return officeHoursDayOptions.map(\.label)
    }

    func officeHoursTimeControlLabelsForTesting() -> [String] {
        return officeHoursTimeControlLabels
    }

    func officeHoursTimeOptionsForTesting() -> [String] {
        return officeHoursTimeOptions.map(\.label)
    }

    func officeHoursEditorSizeForTesting() -> NSSize {
        return officeHoursEditorSize
    }

    private func menuForTesting(at path: [String]) -> NSMenu? {
        guard let firstTitle = path.first else { return menu }
        guard let item = menu.items.first(where: { $0.title == firstTitle }) else { return nil }

        return path.dropFirst().reduce(item.submenu) { currentMenu, title in
            guard let currentMenu else { return nil }
            return currentMenu.items.first(where: { $0.title == title })?.submenu
        }
    }

    private func menuItemForTesting(at path: [String]) -> NSMenuItem? {
        guard let itemTitle = path.last else { return nil }
        let parentPath = Array(path.dropLast())
        return menuForTesting(at: parentPath)?.items.first(where: { $0.title == itemTitle })
    }
    #endif
}
