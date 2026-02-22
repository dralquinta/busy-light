import Foundation
import AppKit

/// Carbon virtual key codes for function keys F13-F20.
/// Used to map physical keyboard events to presence states.
enum FunctionKeyCode: UInt16, Sendable {
    case f13 = 105  // Available
    case f14 = 107  // Tentative
    case f15 = 113  // Busy
    case f16 = 106  // Away
    case f17 = 64   // Off
    case f18 = 79
    case f19 = 80
    case f20 = 90
}

/// Monitors global keyboard events for hotkey presses (F13–F20).
/// Maps function key events to presence state changes and invokes callbacks.
///
/// Uses AppKit `NSEvent.addGlobalMonitorForEvents(matching:handler:)` which
/// requires the Accessibility API permission grant on modern macOS. The user is
/// prompted once at first run.
///
/// Isolated to `@MainActor` — callbacks and lifecycle operations run on main thread.
@MainActor
public final class HotkeyManager {
    
    // MARK: - Callbacks
    
    /// Called when a registered hotkey is pressed.
    /// Provides the target presence state mapped from the function key.
    public var onHotkeyPressed: (@MainActor (PresenceState) -> Void)?
    
    // MARK: - Configuration
    
    /// Maps each presence state to its function key code.
    /// Default: F13=available, F14=tentative, F15=busy, F16=away, F17=off
    private var hotkeyBindings: [PresenceState: UInt16] = [
        .available: FunctionKeyCode.f13.rawValue,
        .tentative: FunctionKeyCode.f14.rawValue,
        .busy: FunctionKeyCode.f15.rawValue,
        .away: FunctionKeyCode.f16.rawValue,
        .off: FunctionKeyCode.f17.rawValue
    ]
    
    // MARK: - Private State
    
    private var globalEventMonitor: Any?  // NSEvent.addGlobalMonitorForEvents return token
    private let logger: Logger
    private var isRunning = false
    
    // MARK: - Initialization
    
    public init(
        hotkeyBindings: [PresenceState: UInt16]? = nil,
        logger: Logger = lifecycleLogger
    ) {
        self.logger = logger
        
        if let bindings = hotkeyBindings {
            self.hotkeyBindings = bindings
        }
        
        logger.logEvent("hotkey.manager.initialized", details: [
            "bindingsCount": String(self.hotkeyBindings.count)
        ])
    }
    
    deinit {
        // Schedule cleanup on main actor
        Task { @MainActor [weak self] in
            self?.stop()
        }
    }
    
    // MARK: - Lifecycle
    
    /// Begins monitoring global keyboard events for registered hotkeys.
    /// Safe to call multiple times — existing monitors are stopped first.
    public func start() {
        stop()
        
        // Request accessibility permission via NSEvent global event monitoring
        // This will prompt the user on first run and require manual grant in System Prefs
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Run callback on main thread
            Task { @MainActor [weak self] in
                self?.handleKeyDown(event)
            }
        }
        
        isRunning = true
        logger.logEvent("hotkey.monitor.started", details: [
            "bindingsCount": String(hotkeyBindings.count)
        ])
    }
    
    /// Stops monitoring global keyboard events.
    public func stop() {
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
        
        isRunning = false
        logger.logEvent("hotkey.monitor.stopped")
    }
    
    // MARK: - Configuration
    
    /// Updates the hotkey-to-state bindings and reinitializes listeners.
    /// Called when user changes hotkey configuration via UI.
    public func updateBindings(_ newBindings: [PresenceState: UInt16]) {
        self.hotkeyBindings = newBindings
        
        // Reinitialize monitoring if currently active
        if isRunning {
            stop()
            start()
        }
        
        logger.logEvent("hotkey.bindings.updated", details: [
            "bindingsCount": String(newBindings.count)
        ])
    }
    
    // MARK: - Private Helpers
    
    /// Handles a keyboard key-down event from the global monitor.
    /// Checks if the key code matches any configured hotkey binding and invokes callback.
    private func handleKeyDown(_ event: NSEvent) {
        let keyCode = event.keyCode
        
        // Find which presence state this key maps to (if any)
        for (state, boundKey) in hotkeyBindings {
            if boundKey == keyCode {
                logger.logEvent("hotkey.pressed", details: [
                    "keyCode": String(keyCode),
                    "targetState": state.rawValue,
                    "timestamp": ISO8601DateFormatter().string(from: Date())
                ])
                
                // Invoke callback on main actor
                onHotkeyPressed?(state)
                return
            }
        }
        
        // Key press did not match any hotkey binding; ignore
    }
}
