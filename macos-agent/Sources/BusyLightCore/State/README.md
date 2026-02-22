# Presence State Machine

Centralized coordinator for presence state transitions with override precedence, debounce logic, and mode management.

## Overview

The `PresenceStateMachine` provides deterministic state management for the BusyLight presence indicator, coordinating inputs from:
- **Calendar events** (automatic state resolution)
- **User overrides** (manual state control)
- **System events** (screen lock, sleep, wake)

All state transitions are validated, logged, and occur atomically on the main thread (`@MainActor` isolated).

---

## State Definitions

The system supports five presence states:

| State | Icon | Meaning | Priority in Calendar Resolution |
|-------|------|---------|--------------------------------|
| `available` | 🟢 Green | User is free and available | Lowest (default) |
| `tentative` | 🟠 Orange | User has tentative/unconfirmed calendar event | Medium |
| `busy` | 🔴 Red | User is in a confirmed meeting or manually busy | High |
| `away` | ⚪ Gray | User is away (screen locked, system asleep) | Highest (system-forced) |
| `unknown` | ⚫ Black | Uninitialized or error state | N/A (startup/fallback only) |

### State Semantics

- **`available`**: Default state when no calendar events are active and no overrides are present.
- **`tentative`**: User has a calendar event marked as "tentative" (needs confirmation).
- **`busy`**: User is in a confirmed calendar meeting, or has manually set themselves as busy.
- **`away`**: System-enforced state when screen is locked or system is asleep. Always overrides all other states.
- **`unknown`**: Initial state at application startup before first calendar scan completes. Also used as fallback on errors.

---

## Operating Modes

The state machine operates in one of two modes:

### `auto` Mode (Automatic Calendar Control)
- State is continuously resolved from calendar events
- Calendar updates immediately apply to presence state
- Default mode at startup
- **Precedence**: Calendar events drive state (except when system goes away)

### `manual` Mode (User Override)
- User has manually set a specific presence state
- Calendar updates are **ignored** until user resumes auto mode
- System away events still override manual state (highest precedence)
- **Precedence**: Manual override blocks calendar updates

### Mode Transitions

```
auto ──────────────────────► manual
 │                              │
 │  User manually sets state    │
 │  via UI toggle               │
 │                              │
 │  User clicks "Resume         │
 │  Calendar Control"           │
 │                              │
 └◄────────────────────────────┘
```

---

## Override Precedence Model

State change requests follow a strict precedence hierarchy:

```
┌─────────────────────────────────────┐
│  System Away (Highest Priority)     │ ◄── Screen lock, sleep
│  - Always overrides everything      │
│  - Suspends current state           │
└─────────────────────────────────────┘
              ▼
┌─────────────────────────────────────┐
│  Manual Override (Medium Priority)  │ ◄── User UI toggle
│  - Blocks calendar updates          │
│  - Optional timeout expiration      │
└─────────────────────────────────────┘
              ▼
┌─────────────────────────────────────┐
│  Calendar Events (Lowest Priority)  │ ◄── Automatic resolution
│  - Active only in auto mode         │
│  - Blocked by manual overrides      │
└─────────────────────────────────────┘
```

### Precedence Rules

1. **System away always wins**: When screen locks or system sleeps, state immediately transitions to `away` regardless of current mode or source.

2. **Manual override blocks calendar**: When user manually sets a state, operating mode switches to `manual` and calendar updates are ignored until user resumes auto mode.

3. **Calendar drives auto mode**: When in `auto` mode with no manual override, calendar events determine presence state based on event priority (`busy` > `tentative` > `available`).

4. **System return restores context**: When system wakes or screen unlocks, the state machine restores the previous state and mode that was active before going away.

---

## Transition Rules

### Allowed Transitions

| From State | To State | Allowed Sources | Notes |
|-----------|----------|-----------------|-------|
| Any | `away` | System only | Always allowed |
| `away` | Any | System (on return) | Restores previous state |
| Any | Any | Manual (if not system away) | User can override to any state |
| Any | Any | Calendar (if auto mode) | Calendar updates apply in auto mode |
| `unknown` | Any | Any | Startup allows any first transition |

### Blocked Transitions

Transitions are **blocked** when:
- **Calendar tries to update during manual mode**: Logged as `manual-override-active`
- **Manual override attempted during system away**: Logged as `system-away-active`
- **Lower priority source tries to override higher priority**: Logged as `insufficient-priority`

