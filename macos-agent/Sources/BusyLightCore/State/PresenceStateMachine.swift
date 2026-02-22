import Foundation

/// Central coordinator for presence state transitions with override precedence,
/// debounce logic, and mode management (auto vs manual control).
///
/// Thread Safety: @MainActor isolated - all state updates are serialized on main thread.
/// This aligns with EventKit and AppKit requirements in the broader application.
@MainActor
public final class PresenceStateMachine {
    
    // MARK: - State Tracking
    
    private(set) public var currentState: PresenceState
    private(set) public var currentMode: OperatingMode
    private(set) public var currentSource: StateSource
    
    /// State to restore when system returns from away
    private var stateBeforeSystemAway: (state: PresenceState, source: StateSource)?
    
    /// Expiration time for manual overrides (nil = no expiration)
    private var manualOverrideExpiry: Date?
    
    /// Timer for checking manual override expiration
    private var expiryCheckTask: Task<Void, Never>?
    
    // MARK: - Configuration
    
    /// Timeout duration for manual overrides in minutes (nil = no timeout)
    public var manualOverrideTimeoutMinutes: Int? = 120
    
    /// Stabilization window in seconds to prevent rapid state oscillation (0 = disabled)
    public var stateStabilizationSeconds: Int = 0
    
    /// Task tracking stabilization delay (cancel if state changes during stabilization)
    private var stabilizationTask: Task<Void, Never>?
    
    // MARK: - Callbacks
    
    /// Notifies when presence state changes. Called after successful transition.
    public var onStateChanged: (@MainActor (PresenceState, StateSource) -> Void)?
    
    /// Notifies when operating mode changes (auto ↔ manual).
    public var onModeChanged: (@MainActor (OperatingMode) -> Void)?
    
    /// Requests calendar engine to perform immediate sync (called when resuming auto mode).
    public var onRequestCalendarSync: (@MainActor () -> Void)?
    
    // MARK: - Initialization
    
    public init(
        initialState: PresenceState = .unknown,
        initialMode: OperatingMode = .auto
    ) {
        self.currentState = initialState
        self.currentMode = initialMode
        self.currentSource = .startup
        
        uiLogger.logEvent("state.machine.initialized", details: [
            "state": initialState.rawValue,
            "mode": initialMode.rawValue
        ])
    }
    
    deinit {
        expiryCheckTask?.cancel()
        stabilizationTask?.cancel()
    }
    
    // MARK: - Public API
    
    /// Primary entry point for all state change requests.
    /// Validates transitions, enforces precedence, and prevents flapping.
    public func handleEvent(_ event: StateEvent) {
        // Check for expired override before processing event
        if currentMode == .manual {
            checkAndHandleExpiredOverride()
        }
        
        switch event {
        case .calendarUpdated(let newState):
            handleCalendarUpdate(newState)
            
        case .manualOverride(let newState):
            handleManualOverride(newState)
            
        case .systemAway:
            handleSystemAway()
            
        case .systemReturned:
            handleSystemReturned()
            
        case .resumeAuto:
            handleResumeAuto()
            
        case .startupInitialize:
            handleStartupInitialize()
            
        case .checkOverrideExpiry:
            checkAndHandleExpiredOverride()
        }
    }
    
    /// Query current state with full context
    public func getCurrentState() -> (state: PresenceState, source: StateSource, mode: OperatingMode) {
        return (currentState, currentSource, currentMode)
    }
    
    /// Validate whether a transition would be allowed (query only, no side effects)
    public func canTransition(to state: PresenceState, from source: StateSource) -> Bool {
        let result = StateTransition.isAllowed(
            from: currentState,
            to: state,
            currentSource: currentSource,
            requestedBy: source,
            mode: currentMode
        )
        return result.allowed
    }
    
    // MARK: - Event Handlers
    
    private func handleCalendarUpdate(_ newState: PresenceState) {
        // Debounce: no-op if state unchanged
        guard newState != currentState else {
            uiLogger.logEvent("state.transition.ignored", details: [
                "reason": "no-op",
                "currentState": currentState.rawValue,
                "source": "calendar"
            ])
            return
        }
        
        // Validate transition
        let validation = StateTransition.isAllowed(
            from: currentState,
            to: newState,
            currentSource: currentSource,
            requestedBy: .calendar,
            mode: currentMode
        )
        
        guard validation.allowed else {
            uiLogger.logEvent("state.transition.blocked", details: [
                "reason": validation.reason ?? "unknown",
                "requestedBy": "calendar",
                "currentMode": currentMode.rawValue,
                "currentSource": currentSource.rawValue
            ])
            return
        }
        
        // Apply transition with optional stabilization
        applyStateTransition(to: newState, source: .calendar)
    }
    
