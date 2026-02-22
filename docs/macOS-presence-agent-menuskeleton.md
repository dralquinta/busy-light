# macOS Presence Agent — Menu Bar Skeleton

**Date:** February 22, 2026  
**Status:** ✅ Complete  
**Target:** macOS Tahoe (12.0+)  
**Language:** Swift 6.2.3  

---

## Overview

Built a native macOS menu bar application skeleton for the [busy-light](../) device. The agent runs entirely in the menu bar without a Dock icon, enabling low-overhead presence signaling. The project includes:

- ✅ Menu bar UI (`NSStatusBar`) with presence state display
- ✅ Persistent settings storage (UserDefaults)
- ✅ Structured logging (`os_log`)
- ✅ Configuration management layer
- ✅ Test suite (Swift Testing; runs in Xcode, skipped in Command Line Tools)
- ✅ Swift 6 strict concurrency compliance
- ✅ Build wrapper script (`build.sh`) for consistent builds from project root

---

## Architecture

### Directory Structure

```
busy-light/
├── build.sh                    # Build wrapper (debug | release | test | clean)
├── macos-agent/
│   ├── Package.swift           # Swift Package manifest
│   ├── Sources/
│   │   ├── BusyLight/          # Executable target
│   │   │   ├── main.swift      # Entry point (imperative, not @main)
│   │   │   ├── BusyLightApp.swift  # NSApplicationDelegate
│   │   │   └── AppDelegate.swift   # (empty; kept for reference)
│   │   └── BusyLightCore/      # Library target (public API for tests)
│   │       ├── Models/
│   │       │   ├── PresenceState.swift      # Available, Busy, Away
│   │       │   ├── DeviceStatus.swift       # Device connection state
│   │       │   └── AppConfiguration.swift   # Persistent settings
│   │       ├── Core/
│   │       │   ├── Logger.swift             # Structured logging wrapper
│   │       │   └── ConfigurationManager.swift # UserDefaults layer
│   │       └── UI/
│   │           └── StatusMenuController.swift # Menu bar UI
│   ├── Tests/
│   │   └── BusyLightTests/
│   │       ├── LaunchPersistenceTests.swift # Configuration restart tests
│   │       └── SettingsTests.swift          # Settings model tests
│   ├── README.md                # Build, run, and architecture guide
│   └── .gitignore              # Xcode and SPM artifacts
└── README.md                    # Project overview
```

### Core Components

#### 1. **Models** (`BusyLightCore/Models/`)

**`PresenceState.swift`**
- Enum: `available`, `busy`, `away`
- Implements `Codable` + `Sendable` for UserDefaults persistence and concurrency
- Computed property: `displayName` (human-readable)

**`DeviceStatus.swift`**
- Tracks device connection state (connected, disconnected, error)
- Stores `lastUpdate` timestamp and optional `errorMessage`
- `displayText` property for UI display

**`AppConfiguration.swift`**
- Struct holding all persistent settings
- Fields:
  - `presenceState` (default: `.available`)
  - `deviceNetworkAddress` (for REST/WebSocket communication)
  - `deviceNetworkPort` (default: 8080)
  - `launchOnStartup` (future: login item registration)
  - `showMenuBarText` (show/hide presence text in menu bar)
- Conforms to `Codable` + `Sendable`

#### 2. **Core Services** (`BusyLightCore/Core/`)

**`Logger.swift`**
- Wrapper around `os_log` for structured logging
- Convenience global instances: `lifecycleLogger`, `uiLogger`, `configLogger`, `deviceLogger`, `errorLogger`
- Categories map to subsystems for easy filtering:
  ```swift
  log stream --predicate 'subsystem == "com.busylight.agent.lifecycle"'
  ```
- Class is `@unchecked Sendable` (os_log is thread-safe)

**`ConfigurationManager.swift`**
- Singleton (`@MainActor`) managing UserDefaults persistence
- Methods:
  - `loadConfiguration()` — Load from UserDefaults on startup
  - `saveConfiguration()` — Persist to UserDefaults on change
  - Accessors: `getPresenceState()`, `setPresenceState()`, etc.
- Stores all settings under `com.busylight.agent.*` keys

#### 3. **UI** (`BusyLightCore/UI/`)

**`StatusMenuController.swift`**
- Manages `NSStatusBar` icon and dropdown menu
- Main interface:
  - `updatePresenceState(_ state: PresenceState)` — Updates menu text
  - `updateDeviceStatus(_ status: DeviceStatus)` — Shows device connection
