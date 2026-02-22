import Foundation

/// Events that trigger state machine transitions.
/// These are the only valid inputs to the state machine.
@MainActor
public enum StateEvent: Sendable {
    /// Calendar engine detected a presence state change
    case calendarUpdated(PresenceState)
    
    /// User manually set a presence state via UI
    case manualOverride(PresenceState)
    
    /// System went away (screen lock, sleep, etc.)
    case systemAway
    
    /// System returned from away state (unlock, wake, etc.)
    case systemReturned
    
    /// User requested to resume automatic calendar control
    case resumeAuto
    
    /// Application startup initialization
    case startupInitialize
    
    /// Check if manual override timeout has expired (internal timer event)
    case checkOverrideExpiry
    
    /// User requested to turn the system off (suspend calendar sync, light off)
    case turnOff
    
    /// Hotkey (F13–F20) triggered a manual state override
    case hotkeyPressed(PresenceState)
}
