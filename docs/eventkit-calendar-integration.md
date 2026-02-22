# EventKit Calendar Integration

BusyLight monitors your macOS Calendar to automatically detect your availability and display it on the menu bar status light.

## Overview

- **Green (🟢)**: Available — no overlapping events
- **Red (🔴)**: Busy — active event marked as busy or unavailable
- **Orange (🟠)**: Tentative — active event marked as tentative
- **Gray (⚪)**: Away — screen is locked or asleep

The calendar scanner runs automatically:
- Every 60 seconds (configurable via `CalendarEngine.scanInterval`)
- Immediately when you unlock the screen after sleep
- Instantly when the system detects a calendar change (new event, edit, delete)

## Setup

### 1. Grant Calendar Access

When BusyLight launches as a proper `.app` bundle (`./BusyLight.app`), macOS will prompt you to grant Calendar access:

```
"BusyLight" would like to access your calendars.
```

Click **Allow**. This permission is remembered per bundle identifier (`com.busylight.agent`).

> **Note**: If the prompt doesn't appear, open **System Settings → Privacy & Security → Calendars** and add BusyLight manually, or run:
> ```bash
> tccutil reset Calendar
> ```
> Then relaunch the app.

### 2. Ensure Calendars Are Synced

macOS Calendar must have your external calendar accounts configured:

**For Google Calendar:**
1. Open **Calendar.app**
2. **Calendar → Add Account… → Google**
3. Sign in and authorize
4. Calendars should appear in Calendar.app sidebar

**For Outlook / Microsoft Exchange:**
1. Open **Calendar.app**
2. **Calendar → Add Account… → Microsoft Exchange** (or **Outlook.com**)
3. Sign in and authorize
4. Calendars should appear in Calendar.app sidebar

**Verify the account is synced:**
- open Calendar.app and confirm your event is visible
- Check that the calendar checkbox in the sidebar is **ticked** (unchecked calendars are hidden from EventKit)

## How It Works

### Permission & Startup
1. BusyLight requests full calendar access (macOS 14+) at first run
2. Scans all calendars configured in System Settings → Internet Accounts
3. Begins polling every 60 seconds

### Scanning
On each scan, BusyLight queries EventKit for all events overlapping the current moment within a ±12 hour window:

```
|--------- 12h ago --------- NOW --------- 12h ahead ---------|
                        [query window]
```

The window is capped at 12 hours to ensure all-day and multi-day events are captured (EventKit requires a date range, not a point query).

### Availability Resolution

Events are processed in priority order:

| State | Priority | Result |
|-------|----------|--------|
| **Busy** | 1 (highest) | Light turns 🔴 red |
| **Unavailable** | 1 | Light turns 🔴 red |
| **Not Supported** | 1 | Light turns 🔴 red |
| **Tentative** | 2 | Light turns 🟠 orange (unless a busy event exists) |
| **Free** | 3 | Does not change availability |
| No events | — | Light turns 🟢 green |

**Why `.notSupported` is treated as busy:**

Google Calendar events synced via CalDAV and Outlook events synced via Exchange frequently arrive in EventKit without the `TRANSP`/`FREEBUSY` property set. EventKit maps this absence to `.notSupported`. Because the user explicitly created a time block, the safe default is to treat it as busy.

### Instant Updates

When you modify a calendar event, EventKit posts `EKEventStoreChanged`. BusyLight listens for this notification:
1. Flushes the cached event store
2. Immediately re-scans
3. Fires the availability callback (updates the light)

This happens in < 100ms, so you see the light change almost instantly.

### Screen Lock / Sleep Detection

BusyLight monitors for screen sleep and lock using `NSWorkspace` notifications:

- **Primary**: `NSWorkspace.screensDidSleepNotification` — most reliable, works from command-line binaries
- **Secondary**: `NSWorkspace.willSleepNotification` — fallback
- **Tertiary**: `DistributedNotificationCenter` `com.apple.screenIsLocked` — best-effort, requires `.app` bundle

When the screen locks, the light turns ⚪ gray (away). When you unlock, BusyLight re-scans the calendar and restores the correct light state.

## Usage

### Automatic (Default)

The light updates automatically as you work:
- Create a meeting → light turns red (if marked busy)
- End the meeting → light turns green
- Lock your screen → light turns gray
- Unlock → light returns to the current calendar state

### Manual Override

Click the status icon and select **Mark as Busy** (when available) to manually override the calendar-driven state. The light will stay red until:
- You click **Resume Calendar Control**
- The app restarts

The override is not persisted across app restarts intentionally — it's a temporary "in a meeting" signal.

### Debug Menu

Right-click the status icon → **Debug**:

- **Scan Calendar Now** — Trigger an immediate scan (useful if you just synced an event)
- **Simulate Screen Lock (Away)** — Test the away state without locking
- **Simulate Screen Unlock (Return)** — Test the return transition

## Troubleshooting

### "Calendar: Paused (no calendars)" or No Events Found

**Symptom**: `calendar.diagnostic.no_calendars` in the logs.

**Cause**: EventKit cannot see any calendars — the app wasn't granted Calendar access, or the access was denied.

**Fix**:
1. Open **System Settings → Privacy & Security → Calendars**
2. Ensure **BusyLight** is in the list and **toggled on**
3. If it's not listed, run `tccutil reset Calendar` and relaunch
4. Restart BusyLight

### Events Not Appearing (Empty Query Results)

**Symptom**: `calendar.diagnostic.visible_calendar ...` appears in logs, but `event_count=0` even when Calendar.app shows an event.

**Cause**: 
- The event exists in Calendar.app but the calendar is unchecked in the sidebar
- The event is on a calendar not synced to macOS yet

