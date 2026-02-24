import AppKit
import BusyLightCore
import ApplicationServices

/// Application delegate managing the macOS menu bar presence agent lifecycle.
@MainActor
class BusyLightApp: NSObject, NSApplicationDelegate {
    private var statusMenuController: StatusMenuController?
    private var calendarEngine: CalendarEngine?
    private var systemMonitor: SystemPresenceMonitor?
    private var hotkeyManager: HotkeyManager?
    private var stateMachine: PresenceStateMachine?
    private var networkClient: NetworkClient?
    private var meetingEngine: MeetingDetectionEngine?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        lifecycleLogger.logEvent("Application launched")

        // Configure app to run in menu bar only (no Dock icon)
        NSApplication.shared.setActivationPolicy(.prohibited)
        
        // Check accessibility permission required for global hotkey monitoring
        checkAccessibilityPermission()

        // Initialize configuration system
        ConfigurationManager.shared.loadConfiguration()
        lifecycleLogger.logEvent("Configuration manager initialized")

        // Create status menu controller (menu bar UI)
        let controller = StatusMenuController()
        statusMenuController = controller
        lifecycleLogger.logEvent("Status menu controller created")

        uiLogger.logEvent("Menu bar icon displayed")

        // Initialize the state machine with configuration settings
        let machine = PresenceStateMachine(initialState: .unknown, initialMode: .auto)
        machine.manualOverrideTimeoutMinutes = ConfigurationManager.shared.getManualOverrideTimeoutMinutes()
        machine.stateStabilizationSeconds = ConfigurationManager.shared.getStateStabilizationSeconds()
        stateMachine = machine
        lifecycleLogger.logEvent("State machine initialized")
        
        // Wire state machine callbacks to UI
        machine.onStateChanged = { [weak controller, weak self, weak machine] state, source, reason in
            controller?.updatePresenceState(state, source: source, reason: reason, mode: machine?.currentMode ?? .auto)

            // Update calendar status label when calendar or startup drives state.
            // Skip .off — that label is already set by updateModeDisplay(.off).
            if source == .calendar || source == .startup, state != .off {
                if state == .available {
                    controller?.setCalendarEngineStatus("Active")
                } else if state == .unknown {
                    controller?.setCalendarEngineStatus("Starting…")
                } else {
                    controller?.setCalendarEngineStatus("\(state.displayName) ●")
                }
            }
            
            // Send state to WLED devices
            Task {
                await self?.networkClient?.sendState(state)
            }
        }
        
        machine.onModeChanged = { [weak controller] mode in
            controller?.updateModeDisplay(mode)
        }

        // Start the calendar engine and wire its output to the state machine.
        let engine = CalendarEngine()
        calendarEngine = engine

        engine.onAvailabilityChange = { [weak machine] state in
            machine?.handleEvent(.calendarUpdated(state))
        }
        
        // Wire state machine callback to trigger calendar sync
        machine.onRequestCalendarSync = { [weak engine] in
            Task { await engine?.scanNow() }
        }

        controller.onResumeCalendarControl = { [weak machine, weak self] in
            machine?.handleEvent(.resumeAuto)
            // Clear any stale meeting detections when manually resuming calendar control
            self?.meetingEngine?.clearAndSuppressFor(seconds: 5)
        }
        
        controller.onManualOverride = { [weak machine] state in
            machine?.handleEvent(.manualOverride(state))
        }

        controller.onTurnOff = { [weak machine] in
            machine?.handleEvent(.turnOff)
        }

        controller.onTimeoutChanged = { [weak machine] minutes in
            // Persist to UserDefaults
            ConfigurationManager.shared.setManualOverrideTimeoutMinutes(minutes)
            // Apply immediately to the running state machine
            machine?.manualOverrideTimeoutMinutes = minutes
            lifecycleLogger.logEvent("override.timeout.updated", details: [
                "minutes": minutes.map { String($0) } ?? "never"
            ])
        }