Blocked transitions are logged but do not change state.

---

## Debounce and Anti-Flapping Logic

The state machine prevents unnecessary state oscillation through several mechanisms:

### 1. No-Op Guard (Primary Debounce)
- If requested state equals current state, transition is ignored
- Logged as: `state.transition.ignored` with `reason: no-op`
- Prevents redundant UI updates and unnecessary downstream actions

### 2. Idempotent Event Processing
- Repeated identical events (e.g., calendar polling returns same state) result in no action
- State machine tracks current state and only fires `onStateChanged` callback when state actually changes

### 3. Optional Stabilization Window
- Configurable delay (default: 0 seconds, disabled)
- When enabled, state transitions are delayed by `stateStabilizationSeconds` to allow "settling time"
- Example use case: Prevent oscillation when meeting ends at 3:00:00 PM but calendar polling occurs at 2:59:58 PM
- Stabilization is cancelled if a higher-priority event arrives (e.g., system away, manual override)
- Configured via: `AppConfiguration.stateStabilizationSeconds`

### 4. Atomic Updates
- All state changes occur synchronously within `@MainActor` context
- No partial state updates or race conditions
- Thread-safe by design (main-thread serialization)

---

## Example Transition Scenarios

### Scenario 1: User Manually Sets Busy During Available Period

```swift
// Initial state: auto mode, available (from calendar)
currentState = .available
currentMode = .auto
currentSource = .calendar

// User clicks "Mark as Busy"
stateMachine.handleEvent(.manualOverride(.busy))

// Result:
currentState = .busy
currentMode = .manual          // ← Mode switched
currentSource = .manual
// UI shows "Resume Calendar Control" button
```

**Log output:**
```
state.override.set [state=busy timeoutMinutes=120]
state.mode.changed [from=auto to=manual]
state.transition.success [from=available to=busy source=manual mode=manual]
```

---

### Scenario 2: System Locks During Manual Override

```swift
// Initial state: manual override to busy
currentState = .busy
currentMode = .manual
currentSource = .manual

// Screen locks
stateMachine.handleEvent(.systemAway)

// Result:
currentState = .away
currentMode = .manual          // ← Mode preserved
currentSource = .system        // ← Source changed (higher priority)
stateBeforeSystemAway = (.busy, .manual)  // ← Saved for restoration
```

**Log output:**
```
state.transition.success [from=busy to=away source=system mode=manual]
```

**On unlock:**
```swift
stateMachine.handleEvent(.systemReturned)

// Result:
currentState = .busy           // ← Restored
currentSource = .manual        // ← Restored
currentMode = .manual          // ← Still manual
```

**Log output:**
```
state.system.returned [restoredState=busy restoredSource=manual]
state.transition.success [from=away to=busy source=manual mode=manual]
```

---

### Scenario 3: Calendar Meeting Starts While Manually Available

```swift
// Initial state: manual override to available
currentState = .available
currentMode = .manual
currentSource = .manual

// Calendar engine detects busy meeting
stateMachine.handleEvent(.calendarUpdated(.busy))

// Result: NO CHANGE (calendar blocked by manual override)
currentState = .available      // ← Unchanged
currentMode = .manual
currentSource = .manual
```

**Log output:**
```
state.transition.blocked [reason=manual-override-active requestedBy=calendar currentMode=manual]
```

---

### Scenario 4: Manual Override Timeout Expires

```swift
// Initial state: manual override set 120 minutes ago
currentState = .busy
currentMode = .manual
manualOverrideExpiry = Date() - 1 second  // Expired

// Timer fires expiry check
stateMachine.handleEvent(.checkOverrideExpiry)

// Result: Auto-resume triggered
currentMode = .auto            // ← Switched back
onRequestCalendarSync()        // ← Callback fired
// Calendar sync will apply current calendar state
```

**Log output:**
```
state.override.expired [durationMinutes=120]
state.mode.changed [from=manual to=auto]
state.calendar.sync.requested [trigger=resume-auto]
```

---

## Configuration Options

### Manual Override Timeout

Controls automatic expiration of manual overrides.

- **Property**: `AppConfiguration.manualOverrideTimeoutMinutes`
- **Default**: `120` (2 hours)
- **Values**:
  - `nil` = No timeout (override persists until explicitly cleared)
  - `1...n` = Timeout in minutes
