# BusyLight macOS Agent

A minimal menu bar application for managing presence state on MacOS Tahoe. The BusyLight agent runs entirely in the menu bar without requiring a Dock icon or foreground window, enabling low-overhead availability signaling.

## Features

- **Menu Bar Only**: No Dock icon or foreground windows
- **Persistent Settings**: Configuration saved across application restarts
- **Presence Modes**: Available, Busy, Away
- **Device Integration Ready**: Network-based communication prepared (REST/WebSocket)
- **Structured Logging**: Full activity tracking via `os_log`
- **Sleep/Wake Resilient**: Remains active across system sleep cycles

## Quick Start

### Build

```bash
cd macos-agent
xcodebuild -scheme BusyLight -configuration Debug
```

Or via Swift Package Manager:

```bash
swift build
```

### Run

```bash
xcodebuild -scheme BusyLight
```

Or:

```bash
.build/debug/BusyLight
```

The application will launch silently and display an icon in the macOS menu bar (upper-right corner of the screen).

## Usage

1. **Launch the application**: The menu bar icon will appear in the top-right corner
2. **Click the icon** to open the dropdown menu
3. **Choose mode**: `Mode` → `Automatic` (calendar-driven) or `Manual Override`
4. **Set manual status** (manual mode only): `Manual Status` → Available/Tentative/Busy
5. **View device status**: Menu shows online/offline and last sync time
6. **Settings**: Configure WLED host and preset IDs via `Settings…`
7. **Quit**: Select "Quit BusyLight" from the menu

## Permissions

- **No elevated permissions required** for basic operation
- **Network access** will be required in a future phase when device communication is enabled

## Architecture

```
Sources/BusyLight/
├── main.swift              # Application entry point
├── AppDelegate.swift       # Lifecycle management
├── Models/
│   ├── PresenceState.swift      # Available, Busy, Away, Tentative, Unknown
│   ├── DeviceStatus.swift       # Device connection state
│   └── AppConfiguration.swift   # Persistent settings
├── Core/
│   ├── Logger.swift             # Structured logging via os_log
│   └── ConfigurationManager.swift # UserDefaults persistence
├── State/
│   ├── PresenceStateMachine.swift   # State transition coordinator
│   ├── StateEvent.swift             # Input events
│   ├── StateSource.swift            # Source tracking (calendar/manual/system)
│   ├── StateTransition.swift        # Validation rules
│   └── OperatingMode.swift          # Auto vs manual mode
├── Calendar/
│   ├── CalendarEngine.swift         # EventKit integration
│   ├── CalendarScanner.swift        # Event polling
│   └── CalendarAvailabilityResolver.swift # Priority resolution
├── System/
│   └── SystemPresenceMonitor.swift  # Screen lock/sleep detection
└── UI/
    └── StatusMenuController.swift # Menu bar icon and menu
```

## State Machine

The BusyLight agent uses a centralized state machine to coordinate presence state from multiple sources:

### Operating Modes
- **Auto Mode** (default): Presence state automatically resolves from calendar events
- **Manual Mode**: User override active, calendar updates ignored until resumed

### State Precedence
```
System Away (Highest)  ─►  Screen lock/sleep always overrides everything
      │
      ▼
Manual Override        ─►  User toggle blocks calendar updates
      │
      ▼
Calendar Events        ─►  Automatic resolution in auto mode
```

### Configuration Options

**Manual Override Timeout** (`app.manual_override_timeout`):
- Default: `120` minutes (2 hours)
- Set to `-1` for no timeout (indefinite override)
- Automatically resumes calendar control when expired

**State Stabilization Delay** (`app.state_stabilization`):
- Default: `0` seconds (disabled)
- Adds delay before state transitions to prevent rapid oscillation
- Useful at calendar event boundaries

