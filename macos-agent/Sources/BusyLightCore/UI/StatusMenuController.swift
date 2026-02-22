import AppKit

/// Manages the menu bar status icon and dropdown menu.
/// Isolated to @MainActor because all NSStatusBar and menu operations must run on the main thread.
@MainActor
public class StatusMenuController {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var statusText: NSMenuItem?
    private var toggleMenuItem: NSMenuItem?
    private var deviceStatusItem: NSMenuItem?
    
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
        
        // Device status
        deviceStatusItem = NSMenuItem(title: "Device: Disconnected", action: nil, keyEquivalent: "")
        menu.addItem(deviceStatusItem!)
        
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
        statusText?.title = "Status: \(state.displayName)"
        
        // Update toggle button text based on current state
        let nextState: PresenceState = state == .available ? .busy : .available
        toggleMenuItem?.title = "Mark as \(nextState.displayName)"
        
        // Update button icon color based on state
        updateButtonAppearance(for: state)
        
        uiLogger.logEvent("Presence state updated", details: ["state": state.rawValue])
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
        }
    }
    
    // MARK: - Action Handlers
    
    @objc private func togglePresenceState() {
        let config = ConfigurationManager.shared
        let currentState = config.getPresenceState()
        let newState: PresenceState = currentState == .available ? .busy : .available
        
        config.setPresenceState(newState)
        updatePresenceState(newState)
        
        uiLogger.logEvent("Presence state toggled", details: ["from": currentState.rawValue, "to": newState.rawValue])
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
