# Away Status Hotkey Guide

**Status**: ✅ Functional (as of February 2026)  
**Last Updated**: February 22, 2026

## Overview

The Away status can be triggered via **Left Control + Left Command + 6** (Ctrl+Cmd+6). This hotkey immediately sets your presence to "Away" and blocks calendar synchronization for 30 minutes, allowing you to temporarily override calendar-driven status changes.

## Quick Start

1. **Press**: `Ctrl+Cmd+6` (hold Left Control + Left Command, then press 6)
2. **Result**: Menu bar icon changes to ⚪ (white circle) — status set to Away
3. **Duration**: 30 minutes (can be extended at any time by pressing Ctrl+Cmd+6 again)
4. **Resume**: Press `Ctrl+Cmd+4` to immediately return to calendar-driven status

## Hotkey Trigger Algorithm

### Phase 1: Global Hotkey Detection

When you press **Ctrl+Cmd+6**, the following sequence occurs:

```
1. NSEvent.addGlobalMonitorForEvents(matching: .keyDown) intercepts keypress
   ↓ [System-wide keyboard monitor listening for all key events]
   
2. Identify key code:
   Key code = 22 (numeric "6" key, ANSI layout)
   ↓
   
3. Check modifier flags:
   - Left Control key held? ✓ YES
   - Left Command key held? ✓ YES
   ↓ [Both modifiers required]
   
4. Match against hotkeyBindings:
   hotkeyBindings = {
       available: 18    (Ctrl+Cmd+1)
       tentative: 19    (Ctrl+Cmd+2)
       busy: 20         (Ctrl+Cmd+3)
       away: 22         (Ctrl+Cmd+6)  ← MATCH!
   }
   ↓
   
5. Trigger callback:
   onHotkeyPressed?(PresenceState.away)
```

**Key Codes Used** (ANSI Keyboard Layout):
- Code 18 → "1" key
- Code 19 → "2" key
- Code 20 → "3" key
- Code 22 → "6" key
- Code 21 → "4" key (special: Resume Calendar)
- Code 23 → "5" key (special: Turn Off)

### Phase 2: State Machine Processing

Once the hotkey is detected, the state machine processes the request:

```
1. Receive hotkeyPressed(.away) event
   ↓
   
2. Delegate to handleHotkeyOverride(.away)
   ↓ [Hotkey press treated as manual override]
   
3. Call handleManualOverride(.away)
   ↓
   a) Cancel any pending stabilization tasks
   ↓
   b) Guard check: Is system already in away mode?
      → If YES, block the request (system away takes priority)
      → If NO, continue
   ↓
   c) Mode transition:
      If currentMode != .manual:
         setMode(.manual)
         → Triggers onModeChanged callback
         → Disables calendar synchronization
   ↓
   d) Set override expiration timer:
      manualOverrideExpiry = Date() + 30 minutes
      scheduleExpiryCheck(after: 30)
      → Timer scheduled to check at 30 minutes
   ↓
   e) Log event:
      "state.override.set [state: away, timeoutMinutes: 30]"
   ↓
   f) Apply state transition:
      applyStateTransition(to: .away, source: .manual)
      → Sets currentState = .away
      → Sets currentSource = .manual
      → Triggers onStateChanged callback
```

### Phase 3: UI Update

The menu bar and status display update to reflect Away status:

```
1. updatePresenceState(.away) called
   ↓
   - Update status text: "Status: Away"
   - Update icon: ⚪ (white circle)
   ↓

2. updateModeDisplay(.manual) called
   ↓
   - Calendar status: "Calendar: Overridden"
   - Show "Resume Calendar Control" menu item
   - Toggle button: "Manually Mark as Available"
   ↓

3. Logging:
   hotkey.pressed [keyCode=22 targetState=away]
   state.transition [from=available to=away source=manual]
```

## Behavior During 30-Minute Override

### What Happens
- ✓ Your status shows **Away** in the menu bar
- ✓ Calendar events are ignored (not scanned)
- ✓ Device light shows Away icon (⚪)
- ✗ Calendar sync paused
- ✗ New calendar events don't update your status

