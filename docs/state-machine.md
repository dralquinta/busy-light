# State Machine Architecture

BusyLight uses a hierarchical state machine to coordinate presence state across multiple independent sources: calendar events, manual overrides, and system lock/unlock events. This document describes the design, states, modes, and transition logic.

## Overview

The **PresenceStateMachine** is the central coordinator. It:
- Validates all incoming state change requests via **StateTransition** rules
- Enforces source precedence to prevent lower-priority sources from overriding higher-priority ones
- Manages operating modes (automatic calendar-driven, manual overrides, off/suspended)
- Debounces rapid state oscillations via optional stabilization delays
- Handles manual override expiration (with configurable timeout)
- Notifies UI and components of state changes via callbacks

## Presence States

The **PresenceState** enum defines the user's availability:

| State | Display Name | Icon | Meaning |
|-------|--------------|------|---------|
| `.available` | Available | 🟢 | User is available |
| `.busy` | Busy | 🔴 | User is in a meeting or busy |
| `.away` | Away | ⚪ | User is away or screen locked |
| `.tentative` | Tentative | 🟠 | User has a tentatively accepted event |
| `.unknown` | Unknown | ⚫ | Initial state or unresolved condition |
| `.off` | Off | ⬛ | System suspended — no syncing, light is off |

## Operating Modes

The **OperatingMode** enum controls how state is determined:

### `.auto` (Automatic Calendar-Driven)
- Calendar engine continuously scans events and updates state
- System lock/unlock is monitored (screen lock → `.away`, unlock → restore previous)
- No manual overrides active
- This is the default mode at startup

### `.manual` (User Override)
- User has explicitly set the presence state via the menu or debug UI
- Calendar updates are **ignored** until `.manual` mode is exited
- Manual override has an optional timeout (configurable via GUI, default 2 hours)
- After timeout expires, the system automatically resumes `.auto` mode
- User can explicitly resume `.auto` via "Resume Calendar Control" menu item

### `.off` (System Suspended)
- **All syncing is disabled** — calendar engine updates are ignored
- System lock/unlock events are ignored
- No debounce/stabilization tasks are scheduled
- The light is turned off (`PresenceState.off`, icon ⬛)
- Label shows "Calendar: Disabled"
- "Resume Calendar Control" menu item is visible and resumes `.auto` mode
- Any manual override (via toggle button, Debug menu, or other UI) will turn the system **back on** in `.manual` mode and apply the chosen state

> **Key Behavior**: `.off` mode is intended as a full system suspension for when the user wants to completely disconnect BusyLight. It is only exited via explicit manual action (Resume, or manual override).

## State Sources & Priority

Each state change has a **source**, which determines its priority in conflict resolution:

| Source | Priority | Meaning |
|--------|----------|---------|
| `.system` | 3 (highest) | Screen lock/unlock events |
| `.manual` | 2 | User-initiated overrides |
| `.calendar` | 1 | Calendar engine updates |
| `.startup` | 0 (lowest) | Initialization (can be overridden by anything) |

When multiple sources want to update state simultaneously, the source with the highest priority wins. Lower-priority sources are blocked until the higher-priority condition clears.

### Example
- Calendar says "Available" (priority 1)
- User overrides to "Busy" (priority 2, `.manual`) → State becomes Busy, calendar updates ignored
- Screen locks (priority 3, `.system`) → State becomes Away, manual override kept in memory
- Screen unlocks (system source returns) → State returns to Busy (restores manual override)
- User resolves ("Resume Calendar Control") → State returns to calendar-driven, next update applies

## State Transitions

### Validation Rules

A transition is **allowed** if:

1. **In `.off` mode** → Block all calendar and system events. Only allow manual or startup sources (to re-enable the system).
2. **In `.manual` mode** → Block calendar events. Allow manual and system events.
3. **In `.auto` mode** → Allow all events.
4. **System events** → Always allowed (override everything, except when `.off` blocks them).
5. **Startup source** → Can transition from `.unknown` to any state freely.
6. **Source precedence** → A lower-priority source cannot override a higher-priority source unless the higher-priority source is `.startup`.

