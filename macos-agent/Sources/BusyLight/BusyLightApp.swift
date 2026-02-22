import AppKit
import BusyLightCore

/// Application delegate managing the macOS menu bar presence agent lifecycle.
@MainActor
class BusyLightApp: NSObject, NSApplicationDelegate {
    private var statusMenuController: StatusMenuController?
    private var calendarEngine: CalendarEngine?
    private var systemMonitor: SystemPresenceMonitor?
    private var stateMachine: PresenceStateMachine?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        lifecycleLogger.logEvent("Application launched")

        // Configure app to run in menu bar only (no Dock icon)
        NSApplication.shared.setActivationPolicy(.prohibited)

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
        machine.onStateChanged = { [weak controller] state, source in
            controller?.updatePresenceState(state)
            
            // Update calendar status label based on source
            if source == .calendar {
                if state == .available {
                    controller?.setCalendarEngineStatus("Active")
                } else {
                    controller?.setCalendarEngineStatus("\(state.displayName) ●")
                }
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

        controller.onResumeCalendarControl = { [weak machine] in
            machine?.handleEvent(.resumeAuto)
        }
        
        controller.onManualOverride = { [weak machine] state in
            machine?.handleEvent(.manualOverride(state))
        }

        controller.setCalendarEngineStatus("Starting…")
        Task {
            await engine.start()
            // Reflect the actual state that came out of the first scan.  Do not
            // overwrite the label if applyCalendarState already set it (e.g. a
            // busy event was found on first scan).
            if !engine.isActive {
                controller.setCalendarEngineStatus("Permission denied")
            } else if engine.currentState == .available {
                controller.setCalendarEngineStatus("Active")
            }
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

        controller.onSimulateAway = { [weak monitor] in
            monitor?.simulateAway()
        }

        controller.onSimulateReturn = { [weak monitor] in
            monitor?.simulateReturn()
        }

        controller.onScanNow = { [weak engine] in
            Task { await engine?.scanNow() }
        }

        monitor.start()
        lifecycleLogger.logEvent("System presence monitor started")
        
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
        calendarEngine?.stop()
        lifecycleLogger.logEvent("Monitors stopped")

        // Ensure configuration is saved
        ConfigurationManager.shared.saveConfiguration()
        lifecycleLogger.logEvent("Configuration saved at shutdown")
    }
}