### Can Override be Extended?
**Yes** — Press **Ctrl+Cmd+6 again** during the 30-minute window:
```
Current state: Away (time elapsed: 15 minutes)
Press: Ctrl+Cmd+6 again
Result: New 30-minute timer starts from NOW
         Total away time can exceed 30 minutes by pressing repeatedly
```

### Can Override be Cancelled Early?
**Yes** — Press **Ctrl+Cmd+4** (Resume Calendar):
```
Current state: Away (time elapsed: 5 minutes)
Press: Ctrl+Cmd+4
Result: Override cancelled IMMEDIATELY
        Calendar resumes control
        Timer discarded (remaining 25 minutes ignored)
```

## Automatic Recovery After 30 Minutes

### Timeline
```
00:00 — Press Ctrl+Cmd+6
        State: Away
        Timer: Scheduled for 30 minutes

30:00 — Timer fires automatically
        ↓
        checkAndHandleExpiredOverride() executes
        ↓
        if (manualOverrideExpiry < now AND currentMode == .manual):
            handleResumeAuto()
            ↓
            - Cancel override
            - Reset source to .startup
            - Switch mode back to .auto
            - Trigger engine.scanNow()
        ↓
        Calendar rescan completes
        Status returns to calendar-driven value
```

### Automatic Recovery Process

```
1. 30-minute timer expires
   ↓

2. expiryCheckTask fires:
   checkAndHandleExpiredOverride() called
   ↓

3. State machine checks:
   if expirationTime < currentTime:
       ↓
       handleResumeAuto():
           - manualOverrideExpiry = nil
           - expiryCheckTask?.cancel()
           - currentSource = .startup
           - setMode(.auto)
           - applyStateTransition(to: .off, source: .startup, force: true)
           - onRequestCalendarSync?()
   ↓

4. Calendar engine responds:
   await engine.scanNow()
   ↓
   - Scan current calendar events
   - Determine current availability
   - Apply new state automatically
   ↓

5. UI updates:
   Status returns to calendar-driven value
   Example: Away → Available (if calendar is free)
   ↓
   Menu updates:
   - Calendar status: "Calendar: Resuming…"
   - "Resume Calendar Control" item hidden
```

## Code Implementation Details

### HotkeyManager.swift

**Detection Logic** (lines ~165-180):
```swift
// Check for Away status trigger
if keyCode == 22 {  // 6 key
    let hasControl = event.modifierFlags.contains(.control)
    let hasCmd = event.modifierFlags.contains(.command)
    if hasControl && hasCmd {
        // Away hotkey matched!
        onHotkeyPressed?(PresenceState.away)
        return
    }
}
```

**Key to Name Mapping** (lines ~215-225):
```swift
case 22: return "Ctrl+Cmd+6"  // Away status
```

### ConfigurationManager.swift

**Migration Logic** (lines 54-67):
```swift
// Load hotkey bindings with automatic migration
if let savedBindings = userDefaults.dictionary(...) {
    let oldFunctionKeyCodes: Set<UInt16> = [105, 107, 113, 106, 64]
    let hasOldBindings = bindings.values.contains { oldFunctionKeyCodes.contains($0) }
    
    if hasOldBindings {
        resetHotkeysToDefaults()  // Migrate F13-F17 → Ctrl+Cmd+1/2/3/6
    }
}
```

### PresenceStateMachine.swift

**Override Handling** (lines ~220-250):
```swift
private func handleManualOverride(_ newState: PresenceState) {
    // Set manual override expiration
    if let timeoutMinutes = manualOverrideTimeoutMinutes {
        manualOverrideExpiry = Date().addingTimeInterval(
            TimeInterval(timeoutMinutes * 60)
        )
        scheduleExpiryCheck(after: timeoutMinutes)
    }
    
    // Apply state change
    applyStateTransition(to: newState, source: .manual)
}
```

**Expiration Check** (lines ~400+):
```swift
private func checkAndHandleExpiredOverride() {
    guard let expiryTime = manualOverrideExpiry,
          expiryTime < Date() else { return }
    
    handleResumeAuto()  // Automatic recovery
}
```

### AppConfiguration.swift