### Transition Table

| Event | Source | Allowed From Mode | Result |
|-------|--------|-------------------|--------|
| `calendarUpdated(state)` | `.calendar` | `.auto` only | Update to `state` |
| `manualOverride(state)` | `.manual` | Any (escapes `.off`) | Switch to `.manual`, update to `state` |
| `systemAway` | `.system` | Any except `.off` | Update to `.away`, save previous state |
| `systemReturned` | `.system` | Any except `.off` | Restore previous state |
| `resumeAuto` | `.startup` | Any | Switch to `.auto`, reset source, request calendar sync |
| `turnOff` | `.startup` | Any | Switch to `.off`, update to `.off` state |
| `startupInitialize` | `.startup` | Any | Initialize to `.unknown` |
| `checkOverrideExpiry` | `.manual` | `.manual` only | Check timeout, resume `.auto` if expired |

## Events

The **StateEvent** enum defines the inputs to the state machine:

```swift
public enum StateEvent {
    case calendarUpdated(PresenceState)    // Calendar engine detected a change
    case manualOverride(PresenceState)     // User manually set state
    case systemAway                        // Screen locked or system sleeping
    case systemReturned                    // Screen unlocked or system waking
    case resumeAuto                        // User clicked "Resume Calendar Control"
    case turnOff                           // User clicked "Turn Off BusyLight"
    case startupInitialize                 // Application startup
    case checkOverrideExpiry               // Timer: check if override has timed out
}
```

## Configuration

The state machine behavior is configured via **AppConfiguration** and persisted in UserDefaults:

### Manual Override Timeout
- **Key**: `app.manual_override_timeout`
- **Type**: `Int?` (minutes)
- **Default**: `120` (2 hours)
- **Special Value**: `-1` in UserDefaults means `nil` (never timeout)
- **UI**: "Override Timeout" submenu in main menu (15 min, 30 min, 60 min, 2 hours, 4 hours, Never)

When set to `nil`, manual overrides never expire automatically.

### State Stabilization Delay
- **Key**: `app.state_stabilization`
- **Type**: `Int` (seconds)
- **Default**: `0` (disabled)
- **Purpose**: Prevents rapid oscillation when calendar events are overlapping or conflicting

When configured (>0), each calendar update is delayed by the specified duration. If another event arrives during the delay, the delay is restarted. This smooths brief state fluctuations.

## Callbacks

The state machine notifies observers via these callbacks:

### `onStateChanged: (PresenceState, StateSource) -> Void`
Called after a successful state transition, with the new state and its source.

### `onModeChanged: (OperatingMode) -> Void`
Called when operating mode changes (auto ↔ manual, manual ↔ off, etc.).

### `onRequestCalendarSync: () -> Void`
Called when resuming auto mode to trigger an immediate calendar scan.

## Wiring in BusyLightApp

```swift
// Calendar engine → state machine
engine.onAvailabilityChange = { state in
    machine.handleEvent(.calendarUpdated(state))
}

// System monitor → state machine
monitor.onUserAway = { machine.handleEvent(.systemAway) }
monitor.onUserReturned = { machine.handleEvent(.systemReturned) }

// State machine → UI
machine.onStateChanged = { state, source in
    controller.updatePresenceState(state)
    if source == .calendar || source == .startup, state != .off {
        controller.setCalendarEngineStatus(...)
    }
}

machine.onModeChanged = { mode in
    controller.updateModeDisplay(mode)
}

machine.onRequestCalendarSync = { Task { await engine?.scanNow() } }

// UI → state machine
controller.onManualOverride = { state in machine.handleEvent(.manualOverride(state)) }
controller.onResumeCalendarControl = { machine.handleEvent(.resumeAuto) }
controller.onTurnOff = { machine.handleEvent(.turnOff) }
```

