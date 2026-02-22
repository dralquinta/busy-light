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

## Documentation

### Architecture & Design
- **[macOS Presence Agent — Menu Bar Skeleton](docs/macOS-presence-agent-menuskeleton.md)** — Complete implementation guide, architecture, build workflow, concurrency design, and testing strategy (February 2026)
- **[State Machine Architecture](docs/state-machine.md)** — Hierarchical state machine coordinating presence across calendar, manual overrides, and system events. Modes, transitions, priority rules, and configuration options.

### Integration Guides
- **[EventKit Calendar Integration](docs/eventkit-calendar-integration.md)** — Calendar event scanning, permission handling, and availability resolution logic

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