        controller.onConfigureDeviceAddress = { [weak self, weak controller] address in
            let previous = ConfigurationManager.shared.getDeviceNetworkAddresses().first ?? ""

            ConfigurationManager.shared.setDeviceNetworkAddress(address)
            ConfigurationManager.shared.setDeviceNetworkAddresses([address])

            lifecycleLogger.logEvent("device.host.override.updated", details: [
                "previous": previous.isEmpty ? "(none)" : previous,
                "new": address
            ])

            controller?.updateConfiguredDevice(address: address, status: .unknown)

            Task {
                await self?.networkClient?.applyDeviceHostOverride(address)
            }
        }
        
        controller.onGetCalendarList = { [weak engine] in
            let available = engine?.getAvailableCalendars() ?? []
            let enabled = ConfigurationManager.shared.getEnabledCalendarTitles()
            return (available, enabled)
        }
        
        controller.onUpdateEnabledCalendars = { [weak engine] titles in
            await engine?.setEnabledCalendars(titles)
        }

        controller.setCalendarEngineStatus("Starting…")
        Task {
            await engine.start()
            // Reflect the actual state that came out of the first scan.  Do not
            // overwrite the label if applyCalendarState already set it (e.g. a
            // busy event was found on first scan).
            if !engine.isActive {
                controller.setCalendarEngineStatus("Permission required")
            } else if engine.currentState == .available {
                controller.setCalendarEngineStatus("Active")
            }
            
            // Refresh calendar menu now that permissions are granted and engine is active
            controller.refreshCalendarMenu()
            // If state != .available, applyCalendarState already set the label.
        }

        // Start the system presence monitor so screen lock → away.
        let monitor = SystemPresenceMonitor()
        systemMonitor = monitor

        monitor.onUserAway = { [weak machine] in
            machine?.handleEvent(.systemAway)
        }

        monitor.onUserReturned = { [weak machine] in
            machine?.handleEvent(.systemReturned)
        }

        #if DEBUG
        controller.onSimulateAway = { [weak monitor] in
            monitor?.simulateAway()
        }

        controller.onSimulateReturn = { [weak monitor] in
            monitor?.simulateReturn()
        }

        controller.onScanNow = { [weak engine] in
            Task { await engine?.scanNow() }
        }
        #endif

        monitor.start()
        lifecycleLogger.logEvent("System presence monitor started")
        
        // Immediately scan calendars on startup to set initial status
        Task {
            await engine.scanNow()
        }
        
        // Start the hotkey manager to listen for global keyboard events
        let hotkeyMgr = HotkeyManager(
            hotkeyBindings: ConfigurationManager.shared.getHotkeyBindings()
        )
        hotkeyManager = hotkeyMgr
        
        hotkeyMgr.onHotkeyPressed = { [weak machine] state in
            // Handle state transition
            machine?.handleEvent(.hotkeyPressed(state))
        }
        
        hotkeyMgr.onResumeCalendarControl = { [weak machine, weak engine, weak self] in
            // Cancel override and resume calendar control immediately
            machine?.handleEvent(.resumeAuto)
            
            // Clear any stale meeting detections and suppress for 5 seconds
            // This prevents lingering Google Meet tabs from overriding calendar state
            self?.meetingEngine?.clearAndSuppressFor(seconds: 5)
            
            // Trigger immediate calendar scan to update status
            Task {
                await engine?.scanNow()
            }
        }
        
        hotkeyMgr.onTurnOffPressed = { [weak machine] in
            // Turn off the system
            machine?.handleEvent(.turnOff)
        }
        
        hotkeyMgr.start()
        lifecycleLogger.logEvent("Hotkey manager started")

        // Initialize and start meeting detection engine (if enabled)
        let meetingConfig = ConfigurationManager.shared
        if meetingConfig.getMeetingDetectionEnabled() {
            let engine = MeetingDetectionEngine()
            engine.pollIntervalSeconds = meetingConfig.getMeetingPollIntervalSeconds()
            engine.confidenceThreshold = meetingConfig.getMeetingConfidenceThreshold()
            engine.setProvider(.zoom,  enabled: meetingConfig.getMeetingProviderZoomEnabled())
            engine.setProvider(.teams, enabled: meetingConfig.getMeetingProviderTeamsEnabled())
            engine.setProvider(.meet,  enabled: meetingConfig.getMeetingProviderBrowserEnabled())
            engine.onMeetingStatusChanged = { [weak machine] status in
                machine?.handleEvent(.meetingDetected(status))
            }
            engine.start()
            meetingEngine = engine
            lifecycleLogger.logEvent("Meeting detection engine started", details: [
                "pollInterval": String(engine.pollIntervalSeconds),
                "threshold": engine.confidenceThreshold.displayName
            ])
        }
        