## Scenarios

### Scenario 1: User Manually Overrides During Calendar Meetings
1. Calendar detects user is in a meeting → state = `.busy`
2. User clicks "Mark as Available" → mode switches to `.manual`, state = `.available`
   - Calendar updates are now **ignored**
   - UI shows "Calendar: Overridden", "Resume Calendar Control" appears
3. After 2 hours (default timeout), override expires
   - Mode switches to `.auto`
   - Calendar scan runs immediately, applies current event state
4. User can also click "Resume Calendar Control" to exit `.manual` immediately

### Scenario 2: Screen Lock During Manual Override
1. User has manually set state to `.available` (`.manual` mode)
2. Screen locks → system event with priority 3
   - State becomes `.away` (system event always wins)
   - Override is saved in memory
3. Screen unlocks → system returns
   - State restores to `.available` (the saved manual override)
   - Remains in `.manual` mode; override timer continues

### Scenario 3: User Turns System Off
1. User clicks "Turn Off BusyLight"
   - Mode = `.off`, state = `.off`, icon = ⬛
   - Calendar label shows "Calendar: Disabled"
   - "Resume Calendar Control" menu item appears
   - All stabilization and override tasks are cancelled
2. Calendar engine continues running in the background (for persistence) but updates are **blocked** at state machine
3. System lock/unlock events are also **blocked**
4. User can:
   - Click "Resume Calendar Control" → mode = `.auto`, calendar scan runs
   - Click "Mark as Busy" (or any manual override) → mode = `.manual`, state = `.busy`, light turns back on

### Scenario 4: Turning On via Manual Override from Off
1. Currently in `.off` mode (light is ⬛, calendar is disabled)
2. User clicks "Mark as Busy" via toggle or Debug menu
   - Mode switches to `.manual` (escapable from `.off`)
   - State becomes `.busy`
   - Manual override timeout starts
   - Light turns on to 🔴

## Logging

All significant state machine events are logged via `OSLog` (uiLogger, lifecycleLogger, calendarLogger). Key events:

- `state.transition.success` — Transition completed
- `state.transition.blocked` — Transition rejected (with reason)
- `state.transition.ignored` — No-op due to debounce or off mode
- `state.mode.changed` — Operating mode switched
- `state.override.set` — Manual override activated
- `state.override.expired` — Timeout fired
- `state.system.away` / `state.system.returned` — System lock/unlock
- `state.system.off` — User turned off system
- `state.calendar.sync.requested` — Requested calendar scan

Logs can be viewed in Console.app filtered by subsystem `BusyLight`.

## Implementation Files

- **[State/PresenceStateMachine.swift](../macos-agent/Sources/BusyLightCore/State/PresenceStateMachine.swift)** — Core state machine logic
- **[State/StateTransition.swift](../macos-agent/Sources/BusyLightCore/State/StateTransition.swift)** — Transition validation rules
- **[State/StateEvent.swift](../macos-agent/Sources/BusyLightCore/State/StateEvent.swift)** — Event definitions
- **[State/StateSource.swift](../macos-agent/Sources/BusyLightCore/State/StateSource.swift)** — Source priority definitions
- **[State/OperatingMode.swift](../macos-agent/Sources/BusyLightCore/State/OperatingMode.swift)** — Mode definitions
- **[Models/PresenceState.swift](../macos-agent/Sources/BusyLightCore/Models/PresenceState.swift)** — State definitions
- **[Core/ConfigurationManager.swift](../macos-agent/Sources/BusyLightCore/Core/ConfigurationManager.swift)** — Persistence
- **[UI/StatusMenuController.swift](../macos-agent/Sources/BusyLightCore/UI/StatusMenuController.swift)** — UI wiring
- **[BusyLight/BusyLightApp.swift](../macos-agent/Sources/BusyLight/BusyLightApp.swift)** — Lifecycle wiring