### Key Features
- **Deterministic transitions**: All state changes validated and logged
- **Override precedence**: System > Manual > Calendar
- **Debounce logic**: Prevents redundant transitions and flapping
- **Timeout support**: Optional auto-resume from manual overrides
- **Thread-safe**: @MainActor isolation ensures serialized updates

📖 **Detailed documentation**: [State/README.md](Sources/BusyLightCore/State/README.md)

---

## Configuration

Settings are stored in `UserDefaults` under the suite `com.busylight.agent`. Configuration auto-loads on startup.

**Persistent Settings:**
- `app.presence_state`: Current presence mode (available/busy/away/tentative/unknown)
- `app.device_network_addresses`: Configured WLED device addresses
- `app.device_network_address`: Legacy device host/IP (kept in sync)
- `app.device_network_port`: Device communication port (default: 80)
- `app.launch_on_startup`: Enable login item (not yet implemented)
- `app.show_menu_bar_text`: Display presence state in menu bar
- `app.manual_override_timeout`: Manual override timeout in minutes (default: 120, -1 = none)
- `app.state_stabilization`: State stabilization delay in seconds (default: 0)

## Logging

View structured logs via the macOS log system:

```bash
log stream --predicate 'subsystem == "com.busylight.agent.*"' --level debug
```

Or filter by subsystem:

```bash
log stream --predicate 'subsystem == "com.busylight.agent.lifecycle"'
log stream --predicate 'subsystem == "com.busylight.agent.ui"'
log stream --predicate 'subsystem == "com.busylight.agent.configuration"'
```

## Testing

Run the test suite:

```bash
xcodebuild test -scheme BusyLight
```

Or via Swift Package Manager:

```bash
swift test
```

**Test Coverage:**
- `LaunchPersistenceTests`: Verify settings persist across application restarts
- `SettingsTests`: Validate configuration storage and enum representations

## Hardware Integration (Planned)

The application skeleton is prepared for network-based device communication:

1. **Phase 1** (current): Menu bar UI + settings persistence ✅
2. **Phase 2** (next): REST/WebSocket adapter to sync presence state with device
3. **Phase 3** (future): Advanced features (device discovery, multi-device support, etc.)

## Expected Runtime Behavior

- **Startup**: Logs startup event, loads configuration from UserDefaults, displays menu bar icon
- **Menu interaction**: Toggling presence state logs change and updates menu display
- **Shutdown**: Saves configuration, logs shutdown event
- **System sleep/wake**: Application remains resident and active (no restart required)

## Troubleshooting

### Menu bar UI (Production)

The production menu bar UI is intentionally minimal and includes:

- **Status**: Current presence state
- **Mode**: Automatic or Manual Override
- **Manual Status**: Available, Tentative, Busy (manual mode only)
- **Device**: Online/Offline indicator and last sync timestamp
- **Calendar**: Current calendar engine status
- **Override Timeout**: Manual override auto-resume timeout (manual mode only)
- **Settings…**: WLED host + preset IDs
- **Quit**

Debug-only items (calendar scan, simulated away/return, hotkey debug) are shown only in Debug builds.

### Application appears in Dock

The app is configured with activation policy `.prohibited` to hide the Dock icon. If it appears:

- Force quit the application: `killall BusyLight`
- Rebuild and relaunch

### Settings not persisting

Check `UserDefaults` defaults directly:

```bash
defaults read com.busylight.agent
```

Or review logs:

```bash
log stream --predicate 'subsystem == "com.busylight.agent.configuration"' --level debug
```

## Development Notes

- **Minimum macOS**: Tahoe (12.0)
- **Swift Version**: 5.5+
- **No external dependencies**: Uses AppKit, Foundation, os_log only
- **Architecture**: Event-driven with centralized state management

Future phases will add:
- Device communication layer (HTTP/WebSocket client)
- Preferences window
- Login item registration for auto-start
- Dock menu fallback (if required)

---

**Version**: 0.1.0  
**Status**: Active Development — Menu bar skeleton complete  
**Next**: Device communication adapter
