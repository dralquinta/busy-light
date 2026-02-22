---
layout: default
title: Software Documentation — BusyLight macOS Agent
description: How the BusyLight macOS agent works — calendar integration, state management, hotkeys, and WLED communication.
---

# Software Documentation (macOS Agent)

The BusyLight macOS agent is a native Swift application that runs in your menu bar. It reads your calendar, resolves your presence state, and communicates that state to the WLED device.

---

## Overview

The agent is intentionally minimal:

- Runs in the menu bar only — no Dock icon, no foreground window.
- Reads your macOS calendar using EventKit.
- Uses a priority-based state machine to resolve presence.
- Sends HTTP JSON commands to your WLED device.
- Responds to global keyboard shortcuts for manual override.
- Persists configuration across restarts.

---

## Calendar Integration

The agent uses **EventKit** to read events from your macOS Calendar. It polls your calendars on a regular interval and resolves your current availability based on:

- Whether an event is currently in progress.
- The event's availability status (Busy, Free, Tentative).
- Overlapping events and their combined availability.

The calendar data never leaves your machine. EventKit reads local calendar data (including synchronized Exchange/Google calendars cached on-device).

Full details: [EventKit Calendar Integration](eventkit-calendar-integration.md)

---

## State Machine

Presence state is managed by a centralized state machine with three priority levels:

```
System (Highest)   ─►  Screen lock / sleep always overrides everything
        │
        ▼
Manual Override    ─►  Hotkeys or Stream Deck block calendar updates
        │
        ▼
Calendar (Lowest)  ─►  Automatic resolution from EventKit in auto mode
```

### Operating Modes

- **Auto Mode** (default): Presence state is resolved automatically from calendar events.
- **Manual Mode**: A user-triggered override is active. Calendar updates are ignored until the override expires or is cancelled.

### Manual Override Timeout

Manual overrides automatically expire after a configurable timeout (default: 30 minutes). After expiry, the agent returns to calendar-driven auto mode. You can cancel an override immediately using **Ctrl+Cmd+4**.

Full details: [State Machine Architecture](state-machine.md)

---

## Hotkeys

BusyLight registers global keyboard shortcuts that work system-wide:

| Hotkey | Action |
|--------|--------|
| **Ctrl+Cmd+1** | Mark as Available |
| **Ctrl+Cmd+2** | Mark as Tentative |
| **Ctrl+Cmd+3** | Mark as Busy |
| **Ctrl+Cmd+4** | Resume Calendar Control (cancel override) |
| **Ctrl+Cmd+5** | Turn Off |
| **Ctrl+Cmd+6** | Mark as Away |

Hotkeys require Accessibility permission. See [Hotkey Documentation](hotkey.md) for permission setup and troubleshooting.

---

## WLED Communication

The agent communicates with the WLED device using WLED's standard HTTP JSON API:

```
POST http://<device-ip>/json/state
```

Each presence state maps to a WLED preset ID:

| Presence State | WLED Preset |
|----------------|-------------|
| Available | 1 |
| Tentative | 2 |
| Busy | 3 |
| Away | 4 |
| Off | 5 |
| Unknown | 6 |

The agent sends a `ps` (preset) command to activate the corresponding preset on the device. All color, animation, and brightness decisions are handled by WLED — the agent only sends the preset ID.

See the [Hardware Documentation](hardware.md) for WLED preset configuration.

---

## Required Permissions

### Accessibility (for Global Hotkeys)

Required for global keyboard shortcut detection.

**To grant:**
1. Open **System Settings → Privacy & Security → Accessibility**
2. Add `BusyLight.app` and toggle ON
3. Restart the app

### Calendar (for Status Sync)

Required for reading calendar events via EventKit.

**To grant:**
1. Open **System Settings → Privacy & Security → Calendars**
2. Find "BusyLight" and toggle ON

---

## Building and Running

### Prerequisites

- macOS Monterey (12.0) or later
- Xcode 13+ or Swift 5.5+

### Build

```bash
./build.sh
```

Or manually:

```bash
cd macos-agent
xcodebuild -scheme BusyLight -configuration Release
```

### Run

```bash
open BusyLight.app
```

Or for debug mode with logs:

```bash
./debug.sh
```

### First-Launch Setup

After each new build:

1. Remove the old Accessibility registration (System Settings → Accessibility → remove BusyLight).
2. Run the new build.
3. Grant Accessibility permission when prompted.
4. Restart the app.

This is required because new builds have different code signatures.

---

## Configuration

Settings are persisted in `UserDefaults` under the suite `com.busylight.agent`:

| Key | Default | Description |
|-----|---------|-------------|
| `app.presence_state` | `unknown` | Current presence mode |
| `app.device_network_address` | — | WLED device IP address |
| `app.device_network_port` | `80` | WLED HTTP port |
| `app.manual_override_timeout` | `30` | Manual override expiry in minutes (-1 = no timeout) |
| `app.state_stabilization` | `0` | State change debounce delay in seconds |

---

## Logging

View structured logs:

```bash
log stream --predicate 'subsystem == "com.busylight.agent.*"' --level debug
```

Filter by subsystem:

```bash
log stream --predicate 'subsystem == "com.busylight.agent.lifecycle"'
log stream --predicate 'subsystem == "com.busylight.agent.calendar"'
log stream --predicate 'subsystem == "com.busylight.agent.ui"'
```

---

## Testing

```bash
xcodebuild test -scheme BusyLight
```

Or via Swift Package Manager:

```bash
swift test
```

---

[← Back to Docs Home](index.md) · [Hardware Setup →](hardware.md) · [Architecture →](architecture.md)