    private func handleManualOverride(_ newState: PresenceState) {
        // Cancel any pending stabilization when user explicitly overrides
        stabilizationTask?.cancel()
        stabilizationTask = nil
        
        // Manual override always succeeds (unless system away is active)
        if currentSource == .system {
            uiLogger.logEvent("state.transition.blocked", details: [
                "reason": "system-away-active",
                "requestedBy": "manual",
                "requestedState": newState.rawValue
            ])
            return
        }
        
        // Switch to manual mode
        if currentMode == .auto {
            setMode(.manual)
        }
        
        // Set manual override expiration
        if let timeoutMinutes = manualOverrideTimeoutMinutes {
            manualOverrideExpiry = Date().addingTimeInterval(TimeInterval(timeoutMinutes * 60))
            scheduleExpiryCheck(after: timeoutMinutes)
            
            uiLogger.logEvent("state.override.set", details: [
                "state": newState.rawValue,
                "timeoutMinutes": String(timeoutMinutes)
            ])
        } else {
            manualOverrideExpiry = nil
            uiLogger.logEvent("state.override.set", details: [
                "state": newState.rawValue,
                "timeout": "none"
            ])
        }
        
        // Apply state change
        applyStateTransition(to: newState, source: .manual)
    }
    
    private func handleSystemAway() {
        // Store current state to restore later (unless we're already away)
        if currentState != .away {
            stateBeforeSystemAway = (currentState, currentSource)
        }
        
        // System away overrides everything
        applyStateTransition(to: .away, source: .system, forceUpdate: true)
    }
    
    private func handleSystemReturned() {
        // Restore previous state and source
        if let previousState = stateBeforeSystemAway {
            applyStateTransition(
                to: previousState.state,
                source: previousState.source,
                forceUpdate: true
            )
            stateBeforeSystemAway = nil
            
            uiLogger.logEvent("state.system.returned", details: [
                "restoredState": previousState.state.rawValue,
                "restoredSource": previousState.source.rawValue
            ])
        } else {
            // No previous state stored, default to unknown
            applyStateTransition(to: .unknown, source: .system)
        }
    }
    
    private func handleResumeAuto() {
        // Cancel any manual override
        manualOverrideExpiry = nil
        expiryCheckTask?.cancel()
        expiryCheckTask = nil
        
        // Reset source to startup so the incoming calendar update is not blocked
        // by the stale manual source priority when it arrives after the sync.
        currentSource = .startup
        
        // Switch to auto mode
        setMode(.auto)
        
        // Request calendar sync to immediately apply current calendar state
        uiLogger.logEvent("state.calendar.sync.requested", details: [
            "trigger": "resume-auto"
        ])
        onRequestCalendarSync?()
    }
    
    private func handleStartupInitialize() {
        // Set to unknown state at startup
        applyStateTransition(to: .unknown, source: .startup, forceUpdate: true)
    }
    
    // MARK: - Core Transition Logic
    
    private func applyStateTransition(
        to newState: PresenceState,
        source: StateSource,
        forceUpdate: Bool = false
    ) {
        let previousState = currentState
        let previousSource = currentSource
        
        // Apply stabilization delay if configured (unless forced)
        if !forceUpdate && stateStabilizationSeconds > 0 {
            // Cancel any pending stabilization
            stabilizationTask?.cancel()
            
            stabilizationTask = Task { [weak self, stateStabilizationSeconds] in
                do {
                    try await Task.sleep(nanoseconds: UInt64(stateStabilizationSeconds) * 1_000_000_000)
                    
                    // After delay, apply the transition
                    await MainActor.run { [weak self] in
                        self?.executeStateTransition(
                            to: newState,
                            source: source,
                            previousState: previousState,
                            previousSource: previousSource
                        )
                    }
                } catch {
                    // Task was cancelled (state changed during stabilization)
                    uiLogger.logEvent("state.stabilization.cancelled", details: [
                        "targetState": newState.rawValue
                    ])
                }
            }
            return
        }
        
        // No stabilization - apply immediately
        executeStateTransition(
            to: newState,
            source: source,
            previousState: previousState,
            previousSource: previousSource
        )
    }
    
    private func executeStateTransition(
        to newState: PresenceState,
        source: StateSource,
        previousState: PresenceState,
        previousSource: StateSource
    ) {
        currentState = newState
        currentSource = source
        
        uiLogger.logEvent("state.transition.success", details: [
            "from": previousState.rawValue,
            "to": newState.rawValue,
            "source": source.rawValue,
            "mode": currentMode.rawValue,
            "previousSource": previousSource.rawValue
        ])
        
        // Notify observers
        onStateChanged?(newState, source)
    }
    
    private func setMode(_ newMode: OperatingMode) {
        guard newMode != currentMode else { return }
        
        let previousMode = currentMode
        currentMode = newMode
        
        uiLogger.logEvent("state.mode.changed", details: [
            "from": previousMode.rawValue,
            "to": newMode.rawValue
        ])
        
        // Notify observers
        onModeChanged?(newMode)
    }
    
    // MARK: - Override Expiry Management
    
    private func scheduleExpiryCheck(after minutes: Int) {
        expiryCheckTask?.cancel()
        
        expiryCheckTask = Task { [weak self] in
            // Wait for the timeout duration
            try? await Task.sleep(nanoseconds: UInt64(minutes) * 60 * 1_000_000_000)
            
            // Check if override has expired
            await MainActor.run { [weak self] in
                self?.handleEvent(.checkOverrideExpiry)
            }
        }
    }
    
    private func checkAndHandleExpiredOverride() {
        guard let expiry = manualOverrideExpiry else { return }
        
        let now = Date()
        if now >= expiry {
            let duration = Int(-expiry.timeIntervalSinceNow) / 60
            
            uiLogger.logEvent("state.override.expired", details: [
                "durationMinutes": String(duration)
            ])
            
            // Automatically resume auto mode
            handleResumeAuto()
        }
    }
}