- **UserDefaults Key**: `app.manual_override_timeout`
- **Behavior**: When timeout expires, operating mode automatically switches to `auto` and calendar sync is triggered

**Example:**
```swift
// Set 30-minute timeout for manual overrides
ConfigurationManager.shared.setManualOverrideTimeoutMinutes(30)

// Disable timeout (manual override persists indefinitely)
ConfigurationManager.shared.setManualOverrideTimeoutMinutes(nil)
```

---

### State Stabilization Delay

Prevents rapid oscillation at calendar event boundaries.

- **Property**: `AppConfiguration.stateStabilizationSeconds`
- **Default**: `0` (disabled)
- **Values**:
  - `0` = No stabilization (immediate transitions)
  - `1...n` = Delay in seconds before applying transition
- **UserDefaults Key**: `app.state_stabilization`
- **Behavior**: State transitions are delayed by specified duration. Delay is cancelled if higher-priority event arrives.

**Example:**
```swift
// Add 30-second stabilization window
ConfigurationManager.shared.setStateStabilizationSeconds(30)

// Disable stabilization (immediate transitions)
ConfigurationManager.shared.setStateStabilizationSeconds(0)
```

---

## Logging

All state machine events are logged using `uiLogger` with structured details.

### Log Events

| Event | Details | When |
|-------|---------|------|
| `state.machine.initialized` | `state`, `mode` | State machine created |
| `state.transition.success` | `from`, `to`, `source`, `mode`, `previousSource` | State change applied |
| `state.transition.ignored` | `reason`, `currentState`, `source` | No-op or duplicate |
| `state.transition.blocked` | `reason`, `requestedBy`, `currentMode`, `currentSource` | Precedence violation |
| `state.mode.changed` | `from`, `to` | Operating mode switched |
| `state.override.set` | `state`, `timeoutMinutes` or `timeout` | Manual override activated |
| `state.override.expired` | `durationMinutes` | Timeout triggered |
| `state.system.returned` | `restoredState`, `restoredSource` | System wake/unlock |
| `state.calendar.sync.requested` | `trigger` | Calendar scan triggered |
| `state.stabilization.cancelled` | `targetState` | Stabilization interrupted |

### Viewing Logs

**Stream all state machine logs:**
```bash
log stream --predicate 'subsystem == "com.busylight.agent.ui"' --level debug
```

**Filter for specific events:**
```bash
log stream --predicate 'subsystem == "com.busylight.agent.ui" AND eventMessage CONTAINS "state.transition"' --level debug
```

**Show only blocked transitions:**
```bash
log stream --predicate 'subsystem == "com.busylight.agent.ui" AND eventMessage CONTAINS "blocked"' --level debug
```

---

## API Reference

### `PresenceStateMachine`

Main coordinator class.

#### Initialization
```swift
init(initialState: PresenceState = .unknown, initialMode: OperatingMode = .auto)
```

#### Properties
```swift
// Current state tracking (read-only)
private(set) public var currentState: PresenceState
private(set) public var currentMode: OperatingMode
private(set) public var currentSource: StateSource

// Configuration
public var manualOverrideTimeoutMinutes: Int?  // Default: 120
public var stateStabilizationSeconds: Int      // Default: 0
```

#### Callbacks
```swift
// Notifies when presence state changes
public var onStateChanged: (@MainActor (PresenceState, StateSource) -> Void)?

// Notifies when operating mode changes
public var onModeChanged: (@MainActor (OperatingMode) -> Void)?

// Requests calendar engine to perform immediate sync
public var onRequestCalendarSync: (@MainActor () -> Void)?
```

#### Methods
```swift
// Primary event handler
public func handleEvent(_ event: StateEvent)

// Query current state with full context
public func getCurrentState() -> (state: PresenceState, source: StateSource, mode: OperatingMode)

// Validate whether a transition would be allowed
public func canTransition(to state: PresenceState, from source: StateSource) -> Bool
```

---

### `StateEvent`

Input events that trigger state machine transitions.

