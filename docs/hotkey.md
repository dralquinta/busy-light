# Global Hotkey Integration Guide

**Status**: ✅ Functional (as of February 2026)  
**Last Updated**: February 22, 2026

## Overview

BusyLight supports global hotkeys for quick presence state changes without opening the menu or Calendar app. Users can press keyboard combinations to immediately override their calendar-based status for a configurable period (default: 30 minutes).

## Hotkey Bindings

Default key combinations require **Left Control + Left Command** held together with a number key:

| Combination | Presence State | Key Code | Description |
|---|---|---|---|
| **Ctrl+Cmd+1** | Available | 18 | Sets availability to free/available |
| **Ctrl+Cmd+2** | Tentative | 19 | Sets status to tentatively booked |
| **Ctrl+Cmd+3** | Busy | 20 | Sets status to busy/do not disturb |
| **Ctrl+Cmd+4** | (Resume Calendar) | 21 | Cancels override, resumes calendar control |
| **F16** | Away | 106 | Sets status to away/offline |
| **F17** | Off | 64 | Turns off the light (pauses all monitoring) |

All bindings are fully customizable via the "Configure Hotkeys" menu (⚙︎ → Configure Hotkeys → Edit preferences).

## Behavior

### When a Hotkey is Pressed (Ctrl+Cmd+1/2/3, F16, F17)
1. **Immediate state change** — Presence status changes to the mapped state within milliseconds
2. **Override active** — Calendar synchronization pauses for the configured timeout duration (default: 30 minutes)
3. **Menu bar updates** — BusyLight icon and status display update immediately
4. **Device communicates** — New status is sent to the busy-light hardware device
5. **Logging** — Event is logged: `hotkey.pressed [keyCode=... targetState=...]`

### When Resume Calendar (Ctrl+Cmd+4) is Pressed

**This hotkey has ABSOLUTE PRIORITY over all other operations, including pending timeouts and active overrides.**

Sequence of operations:
1. **Override canceled immediately** — Manual override is unconditionally terminated, regardless of remaining timeout
2. **Stabilization canceled** — Any pending state transitions are canceled to ensure immediate effect
3. **Source reset** — Internal state source reset to ensure calendar updates are not blocked
4. **Operating mode switched** — System immediately switches from manual to auto mode
5. **Calendar rescan triggered** — System automatically rescans calendar without delay
6. **Status updated** — Presence state changes to match current calendar availability
7. **Device updates** — Hardware light reflects the calendar-based status immediately
8. **Logging** — Event is logged with priority flag: `hotkey.resume_calendar [priority=absolute, timestamp=...]`

**Implementation Detail**: In `PresenceStateMachine`, `resumeAuto` events are processed at the very top of event handling, before checking for expired overrides or processing other state changes. This ensures the hotkey always takes precedence.

This hotkey is essential for:
- **Emergency override cancellation** — Immediately regain calendar control if a manual override is no longer needed
- **Timeout bypass** — Don't wait for manual override timeout to expire (default 30 minutes)
- **Forcing immediate sync** — Guarantee current calendar state is applied without delay
- **Restoring calendar authority** — Give calendar control back to automatic mode at any time

### After Override Timeout Expires (without Ctrl+Cmd+4)
1. **Calendar rescan** — System automatically re-scans calendar for current availability
2. **Status returns** — Presence state changes back to calendar-based value
3. **Manual override ends** — Hotkeys stop taking precedence until pressed again

## Technical Implementation

### Architecture

**HotkeyManager** (`Sources/BusyLightCore/System/HotkeyManager.swift`)
- Singleton-like component managing global keyboard event monitoring
- Uses `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)` to capture all keyboard events
- **Main-actor isolated** for thread safety with macOS AppKit
- Requires macOS Accessibility API permission

**Key Components:**
- `start()` — Begins listening for keyboard events
- `stop()` — Closes the global event monitor
- `updateBindings()` — Changes hotkey-to-state mappings (resets monitor if active)
- `handleKeyDown()` — Processes keystroke event, checks modifiers (Ctrl+Cmd), matches key code, invokes callback
- `onHotkeyPressed` — Callback property invoked when a registered hotkey matches