        // Initialize network client for WLED communication
        let client = NetworkClient(config: ConfigurationManager.shared)
        networkClient = client
        
        // Wire network client callback to update UI with device statuses
        client.onDeviceStatusChanged = { [weak controller, weak self] devices in
            controller?.updateDeviceList(devices)
            let configuredAddress = ConfigurationManager.shared.getDeviceNetworkAddresses().first
            let status = self?.deviceConnectionStatus(for: configuredAddress, devices: devices) ?? .unknown
            controller?.updateConfiguredDevice(address: configuredAddress, status: status)
        }
        
        // Connect to WLED devices and start health monitoring
        Task {
            await client.connect()
            client.startHealthMonitoring()
            lifecycleLogger.logEvent("Network client initialized and connected")
        }
        
        #if DEBUG
        // Wire debug info callback
        controller.onShowHotkeyDebugInfo = { [weak hotkeyMgr] in
            guard hotkeyMgr != nil else { return "HotkeyManager not available" }
            return "HotkeyManager active\nBindings: Ctrl+Cmd+1/2/3, Ctrl+Cmd+4 (resume), F16, F17"
        }
        #endif
        
        // Initialize state machine
        machine.handleEvent(.startupInitialize)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Never terminate based on window closure (we have no windows)
        return false
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        lifecycleLogger.logEvent("Application terminating")

        systemMonitor?.stop()
        hotkeyManager?.stop()
        calendarEngine?.stop()
        meetingEngine?.stop()
        networkClient?.stopHealthMonitoring()
        networkClient?.disconnect()
        lifecycleLogger.logEvent("Monitors stopped")

        // Ensure configuration is saved
        ConfigurationManager.shared.saveConfiguration()
        lifecycleLogger.logEvent("Configuration saved at shutdown")
    }
    
    // MARK: - Helpers

    private func deviceConnectionStatus(
        for address: String?,
        devices: [WLEDDevice]
    ) -> DeviceConnectionStatus {
        guard let address = address, !address.isEmpty else { return .unknown }
        guard let device = devices.first(where: { $0.address == address }) else { return .unknown }
        return device.isOnline ? .online : .offline
    }
    
    /// Converts a Carbon virtual key code to a human-readable function key name.
    private func functionKeyName(for keyCode: UInt16) -> String {
        switch keyCode {
        case 105: return "F13"
        case 107: return "F14"
        case 113: return "F15"
        case 106: return "F16"
        case 64:  return "F17"
        case 79:  return "F18"
        case 80:  return "F19"
        case 90:  return "F20"
        default:  return "Unknown"
        }
    }
    
    /// Checks if accessibility permission is granted and shows a popup if not.
    private func checkAccessibilityPermission() {
        // Check if accessibility is enabled
        let isTrusted = AXIsProcessTrusted()
        
        if !isTrusted {
            // Permission not granted - show popup
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = """
            BusyLight needs Accessibility permission to monitor global hotkeys (F13–F17).
            
            Steps to enable:
            1. Open System Settings → Privacy & Security → Accessibility
            2. Look for "BusyLight" in the list
            3. If not there, click "+" and select BusyLight.app
            4. Toggle the switch ON
            5. Restart BusyLight
            
            Without this permission, hotkeys from Stream Deck or keyboard won't be detected.
            """
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Remind Later")
            alert.alertStyle = .warning
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                // Open System Preferences to Accessibility
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
            
            lifecycleLogger.logEvent("accessibility.permission.not_granted")
        } else {
            lifecycleLogger.logEvent("accessibility.permission.granted")
        }
    }
}