**Fix**:
1. Open Calendar.app
2. Ensure the calendar with the event is **checked** in the sidebar (Source → Calendar list)
3. Wait for sync to complete (30–60 seconds for external accounts)
4. Trigger **Debug → Scan Calendar Now** in BusyLight

### Google Calendar or Outlook Events Not Triggering Red Light

**Symptom**: Event exists in Calendar.app, but `calendar.scan.result [event_count=1 ... availability=notSupported]` appears in logs, yet light stays green.

**Cause**: EventKit is returning `availability = .notSupported` for the event (the calendar provider didn't include the TRANSP property). Older BusyLight versions incorrectly treated this as "free."

**Fix**: Ensure you're running the latest build:
```bash
bash build.sh
./debug.sh
```

This build treats `.notSupported` as `.busy`, so the light will turn red.

### Permission Prompt Never Appeared

**Cause**: The `.app` bundle was never properly signed or registered with the system.

**Fix**:
1. Run `tccutil reset Calendar` to clear the TCC cache
2. Run `bash build.sh` to rebuild and reassemble the bundle
3. Launch with `./debug.sh` (or open `BusyLight.app` in Finder)
4. The prompt should appear

### Light Doesn't Update on Calendar Change

**Symptom**: You add an event in Calendar.app but the light doesn't change for 60+ seconds.

**Cause**: EventKit's `EKEventStoreChanged` notification is delayed or didn't fire (can happen with external calendar syncs).

**Fix**: Click **Debug → Scan Calendar Now** to force an immediate rescan. If the light still doesn't update, check that the event is visible in Calendar.app first.

## Logs

All calendar operations are logged to the macOS unified logging system under subsystem `com.busylight.agent.calendar`.

**Stream logs in real-time:**
```bash
./debug.sh
```

Or manually:
```bash
log stream --predicate 'subsystem BEGINSWITH "com.busylight.agent"' --level debug
```

**Key log events:**

| Message | Meaning |
|---------|---------|
| `calendar.scan.execute` | Started a scan at the given query date |
| `calendar.event.found` | Found an overlapping event with the given title and availability |
| `calendar.diagnostic.visible_calendar` | Lists all EventKit-visible calendars (for debugging sync issues) |
| `calendar.diagnostic.no_calendars` | No calendars visible to EventKit — check System Settings → Internet Accounts |
| `calendar.scan.result` | Scan completed with event count and duration |
| `calendar.state.changed` | Resolved availability changed (light will update) |

## Architecture

### Components

**`CalendarPermissionManager`** — Requests and tracks full calendar access permission.

**`CalendarScanner`** — Fetches overlapping events from EventKit within a ±12h window.

**`CalendarAvailabilityResolver`** — Pure logic: maps a list of overlapping events to a `PresenceState` (busy, tentative, available).

**`CalendarEngine`** — Orchestrator: 
- Requests permissions on startup
- Runs a 60s polling timer
- Listens for `EKEventStoreChanged` notifications
- Calls the resolver and fires `onAvailabilityChange` callback

**`SystemPresenceMonitor`** — Tracks screen sleep/wake and fires `onUserAway`/`onUserReturned` callbacks.

**`StatusMenuController`** — Updates the menu bar light and menu items based on availability changes.

### Data Flow

```
┌─────────────────────────────────────────────┐
│ Calendar.app (user creates/edits event)    │
└──────────────────────┬──────────────────────┘
                       │ EKEventStoreChanged
                       ▼
          ┌────────────────────────┐
          │   CalendarEngine       │
          │ (polls every 60s or    │
          │  reacts to store      │
          │  change)              │
          └──────────┬─────────────┘
                     │
                     ▼
          ┌────────────────────────┐
          │ CalendarScanner        │
          │ (queries EventKit)     │
          └──────────┬─────────────┘
                     │
         overlapping events
                     │
                     ▼
        ┌─────────────────────────┐
        │CalendarAvailabilityResolver│
        │(busy > tentative > free)   │
        └──────────┬────────────────┘
                   │
            PresenceState
                   │
                   ▼
        ┌──────────────────────┐
        │ StatusMenuController │  ← screen lock/wake from SystemPresenceMonitor
        │ (update light + menu)│
        └──────────────────────┘
```

### Testability

All components use dependency injection and protocols:

- `CalendarPermissionManaging` — swappable permission logic
- `CalendarEventStoreProtocol` — swappable EventKit access
- `CalendarEventRepresentable` — abstract calendar event without `EKEvent` coupling

Unit tests mock these protocols and test the resolver and engine in isolation without touching the system EventKit database.

## Performance

- **Scan latency**: ~20–50ms per scan (includes EventKit query + resolution)
- **Memory**: < 2 MB (minimal event caching; cleared on every scan)
- **Polling overhead**: Negligible (one 50ms query every 60 seconds = 0.08% CPU)
- **Instant notification**: < 100ms from calendar change to light update
- **Battery impact**: Minimal (no location, no network, single-threaded)

## Limitations

1. **Requires macOS 14+** — Uses `requestFullAccessToEvents()` async API
2. **Only reads calendar data** — BusyLight is read-only; cannot create/edit events
3. **No two-way sync** — Changes made in BusyLight (manual override) don't flow back to Calendar.app
4. **Calendar download required** — External accounts (Google, Outlook) must be fully synced to macOS Calendar first
5. **All-day events always count** — No separate "show all-day as free" option
6. **No calendar filtering** — Scans all calendars; can't exclude personal vs. work calendars yet

## Future Enhancements

- [ ] Per-calendar enable/disable (e.g., show only work calendar)
- [ ] Availability override duration (set "do not disturb" for 1 hour)
- [ ] iCloud account status indicator
- [ ] Event details in menu (time, subject, organizer)
- [ ] Custom colors per availability state
- [ ] Configuration file for scan interval, window size, etc.
