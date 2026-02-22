# Hotkey Integration

Global keyboard hotkeys allow you to control BusyLight presence state without switching focus from your current application. Hotkeys work system-wide, whether BusyLight is in the foreground, background, or menu bar only.

---

## Default Hotkey Mappings

BusyLight uses **function keys F13–F17** by default, mapped as follows:

| Key    | Presence State | Effect |
|--------|---|---|
| **F13** | Available | Sets status to available, activates manual override mode |
| **F14** | Tentative | Sets status to tentative, activates manual override mode |
| **F15** | Busy | Sets status to busy, activates manual override mode |
| **F16** | Away | Sets status to away, activates manual override mode |
| **F17** | Off | Turns off BusyLight (suspends all syncing) |

### Why F13–F17?

- **Hardware keys**: Function keys F13–F20 exist on most modern Mac keyboards and are rarely used by other applications, reducing conflicts.
- **Stream Deck compatible**: Stream Deck buttons can emit F13–F17 key presses via configuration without additional drivers.
- **Low latency**: Direct hardware key events trigger presence state changes in <100 ms.

---

## Stream Deck Integration

Stream Deck buttons can emit hotkeys that BusyLight listens for. No special drivers or plugins required—just configure Stream Deck to emit the function key.

### How to configure Stream Deck
### How to configure Stream Deck

1. Open the Stream Deck application (version 3.10.198.0201+).  
2. Create a new button or edit an existing one.  
3. Set the button action:
       - choose the **Hotkey** action,
       - configure the hotkey to emit:

         | State     | Hotkey                        |
         |-----------|-------------------------------|
         | Available | Left Ctrl + Left Cmd + 1      |
         | Tentative | Left Ctrl + Left Cmd + 2      |
         | Busy      | Left Ctrl + Left Cmd + 3      |
         | Away      | Left Ctrl + Left Cmd + 4      |
         | Off       | Left Ctrl + Left Cmd + 5      |
         | Toggle    | Left Ctrl + Left Cmd + 6      |

4. Assign the action to a physical button on your Stream Deck or dock.  
5. Test: press the button; BusyLight presence should update within 100 ms.

**Example Stream Deck profile layout:**

```
┌──────────────────┬──────────────────┬──────────────────┐
│ Ctrl+Cmd+1       │ Ctrl+Cmd+2       │ Ctrl+Cmd+3       │
│   Available      │   Tentative      │      Busy        │
├──────────────────┼──────────────────┼──────────────────┤
│ Ctrl+Cmd+4       │ Ctrl+Cmd+5       │ Ctrl+Cmd+6       │
│      Away        │       Off        │      Toggle      │
└──────────────────┴──────────────────┴──────────────────┘
```

---

## Reconfiguring Hotkey Bindings

### Via Menu (Recommended)

1. Click the BusyLight menu bar icon 
2. Select **"Configure Hotkeys"** → submenu showing current bindings (e.g., "Available: F13")
3. Click **"Edit preferences for custom bindings"** *(feature in development)*

### Via Configuration File

Hotkey bindings are persisted in macOS `UserDefaults` under the suite `com.busylight.agent`. For advanced users, you can edit bindings directly:

```bash
# View current hotkey bindings
defaults read com.busylight.agent 'app.hotkey_bindings'

# Set custom binding (example: Available -> F18, code 79)
defaults write com.busylight.agent 'app.hotkey_bindings' -dict \
  'available' 79 \
  'tentative' 107 \
  'busy' 113 \
  'away' 106 \
  'off' 64

# Reset to defaults
defaults delete com.busylight.agent 'app.hotkey_bindings'
```


The content is useful for the "Advanced: Custom Hotkey Bindings" section. Here's an updated version with current Carbon virtual key codes:

---

## macOS Permissions

BusyLight uses the **Accessibility API** to monitor global keyboard events system-wide. This requires a one-time permission grant.

### Granting Accessibility Permission

1. **First time you press a hotkey**:
   - macOS will display a permission dialog: *"BusyLight would like to monitor your keyboard."*
   - Click **"Open System Preferences"** or manually navigate to:

2. **System Settings → Privacy & Security → Accessibility**:
   - Look for **"BusyLight"** in the list
   - If not present, click the **"+"** button and navigate to:
     ```
     /Applications/BusyLight.app
     ```
   - Toggle the switch to **enable** Accessibility for BusyLight

3. **Restart BusyLight** for changes to take effect

### Why Accessibility Permission?

Global keyboard monitoring (monitoring keys regardless of which app is focused) requires macOS Accessibility API. This is the modern, sandbox-safe approach used by macOS 13+.

**You will see this permission dialog once.** It is not stored or transmitted; macOS manages it locally.

---

## Behavior: Manual Override Mode

When you press a hotkey:

1. **BusyLight switches to manual override mode** — calendar sync is paused
2. **Presence state changes immediately** (within <100 ms)
3. **Auto-resume on timeout** — manual override expires after 120 minutes (configurable), then calendar sync resumes
4. **System away overrides hotkeys** — if your screen locks while in manual mode, BusyLight automatically switches to `.away` until you unlock

### Example Flow

