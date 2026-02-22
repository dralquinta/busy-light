# Calendar Integration — EventKit Presence Engine

The calendar integration engine automatically derives the user's availability
state from local macOS calendar data using Apple's **EventKit** framework.  It
operates entirely on-device — no cloud API or external network call is made.

---

## Directory structure

```
macos-agent/Sources/BusyLightCore/Calendar/
├── CalendarEventRepresentable.swift   — Protocol + EKEvent conformance
├── CalendarPermissionManager.swift    — Permission request/status
├── CalendarScanner.swift              — EventKit event querying
├── CalendarAvailabilityResolver.swift — Availability state resolution
└── CalendarEngine.swift               — Orchestrator (permissions → scan → resolve)

macos-agent/Tests/BusyLightTests/
├── CalendarAvailabilityResolverTests.swift
└── CalendarEngineTests.swift
```

---

## Permission model

macOS requires explicit user consent before an application may read calendar
data.  The authorization flow is:

1. **`CalendarPermissionManager.requestAccess()`** calls the system prompt the
   first time it is invoked.
2. If the user grants access, `EKEventStore` is cleared for use.
3. If the user denies access, a `CalendarPermissionManager.PermissionError.denied`
   error is thrown and the engine stops without scanning.
4. If access is restricted by MDM policy, `.restricted` is thrown.

> **Info.plist requirement**: The host application target must include
> `NSCalendarsUsageDescription` with a human-readable explanation.
> The SPM executable target links EventKit via `linkerSettings`.

### Permission states table

| `EKAuthorizationStatus`       | Mapped `PermissionStatus` | Engine behaviour           |
|-------------------------------|---------------------------|----------------------------|
| `.notDetermined`              | `.notDetermined`          | Shows system prompt        |
| `.authorized` / `.fullAccess` | `.authorized`             | Proceeds with scan         |
| `.denied`                     | `.denied`                 | Throws `.denied`           |
| `.restricted`                 | `.restricted`             | Throws `.restricted`       |
| `.writeOnly` / unknown        | `.unknown`                | Does not scan              |

---

## Availability resolution rules

The resolver (`CalendarAvailabilityResolver`) evaluates all calendar events
whose `[startDate, endDate)` interval contains the current timestamp and applies
the following priority chain:

```
busy > tentative > available
```

| Condition                                               | Resolved `PresenceState` |
|---------------------------------------------------------|--------------------------|
| Any event with `.busy` or `.unavailable` availability   | `.busy`                  |
| Any event with `.tentative` availability, no busy event | `.tentative`             |
| Events with only `.free` / `.notSupported` availability | `.available`             |
| No overlapping events                                   | `.available`             |

The resolution is **deterministic**: given the same set of events it always
returns the same state regardless of event order.

A new `PresenceState.tentative` case was added to the shared model so the
calendar engine can signal tentative availability to the rest of the app.

---

## Scan interval configuration

The scan interval is configurable via `CalendarEngine.scanInterval` (default
**60 seconds**).

```swift
let engine = CalendarEngine()
engine.scanInterval = 30   // scan every 30 seconds
```

The engine also configures an EventKit query window via
`CalendarScanner.queryToleranceSeconds` (default **12 hours** on each side of
`now`).  This window is wide enough to capture all-day and multi-day events.
The resolver then filters down to only events that actually contain the exact
current timestamp.

---

## Usage

```swift
import BusyLightCore

@MainActor
class AppPresenceCoordinator {
    private let engine = CalendarEngine()

    func start() async {
        engine.scanInterval = 60
        engine.onAvailabilityChange = { [weak self] state in
            self?.handleStateChange(state)
        }
        await engine.start()
    }

    func stop() {
        engine.stop()
    }

    private func handleStateChange(_ state: PresenceState) {
        // Update UI, notify device, persist to configuration, etc.
    }
}
```

---

## Observability

All significant events are logged using `os_log` via the centralised
`calendarLogger` (subsystem: `com.busylight.agent.calendar`).

| Log event key                  | When fired                          |
|--------------------------------|-------------------------------------|
| `calendar.permission.request`  | Before the system prompt is shown   |
| `calendar.permission.result`   | After the system prompt resolves    |
| `calendar.engine.start`        | `CalendarEngine.start()` called     |
| `calendar.engine.stop`         | `CalendarEngine.stop()` called      |
| `calendar.scan.start`          | Before each EventKit query          |
| `calendar.scan.execute`        | Inside `CalendarScanner`            |
| `calendar.scan.result`         | After fetching events               |
| `calendar.scan.complete`       | After resolving state               |
| `calendar.state.changed`       | When `PresenceState` transitions    |

To stream logs in a terminal:

```bash
log stream --predicate 'subsystem BEGINSWITH "com.busylight.agent.calendar"' --level debug
```

---

## Running the tests

The tests use **Swift Testing** and require a full Xcode installation (not just
Command Line Tools) because of Swift Testing's cross-import overlay for
Foundation.

```bash
xcodebuild test -scheme BusyLight
```

The calendar tests use mock objects (`MockCalendarEventStore`,
`MockCalendarPermissionManager`) and never invoke the real `EKEventStore`, so
they run without requiring calendar entitlements in a CI environment.

---

## Known limitations and edge cases

| Limitation | Notes |
|---|---|
| **No background calendar change notifications** | The engine polls on a timer. Events added or removed between scans are not detected until the next interval. |
| **All-day events** | Included in scans. Their `endDate` is midnight *after* the event day (exclusive end). |
| **Events crossing midnight** | Correctly detected; the query window is ±12 hours. |
| **Free events** | Events marked `.free` are treated as "available" regardless of overlap. |
| **Write-only access (macOS 14+)** | The engine treats `.writeOnly` as insufficient and will not scan. |
| **Calendar permission revocation** | If the user revokes permission while the engine is running, the next scan will fail with an EventKit error (logged via `calendarLogger`). The engine remains in its last known state and must be restarted after re-granting permission. |
| **System calendar database unavailable** | Rare; EventKit will throw an error that is caught and logged. State remains unchanged. |