**State Machine Integration:**
- Hotkey events dispatched as `StateEvent.hotkeyPressed(PresenceState)`
- State machine calls `handleHotkeyOverride()` which invokes `handleManualOverride()`
- Manual override logic enforces timeout (default 30 min) before returning to calendar sync

**Configuration & Persistence:**
- `AppConfiguration.hotkeyBindings` — Dictionary mapping `PresenceState` to key codes (UInt16)
- `ConfigurationManager.getHotkeyBindings()` / `setHotkeyBindings()` — UserDefaults I/O
- Persisted to `~/Library/Preferences/com.example.BusyLight.plist` under key `app.hotkey_bindings`

**User Interface:**
- **Configure Hotkeys menu** — Shows current bindings in human-readable format (e.g., "Available: Ctrl+Cmd+1")
- **Edit preferences button** — Opens `HotkeyPreferencesController` window for reconfiguration
- **Keystroke capture** — Uses `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` when editing

### Carbon Virtual Key Codes

BusyLight uses Carbon/ANSI key codes to represent physical keys, independent of keyboard layout:

```
Number row: 18 (1), 19 (2), 20 (3), 21 (4), 23 (5), 22 (6), 26 (7), 28 (8), 25 (9), 29 (0)
Function keys: 105 (F13), 107 (F14), 113 (F15), 106 (F16), 64 (F17), 79 (F18), 80 (F19), 90 (F20)
```

### Modifier Key Handling

The implementation checks `NSEvent.modifierFlags` for required modifier combinations:

```swift
let hasControl = event.modifierFlags.contains(.control)
let hasCmd = event.modifierFlags.contains(.command)
if !hasControl || !hasCmd { skip() }  // Reject if either missing
```

Currently applies to:
- **Keys 1, 2, 3** (mapped in `hotkeyBindings` as PresenceState bindings) — Ctrl+Cmd+1/2/3 for Available, Tentative, Busy
- **Key 4** (Resume Calendar) — Ctrl+Cmd+4 for immediate calendar control resumption (checked separately in `handleKeyDown()` before the hotkeyBindings loop)
- **Function keys (F16, F17)** — Don't require modifiers, work as standalone hotkeys

**Implementation Note**: Resume Calendar (key 21/Ctrl+Cmd+4) is verified with the same modifier checking as keys 1-3, but processed outside the `hotkeyBindings` loop since it's not a PresenceState mapping. This ensures consistent behavior across all Ctrl+Cmd combinations.

### Logging

Successful hotkey presses generate `hotkey.pressed` events:
```
hotkey.pressed [keyCode=18 targetState=available timestamp=2026-02-22T14:30:45Z]
```

Resume Calendar control activation generates:
```
hotkey.resume_calendar [timestamp=2026-02-22T14:30:45Z]
```

## Permission Requirements

### macOS Accessibility Permission

**Why needed**: `NSEvent.addGlobalMonitorForEvents()` requires the Accessibility API to intercept keyboard events system-wide.

**How to grant**:
1. System Settings → Privacy & Security → Accessibility
2. Look for "BusyLight" in the list
3. If missing: Drag `BusyLight.app` from Applications folder into the list, OR click "+" and navigate to the app
4. Toggle ON to enable

**Troubleshooting**:
- **"Accessibility permission popup keeps appearing"** — Bundle code signature mismatch with system's accessibility database. Fix:
  1. Remove BusyLight from Accessibility list (click minus button)
  2. Force-quit BusyLight (Cmd+Q or Terminal: `killall BusyLight`)
  3. Restart app: `./debug.sh`
  4. Grant permission when prompted
  5. Close and reopen app for full functionality

- **"Permission check passes but hotkeys don't work"** — Accessibility permission requires app restart to take effect. After granting:
  1. Close BusyLight completely
  2. Reopen: `./debug.sh` or double-click BusyLight.app

### Calendar Permission

**Why needed**: Calendar event scanning requires access to Calendar.app database.

**How to grant**:
1. System Settings → Privacy & Security → Calendars
2. Find "BusyLight" in the list
3. Toggle ON