- Menu items:
  - Status display (read-only)
  - Toggle button (Available ↔ Busy)
  - Device status indicator
  - Preferences (placeholder)
  - Quit option
- Class is `@MainActor` (all AppKit calls must be on main thread)

#### 4. **Application Delegate** (`BusyLightApp.swift`)

- Implements `NSApplicationDelegate` lifecycle
- Key hooks:
  - `applicationDidFinishLaunching(_:)` — Initialize menu, load config, set activation policy to `.prohibited` (no Dock icon)
  - `applicationWillTerminate(_:)` — Save config on shutdown
  - `applicationShouldTerminateAfterLastWindowClosed(_:)` — Always return `false` (no windows to close)

#### 5. **Entry Point** (`main.swift`)

- Imperative entry point (not `@main`)
- Creates `NSApplication` singleton and wires delegate directly
- Calls `app.run()` to start event loop

---

## Build & Run

### From Project Root

```bash
# Debug build (default)
./build.sh

# Release build
./build.sh release

# Tests (Xcode only; skipped on Command Line Tools)
./build.sh test

# Clean
./build.sh clean
```

### From `macos-agent/` Directory

```bash
# Swift Package Manager
swift build                  # Debug
swift build -c release      # Release

# Or using Xcode (if available)
xcodebuild -scheme BusyLight
xcodebuild test -scheme BusyLight  # Run test suite
```

### Run Application

```bash
# From build output
./.build/debug/BusyLight

# From project root via wrapper
./build.sh && ./.build/debug/BusyLight
```

Application launches with no window; icon appears in menu bar (top-right corner).

---

## Configuration & Persistence

Settings stored in `UserDefaults` under keys like `app.presence_state`, `app.device_network_address`, etc.

**View persisted settings:**
```bash
defaults read com.busylight.agent
```

**Reset to defaults:**
```bash
defaults delete com.busylight.agent
```

---

## Testing

### Available via Xcode

Two test suites using **Swift Testing** (`import Testing`):

1. **`LaunchPersistenceTests`** (`@Suite("Launch Persistence")`)
   - `configurationPersistsAcrossRestarts()` — Verify settings survive app restart
   - `defaultConfigurationWhenNothingSaved()` — Verify sensible defaults
   - `presenceStateToggling()` — Verify state machine works

2. **`SettingsTests`** (`@Suite("Settings")`)
   - `deviceNetworkAddressSettings()` — Address persistence
   - `deviceNetworkPortSettings()` — Port validation
   - `launchOnStartupSettings()` — Toggle test
   - `menuBarTextVisibilitySettings()` — Visibility toggle
   - `presenceStateDisplayNames()` — Enum display names
   - `deviceStatusRepresentation()` — DeviceStatus model

### Running Tests

**Full Xcode (Recommended):**
```bash
cd macos-agent
xcodebuild test -scheme BusyLight
```

**Command Line Tools (CLT):** Tests are **automatically skipped**.
```bash
./build.sh test
# [build.sh] Xcode not available (Command Line Tools only).
# [build.sh] Swift Testing requires the full Xcode installation.
# [build.sh] Skipping tests.
```

**Why tests don't run in CLT:**
Swift Testing's `Foundation` cross-import overlay (`_Testing_Foundation`) is a private framework bundled only with Xcode's frameworks, not CLT's. This design prevents CLT from importing Testing. Test files are preserved and compile when run via Xcode.

---

## Swift 6 Concurrency

All code adheres to Swift 6 strict concurrency:

- **Models** (`PresenceState`, `AppConfiguration`) conform to `Sendable`
- **`Logger`** is `@unchecked Sendable` (os_log is thread-safe internally)
- **`ConfigurationManager`** and **`StatusMenuController`** are `@MainActor` (AppKit requires main thread)
- **Test suites** are `@MainActor` (access main-thread-isolated ConfigurationManager)
- **Global loggers** removed `nonisolated(unsafe)` (unnecessary when class is `@unchecked Sendable`)

---

## Logging

View structured logs in macOS Log.app or terminal:

```bash
# All agent logs
log stream --predicate 'subsystem CONTAINS "com.busylight.agent"'

# By subsystem
log stream --predicate 'subsystem == "com.busylight.agent.lifecycle"'
log stream --predicate 'subsystem == "com.busylight.agent.ui"'
log stream --predicate 'subsystem == "com.busylight.agent.configuration"'

# With level filtering
log stream --predicate 'subsystem CONTAINS "com.busylight.agent"' --level debug
```

