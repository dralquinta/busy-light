import Foundation

/// Validates state transitions based on operating mode and source precedence.
@MainActor
public struct StateTransition: Sendable {
    
    /// Validates whether a transition is allowed based on current mode and source precedence
    public static func isAllowed(
        from currentState: PresenceState,
        to newState: PresenceState,
        currentSource: StateSource,
        requestedBy newSource: StateSource,
        mode: OperatingMode
    ) -> (allowed: Bool, reason: String?) {
        
        // System away always overrides everything
        if newSource == .system {
            return (true, nil)
        }
        
        // In manual mode, only manual or system sources can change state
        if mode == .manual {
            if newSource == .calendar {
                return (false, "manual-override-active")
            }
        }
        
        // Check source precedence: lower priority sources cannot override higher priority
        if newSource.priority < currentSource.priority && currentSource != .startup {
            return (false, "insufficient-priority")
        }
        
        // Startup state can be transitioned to anything
        if currentState == .unknown && currentSource == .startup {
            return (true, nil)
        }
        
        // All other valid transitions are allowed
        return (true, nil)
    }
    
    /// Determines the appropriate state source for a given event
    public static func sourceForEvent(_ event: StateEvent) -> StateSource {
        switch event {
        case .calendarUpdated:
            return .calendar
        case .manualOverride:
            return .manual
        case .systemAway, .systemReturned:
            return .system
        case .startupInitialize:
            return .startup
        case .resumeAuto, .checkOverrideExpiry:
            return .manual // Mode-change events maintain manual source context
        }
    }
    
    /// Determines the target state for a given event
    public static func targetStateForEvent(
        _ event: StateEvent,
        currentState: PresenceState,
        stateBeforeSystemAway: PresenceState?
    ) -> PresenceState? {
        switch event {
        case .calendarUpdated(let state):
            return state
        case .manualOverride(let state):
            return state
        case .systemAway:
            return .away
        case .systemReturned:
            // Restore previous state when returning from system away
            return stateBeforeSystemAway ?? currentState
        case .startupInitialize:
            return .unknown
        case .resumeAuto, .checkOverrideExpiry:
            return nil // These events trigger mode changes, not direct state changes
        }
    }
}
