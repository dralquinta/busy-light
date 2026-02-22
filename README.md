# busy-light

A native macOS presence agent for the busy-light device. This repository contains the hardware specifications and the native macOS application for visual availability signaling.

## Project Structure

- **`specs/`** — Hardware specifications and requirements
- **`macos-agent/`** — macOS menu bar application (Swift + AppKit)
  - See [macos-agent/README.md](macos-agent/README.md) for build, run, and architecture details

## Quick Start (macOS Agent)

```bash
cd macos-agent
xcodebuild -scheme BusyLight
```

The application will launch and display an icon in your menu bar. See [macos-agent/README.md](macos-agent/README.md) for full instructions.

## Required Permissions

BusyLight requires two permissions to function:

### 1. Accessibility Permission (for Global Hotkeys)

Required for detecting keyboard shortcuts (Ctrl+Cmd+1/2/3, F16/F17) system-wide.

**To grant:**
1. Open **System Settings → Privacy & Security → Accessibility**
2. Click the **+** button
3. Navigate to and select `BusyLight.app` (in `/Applications` or build output)
4. Toggle **ON** (ensure checkmark is visible)
5. Restart the App

### 2. Calendar Permission (for Status Sync)

Required for reading your calendar events to determine availability.

**To grant:**
1. Open **System Settings → Privacy & Security → Calendars**
2. Find "BusyLight" in the list
3. Toggle **ON**

## First-Launch Setup

After building or updating the code:

1. **Remove old Accessibility registration** (System Settings → Privacy & Security → Accessibility):
   - Find "BusyLight" in the list
   - Click it, then click the **minus (−)** button
2. **Build the app**: `./build.sh`
3. **Open the app**: `open BusyLight.app` or `./debug.sh`
4. **Grant Accessibility permission** when prompted
5. **Grant Calendar permission** if prompted
6. **Close the app** completely (`Cmd+Q`)
7. **Reopen the app**: `open BusyLight.app`
8. **Status should sync** to your current calendar availability

The permission reset is required because new app builds have different code signatures, and macOS's accessibility database needs to re-validate the app. This is a one-time setup per build.

## Documentation

### Architecture & Design
- **[macOS Presence Agent — Menu Bar Skeleton](docs/macOS-presence-agent-menuskeleton.md)** — Complete implementation guide, architecture, build workflow, concurrency design, and testing strategy (February 2026)
- **[State Machine Architecture](docs/state-machine.md)** — Hierarchical state machine coordinating presence across calendar, manual overrides, and system events. Modes, transitions, priority rules, and configuration options.

### Integration Guides
- **[EventKit Calendar Integration](docs/eventkit-calendar-integration.md)** — Calendar event scanning, permission handling, and availability resolution logic
- **[Global Hotkey Integration](docs/hotkey.md)** — Keyboard shortcuts for quick status changes (Ctrl+Cmd+1/2/3 for states plus Ctrl+Cmd+4 to resume calendar), F16/F17, override behavior, permission setup, and troubleshooting

## Design Philosophy

- **Minimal & Focused**: Single-purpose presence agent, no extraneous UI
- **Low-Overhead**: Runs in menu bar only; minimal CPU/memory footprint
- **Persistent**: Settings and state survive application restarts and system sleep
- **Observable**: Structured logging for debugging and monitoring
- **Ready for Scale**: Architecture prepared for future features (device integration, multi-device, etc.)

## Development Status

- ✅ Menu bar application skeleton
- ✅ Persistent settings storage
- ✅ Presence state management
- ✅ Structured logging
- ✅ Base test suite
- 🔄 Hardware communication adapter (REST/WebSocket) — coming next

## Requirements

- macOS Tahoe (12.0) or later
- Xcode 13+ or Swift 5.5+

## Contributing

See individual module READMEs for contribution guidelines.

---

**Version**: 0.1.0 | **Status**: Active Development 
