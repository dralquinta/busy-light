---
layout: default
title: Architecture Overview — BusyLight
description: System architecture, component breakdown, and communication protocols for BusyLight.
---

# Architecture Overview

BusyLight is composed of two main components: a macOS menu bar agent and an ESP32-based LED device running WLED firmware. This document describes how these components interact and the design decisions behind the system.

---

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        macOS Agent                               │
│                                                                  │
│  ┌──────────────┐   ┌────────────────────┐   ┌──────────────┐  │
│  │  EventKit    │   │   State Machine     │   │ WLED Client  │  │
│  │  Calendar    │──►│  (Priority-based)   │──►│ (HTTP JSON)  │  │
│  │  Scanner     │   │                     │   └──────┬───────┘  │
│  └──────────────┘   │  System  (highest)  │          │          │
│                     │  Manual             │          │          │
│  ┌──────────────┐   │  Calendar (lowest)  │          │          │
│  │  Hotkeys     │──►│                     │          │          │
│  │  (Global)    │   └────────────────────┘          │          │
│  └──────────────┘                                    │          │
│                                                      │          │
│  ┌──────────────┐                                    │          │
│  │  Menu Bar UI │                                    │          │
│  │  (AppKit)    │                                    │          │
│  └──────────────┘                                    │          │
└──────────────────────────────────────────────────────┼──────────┘
                                                        │
                                               HTTP JSON (local Wi-Fi)
                                                        │
                                                        ▼
                                       ┌────────────────────────────┐
                                       │       ESP32 + WLED          │
                                       │                              │
                                       │  ┌────────────────────┐    │
                                       │  │  WLED Firmware     │    │
                                       │  │  (REST API server) │    │
                                       │  └────────┬───────────┘    │
                                       │           │                  │
                                       │           ▼                  │
                                       │  ┌────────────────────┐    │
                                       │  │  LED Matrix/Strip  │    │
                                       │  │  (WS2812B, etc.)   │    │
                                       │  └────────────────────┘    │
                                       └────────────────────────────┘
```

---

## Component Breakdown

### macOS Agent

The macOS agent is a native Swift application using AppKit.

| Component | Responsibility |
|-----------|----------------|
| `CalendarScanner` | Polls EventKit for current calendar events |
| `CalendarAvailabilityResolver` | Resolves presence state from overlapping events |
| `PresenceStateMachine` | Coordinates state from all input sources with priority rules |
| `HotkeyManager` | Registers and handles global keyboard shortcuts |
| `StatusMenuController` | Renders menu bar icon and dropdown menu |
| `WLEDClient` *(planned)* | Sends HTTP JSON commands to WLED device |
| `ConfigurationManager` | Persists settings in UserDefaults |

### ESP32 + WLED Device

The hardware device runs WLED firmware on an ESP32 microcontroller.

| Component | Responsibility |
|-----------|----------------|
| ESP32 MCU | Wi-Fi connectivity, running WLED firmware |
| WLED firmware | REST API server, LED rendering, preset management |
| LED strip/matrix | Physical visual output |

---

## Communication Protocol

### macOS → WLED

The macOS agent communicates with the WLED device using WLED's standard HTTP JSON API over your local Wi-Fi network.

**Endpoint**: `POST http://<device-ip>/json/state`

**Payload** (activate a preset):
```json
{
  "ps": <preset_id>
}
```

**Presence State → Preset Mapping**:

| Presence State | Preset ID |
|----------------|-----------|
| Available | 1 |
| Tentative | 2 |
| Busy | 3 |
| Away | 4 |
| Off | 5 |
| Unknown / Disconnected | 6 |

All communication is local. No internet connection is required after initial WLED setup.

---

## State Machine Design

The presence state machine uses a priority-based model with three levels:

```
Priority Level    Source                Trigger
─────────────     ──────────────────    ──────────────────────────────
HIGH (3)          System Events         Screen lock, sleep/wake
MEDIUM (2)        Manual Override       Hotkeys, menu selection
LOW (1)           Calendar              EventKit polling
```

Higher-priority states always override lower-priority states. When a higher-priority state is removed (e.g., screen unlocks), the state machine falls back to the next active lower-priority state.

### Key Design Decisions

**Calendar as the baseline**: Calendar events drive the default state. The agent polls for events at a regular interval and resolves availability based on event overlaps and their availability flags.

**Manual overrides are temporary**: Hotkey-triggered overrides automatically expire after a configurable timeout (default: 30 minutes). This prevents the light from being stuck in a manual state indefinitely.

**System events always win**: Screen lock and sleep are detected by the system monitor and always produce the Away state, regardless of calendar or manual state.

---

## Data Flow

```
1. CalendarScanner polls EventKit every 60s
        │
        ▼
2. CalendarAvailabilityResolver maps events → PresenceState
        │
        ▼
3. PresenceStateMachine receives state update (source: calendar)
        │
        ├── If manual override active → calendar update ignored
        ├── If system event active → calendar update ignored
        └── Otherwise → state updates
        │
        ▼
4. WLEDClient sends HTTP POST to /json/state with preset ID
        │
        ▼
5. WLED renders preset on LED hardware
```

---

## Security Considerations

- All communication is local (LAN only). No data is transmitted externally.
- Calendar data is read via EventKit — no calendar data is stored outside of macOS's native calendar system.
- WLED API has no authentication by default. Ensure your home Wi-Fi network is secure.
- The macOS agent requests only the minimum permissions required: Accessibility (hotkeys) and Calendars (EventKit).

---

## Future Architecture (Planned)

| Feature | Architecture Impact |
|---------|---------------------|
| Device discovery | mDNS/Bonjour scan for WLED devices on LAN |
| Multi-device support | Fan-out from state machine to multiple WLED clients |
| Stream Deck integration | Additional input source feeding into state machine |
| Preferences window | SwiftUI settings panel for device configuration |

---

[← Back to Docs Home](index.md) · [Hardware Setup →](hardware.md) · [Software Documentation →](software.md)