```swift
public enum StateEvent: Sendable {
    case calendarUpdated(PresenceState)  // Calendar engine detected state change
    case manualOverride(PresenceState)   // User manually set state via UI
    case systemAway                      // System locked or went to sleep
    case systemReturned                  // System unlocked or woke up
    case resumeAuto                      // User clicked "Resume Calendar Control"
    case startupInitialize               // Application startup
    case checkOverrideExpiry             // Internal timer event
}
```

---

### `StateSource`

Indicates the origin of a state transition.

```swift
public enum StateSource: String, Sendable, Codable {
    case calendar  // Priority: 1 (lowest)
    case manual    // Priority: 2
    case system    // Priority: 3 (highest)
    case startup   // Priority: 0 (special)
    
    public var priority: Int { ... }
}
```

---

### `OperatingMode`

Operating mode controlling automatic vs manual state resolution.

```swift
public enum OperatingMode: String, Sendable, Codable {
    case auto    // Calendar-driven
    case manual  // User override active
}
```

---

## Integration Example

Typical integration in `BusyLightApp`:

```swift
// 1. Create state machine
let stateMachine = PresenceStateMachine(initialState: .unknown, initialMode: .auto)
stateMachine.manualOverrideTimeoutMinutes = ConfigurationManager.shared.getManualOverrideTimeoutMinutes()
stateMachine.stateStabilizationSeconds = ConfigurationManager.shared.getStateStabilizationSeconds()

// 2. Wire state machine to UI
stateMachine.onStateChanged = { [weak controller] state, source in
    controller?.updatePresenceState(state)
}

stateMachine.onModeChanged = { [weak controller] mode in
    controller?.updateModeDisplay(mode)
}

// 3. Wire calendar engine to state machine
calendarEngine.onAvailabilityChange = { [weak stateMachine] state in
    stateMachine?.handleEvent(.calendarUpdated(state))
}

// 4. Wire system monitor to state machine
systemMonitor.onUserAway = { [weak stateMachine] in
    stateMachine?.handleEvent(.systemAway)
}

systemMonitor.onUserReturned = { [weak stateMachine] in
    stateMachine?.handleEvent(.systemReturned)
}

// 5. Wire UI manual override to state machine
statusMenuController.onManualOverride = { [weak stateMachine] state in
    stateMachine?.handleEvent(.manualOverride(state))
}

statusMenuController.onResumeCalendarControl = { [weak stateMachine] in
    stateMachine?.handleEvent(.resumeAuto)
}

// 6. Wire state machine callback to trigger calendar sync
stateMachine.onRequestCalendarSync = { [weak calendarEngine] in
    Task { await calendarEngine?.scanNow() }
}

// 7. Initialize
stateMachine.handleEvent(.startupInitialize)
```

---

## Thread Safety

All state machine components are `@MainActor` isolated:
- **Reason**: Integration with EventKit and AppKit requires main thread access
- **Guarantee**: All state updates are serialized on the main thread
- **Implication**: No explicit locking required; Swift's actor isolation provides safety

All types are `Sendable` for safe cross-isolate passing.

---

## Performance Characteristics

- **State transition latency**: < 1 ms (synchronous, no I/O)
- **Memory overhead**: ~200 bytes (state tracking only)
- **Calendar poll frequency**: 60 seconds (configurable in `CalendarEngine`)
- **Override expiry check**: Scheduled timer (no active polling)
- **Stabilization delay**: Optional, configurable (0-60 seconds typical)

**Optimization note:** No-op guard prevents redundant downstream actions (device updates, network calls) when state hasn't changed.

---

## Future Enhancements

Potential improvements for future versions:

1. **State history/audit trail**: Track last N transitions for debugging
2. **Metrics export**: Expose state change counters for observability dashboards
3. **Custom transition rules**: User-defined policy engine for advanced scenarios
4. **Multi-device coordination**: Sync state across multiple devices
5. **Smart timeout prediction**: ML-based auto-resume based on user patterns
6. **Voice/gesture integration**: Additional input sources beyond calendar/UI

---

## See Also

- [CalendarEngine.swift](../Calendar/CalendarEngine.swift) - Calendar event polling and resolution
- [SystemPresenceMonitor.swift](../System/SystemPresenceMonitor.swift) - Screen lock and sleep detection
- [StatusMenuController.swift](../UI/StatusMenuController.swift) - Menu bar UI and user interaction
- [CalendarAvailabilityResolver.swift](../Calendar/CalendarAvailabilityResolver.swift) - Event priority resolution logic