```
Auto mode, calendar shows "Available"
       ↓
You press F15 (Busy hotkey)
       ↓
Manual mode activated, status → "Busy" 
       ↓
Calendar still shows "Available" but manual override blocks it (120 min timeout)
       ↓
After 120 minutes OR you click "Resume Calendar Control" 
       ↓
Auto mode resumes, calendar sync active again
```

---

## No-Op Behavior

Pressing the same hotkey twice in a row does **not** send redundant state change events:

```
Press F15 (Busy) → status: busy, manual mode active
Press F15 (Busy) → no-op, debounced
Press F16 (Away) → status: away (state changed)
```

Duplicate presses are logged to help with debugging.

---

## Known Limitations

### Function Key Availability

- **Macbook with Touch Bar**: F13–F20 are hardware keys accessible via the **Fn + row of keys** mapping. Verify your Stream Deck is configured to emit the correct key codes.
- **Third-party keyboards**: Some mechanical keyboards may not have F13–F20. You can reconfigure BusyLight to use different keys (e.g., F1–F12, or Ctrl+Shift+A shortcuts) if needed.
- **System-reserved keys**: Some macOS versions or external keyboards may reserve certain function keys (e.g., F3 for Mission Control). If a hotkey doesn't work, check **System Settings → Keyboard → Keyboard Shortcuts** for conflicts.

### Sandbox Restrictions (Development Builds)

When running BusyLight as an SPM binary (not a .app bundle), some sandbox restrictions may apply:

- Global hotkey monitoring may fail or prompt for additional permissions
- Distribution as a signed .app bundle resolves these issues

---

## Logging & Debugging

BusyLight logs all hotkey events using structured logging. To view hotkey logs:

### View logs in Console.app

1. **Open Console.app** (Applications → Utilities → Console)
2. **Search for**: `hotkey` or `hotkey.manager.started`
3. **Detailed events include**:
   - Hotkey listener registered/deregistered
   - Hotkey press with key code and target state
   - State transition rejection (e.g., if system is away)
   - Binding updates

### Example log entries

```
hotkey.manager.initialized[0x00000001] bindingsCount = 5
hotkey.monitor.started[0x00000002] bindingsCount = 5
hotkey.pressed[0x00000003] keyCode = 113, targetState = busy, timestamp = 2026-02-22T10:30:45Z
state.transition.success[0x00000004] from = available, to = busy, source = manual
hotkey.bindings.updated[0x00000005] bindingsCount = 5
```

### Simulating hotkey presses for testing

In the menu: **Debug → Simulate Manual Override** allows you to test state transitions without pressing physical keys.

---

## Troubleshooting

### "Hotkeys don't work after app restart"

- [ ] **Accessibility permission not granted**: Check System Settings → Privacy & Security → Accessibility
- [ ] **App not running**: BusyLight must be running (menu bar icon visible) for hotkeys to work
- [ ] **Stream Deck not configured**: Verify the Stream Deck button emits F13–F17, not a different key

### "One hotkey works, others don't"

- [ ] **Key code conflicts**: Another app may be listening for the same key. Check System Settings → Keyboard → Keyboard Shortcuts for global shortcuts
- [ ] **Stream Deck partial configuration**: Ensure all buttons are configured to emit the correct function key
- [ ] **Keyboard layout**: Some non-US keyboard layouts may have different key codes. Use the Debug menu to verify which key codes are being received

### "Hotkey presses are slow (>100 ms)"

- [ ] **Accessibility API overhead**: On some systems, the first hotkey press may take up to 500 ms as the Accessibility API initializes. Subsequent presses are <100 ms
- [ ] **System under load**: If macOS is under high CPU load, keyboard event processing may be delayed
- [ ] **Menu bar icon frozen**: If the menu bar icon is not responding, restart BusyLight

### "Accessibility permission prompt won't go away"

- [ ] **Close BusyLight completely**: Use Quit from the menu or `killall BusyLight`
- [ ] **Remove from Accessibility list**: System Settings → Privacy & Security → Accessibility → Remove BusyLight
- [ ] **Relaunch BusyLight**: The permission dialog should appear once
- [ ] **Grant permission**: Click "Open System Preferences" and toggle the switch

---

## Privacy & Security

- **Hotkey monitoring is local only**: BusyLight does not transmit keyboard events anywhere
- **No logging of key content**: Only function key codes (F13–F17) are logged, not arbitrary keypresses
- **Accessibility API is sandboxed**: Permissions are managed by macOS and visible in System Settings
- **User consent required**: A one-time dialog asks permission before monitoring begins

---

## Advanced: Custom Hotkey Bindings

To use non-function keys, you must:

1. Identify the key's **Carbon virtual key code** (see [Apple documentation](https://developer.apple.com/library/archive/documentation/mac/pdf/MacintoshToolboxEssentials.pdf) or test with a key logger)
2. Update the binding via `defaults` command above
3. **Note**: Non-standard keys may not be supported by Stream Deck and require keyboard hardware changes

---

## Contact & Support

If hotkeys are not working:

1. Check logs via **Debug menu → Simulate Manual Override** to verify state machine is responding
2. Look up your issue in **Troubleshooting** section above
3. Verify Accessibility permission is granted
4. Restart BusyLight and try again

For bugs or feature requests, refer to the main [BusyLight README](../../README.md).