**Example events logged:**
- Application startup / shutdown
- Configuration load / save
- Menu bar initialization
- Presence state changes
- Device status updates
- Errors

---

## Known Limitations & Future Work

### Current Scope (Completed ✅)
- Menu bar UI with presence display
- Persistent settings storage
- Configuration management
- Lifecycle management (startup, shutdown, restart)
- Structured logging
- Swift 6 strict concurrency

### Deferred (Phase 2+)
- **Device Communication:** Network adapter (REST/WebSocket) to sync presence with physical device
- **Login Item Registration:** Auto-launch on system startup
- **Preferences Window:** GUI for configuration (address, port, launch-on-startup toggle)
- **Advanced Status:** Multi-device support, device discovery, provisioning UI
- **Signing & Notarization:** Distribution via App Store or direct download

---

## Build Wrapper Logic

The `build.sh` script abstracts build complexity:

```bash
#!/usr/bin/env bash

# Detects environment:
# - Requires Swift to be installed
# - Runs `swift build [config]` from macos-agent/
# - For testing, checks if Xcode is installed (vs CLT-only)
#   - If Xcode: runs xcodebuild test
#   - If CLT: prints message and exits gracefully

# Usage:
./build.sh [debug|release|test|clean]
```

**Why this matters:**
- **Consistency:** One command from project root, regardless of where user is
- **CI/CD ready:** Exit codes are sensible (0 = success; tests skipped = success)
- **Developer experience:** Clear messaging when tests can't run

---

## Development Notes

### Architecture Decisions

1. **Library + Executable Split (`BusyLightCore` + `BusyLight`)**
   - Allows tests to import `@testable import BusyLightCore`
   - Keeps app delegates and entry point in executable target
   - Clean separation of library (testable) and app (runtime)

2. **`main.swift` vs `@main`**
   - Swift has a quirk: `@main` attribute cannot coexist with a file literally named `main.swift`
   - Solution: `main.swift` is imperative (creates NSApplication, sets delegate, runs)
   - Real delegate logic is in `BusyLightApp.swift`

3. **`@MainActor` on ConfigurationManager**
   - UserDefaults is thread-safe, but NSStatusBar and menu operations require main thread
   - Isolating the manager to `@MainActor` enforces this at compile time

4. **`@unchecked Sendable` for Logger**
   - `os_log` is internally thread-safe (documented in Apple's concurrency guide)
   - Making Logger `@unchecked Sendable` is appropriate and well-reasoned
   - Global logger instances are just constants that wrap a thread-safe API

5. **Swift Testing Over XCTest**
   - XCTest is Xcode-bundled; Swift Testing is part of Swift standard library (Xcode 16+)
   - Swift Testing offers cleaner syntax (`@Suite`, `@Test`, `#expect`)
   - Modern approach recommended by Apple

### File Organization

- **Models:** Independent, immutable data structures
- **Core:** Service managers (Logger, ConfigurationManager)
- **UI:** Presentation logic (StatusMenuController)
- **Main executable:** Entry point and lifecycle delegates
- **Tests:** Mirror source structure for clarity (`LaunchPersistenceTests.swift`, `SettingsTests.swift`)

---

## Troubleshooting

### "no such module 'Testing'" Error

**Cause:** Running `swift test` from command line on CLT-only system.  
**Solution:** Use Xcode or run `./build.sh test` (auto-detects and skips).

### Menu Icon Not Appearing

**Cause:** Application running but NSStatusBar not initialized.  
**Check:**
```bash
# Verify app is running
ps aux | grep BusyLight

# Check logs
log stream --predicate 'subsystem == "com.busylight.agent.lifecycle"'
```

**Solution:** Ensure `StatusMenuController` is initialized in `applicationDidFinishLaunching(_:)`.

### Settings Not Persisting

**Cause:** ConfigurationManager not calling `saveConfiguration()`.  
**Check:**
```bash
defaults read com.busylight.agent
```

**Solution:** Verify `setPresenceState()` (and other setters) are being called; they auto-save.

---

## References

- [Swift Concurrency](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/)
- [Swift Testing](https://developer.apple.com/documentation/testing) (Xcode 16+)
- [os_log Documentation](https://developer.apple.com/documentation/os/logging)
- [NSStatusBar & NSStatusItem](https://developer.apple.com/documentation/appkit/nsstatusbar)
- [UserDefaults](https://developer.apple.com/documentation/foundation/userdefaults)

---

**Implementation Date:** February 22, 2026  
**Repository:** [busy-light/macos-agent](../macos-agent)  
**Next Phase:** Device communication adapter (REST/WebSocket)