**Default Bindings** (lines ~15-24):
```swift
/// Manual override timeout in minutes (default 30 minutes)
public var manualOverrideTimeoutMinutes: Int? = 30

/// Hotkey bindings: maps presence states to Carbon virtual key codes
/// Control+Cmd combinations: 1=available, 2=tentative, 3=busy, 6=away
public var hotkeyBindings: [String: UInt16] = [
    PresenceState.available.rawValue: 18,    // 1 key (Ctrl+Cmd+1)
    PresenceState.tentative.rawValue: 19,    // 2 key (Ctrl+Cmd+2)
    PresenceState.busy.rawValue: 20,         // 3 key (Ctrl+Cmd+3)
    PresenceState.away.rawValue: 22,         // 6 key (Ctrl+Cmd+6)
]
```

## Comparison with Other Hotkeys

| Hotkey | State | Timeout | Recovery |
|--------|-------|---------|----------|
| **Ctrl+Cmd+1** | Available | 30 min | Auto or Ctrl+Cmd+4 |
| **Ctrl+Cmd+2** | Tentative | 30 min | Auto or Ctrl+Cmd+4 |
| **Ctrl+Cmd+3** | Busy | 30 min | Auto or Ctrl+Cmd+4 |
| **Ctrl+Cmd+6** | Away | 30 min | Auto or Ctrl+Cmd+4 |
| **Ctrl+Cmd+4** | Resume Calendar | Immediate | N/A (cancels override) |
| **Ctrl+Cmd+5** | Turn Off | Indefinite | Ctrl+Cmd+1/2/3/6 or app restart |

## Use Cases

### Scenario 1: Quick Away
```
Time: 2:00 PM
Event: Running to a meeting, will be back soon
Action: Press Ctrl+Cmd+6
Result: Away status stays for 30 minutes
Recovery: Automatic at 2:30 PM (or manual Ctrl+Cmd+4 if back sooner)
```

### Scenario 2: Extended Away
```
Time: 3:00 PM  
Event: In back-to-back meetings for the next hour
Action: Press Ctrl+Cmd+6 at 3:00, then again at 3:30
Result: Away status extended to 4:00 PM
Recovery: Automatic at 4:00 PM
```

### Scenario 3: Early Return
```
Time: 3:15 PM
Event: Return from meeting early, need to resume calendar control
Action: Press Ctrl+Cmd+4 (Resume Calendar)
Result: Away override cancelled immediately
Recovery: Calendar rescans and returns to actual availability
         (e.g., back to Available if calendar shows free time)
```

## Troubleshooting

### Away hotkey not working

**Check 1: Old function key bindings**
- If upgrading from older version with F13-F17 function keys
- Check Console for: `"Detected old function key bindings, resetting to new Ctrl+Cmd defaults"`
- If migration message appears, restart app to apply new bindings
- UserDefaults will be updated automatically

**Check 2: Accessibility permission**
- System Settings → Privacy & Security → Accessibility
- Ensure BusyLight has toggle enabled
- If not, grant permission and rebuild app

**Check 3: Correct key combination**
- Must press: **Left Control** + **Left Command** + **6** (numeric row)
- Not right Control or Command keys
- Verify in menu: Debug → Hotkey Debug Info

**Check 4: Console logging**
```bash
# Check for hotkey detection logs
log stream --predicate 'process == "BusyLight"' | grep -i hotkey

# Should show:
# hotkey.pressed [keyCode=22 targetState=away ...]
```

### Timer not expiring

**Cause**: State machine timer not running  
**Solution**: 
1. Check if app in background longer than 30 minutes
2. Log shows: `state.override.set [state: away, timeoutMinutes: 30]`
3. At 30 minutes, should show: `state.override.expired [state: away]`

### Can't get back to calendar

**Cause**: Manual override still active  
**Solution**: Press **Ctrl+Cmd+4** to immediately resume calendar control

## Performance Notes

- **Hotkey detection**: < 1ms (global event monitor)
- **State transition**: < 5ms (state machine update)
- **UI update**: < 50ms (menu bar icon change)
- **Calendar rescan**: 1-10s (depends on calendar size)

## Related Documentation

- [Global Hotkey Integration Guide](hotkey.md) — Complete hotkey documentation
- [State Machine Architecture](state-machine.md) — State machine design and transitions
- [Main README](../README.md) — Quick start and overview