## Build & Setup

### Standard Build
```bash
cd /Users/dralquinta/Documents/DevOps/busy-light
./build.sh
open BusyLight.app
```

### Debug Build with Logging
```bash
./debug.sh
```
Streams live logs to terminal with filter: `subsystem BEGINSWITH "com.busylight.agent"`

### First-Run / After Code Changes
1. **Remove Accessibility permission** (System Settings → Privacy & Security → Accessibility)
   - Click BusyLight, then minus button
2. **Rebuild**: `./build.sh`
3. **Open app**: `open BusyLight.app`
4. **Grant Accessibility permission** when prompted
5. **Grant Calendar permission** if asked
6. **Close and reopen** the app using `./debug.sh`
7. **Test hotkeys**: Press Ctrl+Cmd+1, Ctrl+Cmd+2, Ctrl+Cmd+3, F16, or F17

## Testing Hotkeys

### Manual Testing

1. **Launch app** with debug logging:
   ```bash
   ./debug.sh
   ```

2. **Press a hotkey** (e.g., **Ctrl+Cmd+1** for Available):
   - Menu bar icon should update immediately
   - Terminal should show: `hotkey.pressed [keyCode=18 targetState=available ...]`
   - Status should remain unchanged for 30 minutes (timeout)

3. **After 30 minutes** (or manually set shorter timeout):
   - Status automatically returns to calendar-based value
   - Application rescans calendar

4. **Test Keystroke Capture**:
   - Menu → Configure Hotkeys → Edit preferences for custom bindings
   - Click any binding button (e.g., "Available")
   - Press a key
   - Button should update with new key name
   - Status shows: "✓ Updated [State] → [Key]"

### Validation Checklist

- [ ] Ctrl+Cmd+1 sets status to Available
- [ ] Ctrl+Cmd+2 sets status to Tentative
- [ ] Ctrl+Cmd+3 sets status to Busy
- [ ] Ctrl+Cmd+4 cancels override and returns to calendar status
- [ ] **Ctrl+Cmd+4 has priority**: Press Ctrl+Cmd+1, then immediately press Ctrl+Cmd+4 before timeout expires → status should return to calendar value
- [ ] F16 sets status to Away
- [ ] F17 sets status to Off
- [ ] Status persists for exactly 30 minutes after hotkey press (1/2/3 only)
- [ ] Status returns to calendar-based value after timeout
- [ ] Pressing Ctrl+Cmd+4 during override immediately resumes calendar control (no timeout wait)
- [ ] Menu displays correct hotkey bindings
- [ ] Debug menu shows hotkey debug info
- [ ] Custom hotkey bindings persist across app restarts

## Configuration

### Changing Default Bindings

Edit [AppConfiguration.swift](../macos-agent/Sources/BusyLightCore/Models/AppConfiguration.swift):

```swift
public var hotkeyBindings: [String: UInt16] = [
    PresenceState.available.rawValue: 18,    // Ctrl+Cmd+1
    PresenceState.tentative.rawValue: 19,   // Ctrl+Cmd+2
    PresenceState.busy.rawValue: 20,        // Ctrl+Cmd+3
    PresenceState.away.rawValue: 106,       // F16
    PresenceState.off.rawValue: 64          // F17
]
```

### Changing Override Timeout

Edit [AppConfiguration.swift](../macos-agent/Sources/BusyLightCore/Models/AppConfiguration.swift):

```swift
/// Manual override timeout in minutes (default 30 minutes)
public var manualOverrideTimeoutMinutes: Int? = 30
```

Set to `nil` to disable timeout (overrides persist indefinitely until next hotkey press or Ctrl+Cmd+4).

**IMPORTANT**: The **Ctrl+Cmd+4** hotkey (Resume Calendar) ALWAYS has absolute priority and immediately cancels ANY active override, regardless of remaining timeout. This timeout setting only applies to automatic expiration via `Ctrl+Cmd+1/2/3`. Users can override timeouts at any time by pressing Ctrl+Cmd+4.

## Known Limitations & Future Work

