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

    /// When `true` the current `PresenceState` was resolved from the calendar
    /// engine rather than set manually.
    private var calendarDriven = false

    /// Called when the user taps "Resume Calendar Control" so the app can
    /// trigger an immediate calendar rescan.
    public var onResumeCalendarControl: (@MainActor () -> Void)?
    
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
        
        // Preferences (placeholder for future)
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
        let prefix = calendarDriven ? "Manually " : ""
        toggleMenuItem?.title = "\(prefix)Mark as \(toggleTarget.displayName)"

        // Update button icon color based on state
        updateButtonAppearance(for: state)

        uiLogger.logEvent("Presence state updated", details: ["state": state.rawValue])
    }

    /// Called by `SystemPresenceMonitor` when the screen locks or the system sleeps.
    /// Forces the icon and menu to `.away` regardless of the current calendar state.
    public func applyAwayState() {
        calendarStatusItem?.title = "Calendar: Paused (screen locked)"
        updatePresenceState(.away)
        updateButtonAppearance(for: .away)
        uiLogger.logEvent("system.presence.away.applied")
    }

    /// Called by `SystemPresenceMonitor` when the user returns.
    /// Clears the away override so the next calendar scan can restore the real icon.
    public func clearAwayState() {
        calendarDriven = false
        resumeCalendarItem?.isHidden = true
        calendarStatusItem?.title = "Calendar: Resuming…"
        uiLogger.logEvent("system.presence.away.cleared")
    }

    /// Called by the calendar engine whenever it resolves a new availability state.
    /// Updates the UI and marks state as calendar-driven.
    public func applyCalendarState(_ state: PresenceState) {
        calendarDriven = true
        resumeCalendarItem?.isHidden = true
        // Only show the state in the label when it is noteworthy (non-available).
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
        
        // Update semaphore icon based on presence state
        switch state {
        case .available:
            button.title = "🟢"  // Green for available
        case .busy:
            button.title = "🔴"  // Red for busy
        case .away:
            button.title = "🟡"  // Yellow for away
        case .tentative:
            button.title = "🟠"  // Orange for tentative
        }
    }
    
    // MARK: - Action Handlers
    
    @objc private func togglePresenceState() {
        // Use the locally tracked display state — the calendar engine does NOT
        // write to ConfigurationManager, so config.getPresenceState() is stale.
        let newState: PresenceState = currentDisplayState == .available ? .busy : .available

        // Mark as overridden and show the Resume item.
        calendarDriven = false
        calendarStatusItem?.title = "Calendar: Overridden"
        resumeCalendarItem?.isHidden = false

        updatePresenceState(newState)

        uiLogger.logEvent("Presence state toggled",
                          details: ["from": currentDisplayState.rawValue, "to": newState.rawValue,
                                    "source": "manual"])
    }

    /// Clears the manual override and re-enables calendar-driven state.
    /// The caller is responsible for triggering a fresh calendar scan.
    @objc private func resumeCalendarControl() {
        calendarDriven = true
        calendarStatusItem?.title = "Calendar: Resuming…"
        resumeCalendarItem?.isHidden = true
        onResumeCalendarControl?()
        uiLogger.logEvent("calendar.control.resumed", details: ["source": "manual"])
    }
    
    @objc private func openPreferences() {
        uiLogger.logEvent("Preferences requested (not yet implemented)")
        // Placeholder for future preferences window
    }
    
    @objc private func quitApp() {
        uiLogger.logEvent("Quit requested from menu")
        lifecycleLogger.logEvent("Application shutting down via menu")
        NSApplication.shared.terminate(nil)
    }
}
