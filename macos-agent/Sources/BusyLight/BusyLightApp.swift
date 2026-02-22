import AppKit
import BusyLightCore

/// Application delegate managing the macOS menu bar presence agent lifecycle.
class BusyLightApp: NSObject, NSApplicationDelegate {
    private var statusMenuController: StatusMenuController?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        lifecycleLogger.logEvent("Application launched")

        // Configure app to run in menu bar only (no Dock icon)
        NSApplication.shared.setActivationPolicy(.prohibited)

        // Initialize configuration system
        ConfigurationManager.shared.loadConfiguration()
        lifecycleLogger.logEvent("Configuration manager initialized")

        // Create status menu controller (menu bar UI)
        statusMenuController = StatusMenuController()
        lifecycleLogger.logEvent("Status menu controller created")

        uiLogger.logEvent("Menu bar icon displayed")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Never terminate based on window closure (we have no windows)
        return false
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        lifecycleLogger.logEvent("Application terminating")

        // Ensure configuration is saved
        ConfigurationManager.shared.saveConfiguration()
        lifecycleLogger.logEvent("Configuration saved at shutdown")
    }
}