### Current Limitations
1. **Function keys (F16/F17) don't support modifiers** — They're designed to work alone as simple single-key hotkeys
2. **Keystroke capture UI** — Currently uses local event monitor (standard macOS approach); not available if another app has keyboard focus
3. **No key repeat handling** — Holding a key triggers multiple events; implementation doesn't deduplicate
4. **No Stream Deck native support** — Stream Deck buttons are detected as regular keystrokes with their native key codes; direct SDK integration not yet implemented

### Future Enhancements
1. **Advanced key combo support** — Arbitrary modifier combinations on any key
2. **Device integration** — Native Stream Deck SDK integration for hardware button detection
3. **Macro support** — Single hotkey could trigger state + message combo
4. **Conflict detection** — Warn if binding matches system hotkeys (e.g., Spotlight)
5. **Per-calendar overrides** — Different hotkey bindings for different calendar views

## Troubleshooting

### "Hotkeys not working"

**Check accessibility permission:**
1. Open Console.app (Applications → Utilities)
2. Filter: `process == "BusyLight"`
3. Look for: `hotkey.monitor.started [monitorActive=true]`
   - If `monitorActive=false`: Accessibility permission not granted
   - If log doesn't appear: App not launching correctly

**Try permission reset workflow:**
1. System Settings → Privacy & Security → Accessibility
2. Click minus button next to BusyLight
3. `killall BusyLight`
4. `./debug.sh`
5. Grant permission when popup appears
6. Close BusyLight (`Cmd+Q`)
7. Open again: `open BusyLight.app`
8. Test hotkey

### "I assigned a hotkey but it won't save"

**Try manual defaults write:**
```bash
defaults write com.example.BusyLight app.hotkey_bindings '{ available = 18; }'
```

Then restart the app.

### "Hotkey captured timestamp is 1000s too old"

This is a known macOS behavior—keystrokes are timestamped when the event queue processes them, not when the key is physically pressed. ~1-3 seconds delay is normal.

## Architecture Decisions

### Why NSEvent Global Monitor?
- **Pros**: Simple, built-in, no framework dependencies, works with all hardware (keyboard, Stream Deck, etc.)
- **Cons**: Requires Accessibility permission, no repeat-key deduplication
- **Alternative considered**: EventKit or IOKit (more complex, less compatible)

### Why Carbon Key Codes?
- **Pros**: Keyboard-layout-independent, matches system conventions, works across macOS versions
- **Cons**: Not human-readable (need translation layer)
- **Trade-off**: Implemented `keyCodeToName()` for display purposes

### Why Manual Override + Timeout Pattern?
- **Pros**: Simple to understand, calendar eventually takes precedence, no ambiguous states
- **Cons**: Fixed timeout may not suit all users
- **Future**: Could add "Ask on override" or "Confirm every hour" modes

## Code Reference

**Main files:**
- `Sources/BusyLightCore/System/HotkeyManager.swift` — Global keyboard monitoring (200+ lines)
  - `onHotkeyPressed` callback — Triggered when Ctrl+Cmd+1/2/3 or F16/F17 pressed
  - `onResumeCalendarControl` callback — Triggered when Ctrl+Cmd+4 pressed
- `Sources/BusyLightCore/UI/HotkeyPreferencesController.swift` — Configuration UI (347 lines)
- `Sources/BusyLightCore/State/PresenceStateMachine.swift` — `handleHotkeyOverride()` method
- `Sources/BusyLight/BusyLightApp.swift` — Initialization, callback wiring
- `Sources/BusyLightCore/Models/AppConfiguration.swift` — Binding persistence

**Tests:**
- `Tests/BusyLightTests/` — No dedicated hotkey tests yet (planned)

## See Also

- [State Machine Architecture](state-machine.md) — How hotkey events flow through the state system
- [macOS Presence Agent](macOS-presence-agent-menuskeleton.md) — Complete system design
- [Calendar Integration](eventkit-calendar-integration.md) — Calendar scanning (hotkey overrides this)

---

**Last Verified**: February 22, 2026  
**Maintainer**: DevOps / Engineering Team
