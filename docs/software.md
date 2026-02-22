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

The agent communicates with the WLED device using WLED's standard HTTP JSON API.

**Activate a preset:**
```
POST http://<device-ip>/json/state
{"ps": <preset_id>, "v": true}
```

**Health check / device info:**
```
GET http://<device-ip>/json/info
```

Each presence state maps to a WLED preset ID (defaults, configurable):

| Presence State | Default Preset |
|----------------|----------------|
| Available | 1 — Green solid |
| Tentative | 2 — Yellow/Amber breathe |
| Busy | 3 — Red solid |
| Away | 4 — Blue fade |
| Unknown | 5 — White blink |
| Off | 6 — LEDs off |

The agent sends the preset ID to WLED and WLED handles all pixel rendering. The agent only decides *which* preset to activate.

### Multi-Device Broadcasting

The agent can control **multiple WLED devices simultaneously**. All devices receive the same state change in parallel using Swift's `TaskGroup`. If one device is offline, the others continue to function normally.

### Device Discovery

By default, the agent discovers WLED devices on your local network automatically via **Bonjour/mDNS** (`_http._tcp`). Discovery runs at startup and takes approximately 5 seconds. Discovered devices are verified by fetching `/json/info` and checking for a WLED version string.

Discovery can be disabled and devices configured manually if needed.

### Network Layer Components

The WLED communication layer is implemented across four files:

| File | Role |
|------|------|
| `WLEDTypes.swift` | API models (`WLEDStateRequest`, `WLEDStateResponse`, `WLEDInfoResponse`, `WLEDDevice`), `NetworkError` enum |
| `HTTPAdapter.swift` | Actor-isolated HTTP client with 3-retry exponential backoff (100 ms → 200 ms → 400 ms) |
| `DeviceDiscovery.swift` | Bonjour/mDNS `_http._tcp` browser; verifies candidates via `/json/info` |
| `NetworkClient.swift` | Coordinator: parallel `TaskGroup` broadcast, health polling, deduplication |

Full implementation detail: [WLED WLAN Support](wled-wlan-support.md)

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

- macOS 14.0 (Sonoma) or later
- Xcode 15+ or Swift 6+

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

**Core settings:**

| Key | Default | Description |
|-----|---------|-------------|
| `app.presence_state` | `unknown` | Current presence mode |
| `app.manual_override_timeout` | `30` | Manual override expiry in minutes (-1 = no timeout) |
| `app.state_stabilization` | `0` | State change debounce delay in seconds |
| `app.show_menu_bar_text` | `true` | Show presence text in menu bar |

**Network / WLED settings:**

| Key | Default | Description |
|-----|---------|-------------|
| `app.device_network_addresses` | `[]` | Array of WLED device IP addresses (merged with discovered devices) |
| `app.device_network_port` | `80` | WLED HTTP port (standard HTTP) |
| `app.wled_enable_discovery` | `true` | Enable Bonjour/mDNS auto-discovery |
| `app.wled_http_timeout` | `500` | HTTP request timeout in milliseconds |
| `app.wled_health_check_interval` | `10` | Health check polling interval in seconds |

**Preset ID mappings:**

| Key | Default | Presence State |
|-----|---------|----------------|
| `app.wled_preset_available` | `1` | Available |
| `app.wled_preset_tentative` | `2` | Tentative |
| `app.wled_preset_busy` | `3` | Busy |
| `app.wled_preset_away` | `4` | Away |
| `app.wled_preset_unknown` | `5` | Unknown |
| `app.wled_preset_off` | `6` | Off |

**Example: configure multiple devices manually:**
```bash
defaults write com.busylight.agent app.device_network_addresses \
  -array "192.168.1.100" "192.168.1.101"
defaults write com.busylight.agent app.wled_enable_discovery -bool false
```

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

For full WLED network integration testing procedures, see [WLED Network Module Testing Guide](../docs/module-testing.md).

---

[← Back to Docs Home](index.md) · [Hardware Setup →](hardware.md) · [Architecture →](architecture.md)
