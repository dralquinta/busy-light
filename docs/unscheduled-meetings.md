# Unscheduled Meeting Detection

BusyLight can automatically detect when you join a meeting that was **not** scheduled on your calendar — for example, an impromptu Zoom call, a quick Teams chat escalated to a video call, or a Google Meet link shared in Slack — and mark you as **busy** immediately.

---

## Supported Providers

| Provider | Detection method | App / Browser |
|---|---|---|
| **Zoom** | Process + window title (Accessibility API) | Native macOS app |
| **Microsoft Teams** | Process + window title (Accessibility API) | Native macOS app |
| **Google Meet** | Browser window title (Accessibility API) | Safari, Chrome, Edge, Brave, Firefox |
| **Teams web** | Browser window title (Accessibility API) | Safari, Chrome, Edge, Brave, Firefox |
| **Zoom web** | Browser window title (Accessibility API) | Safari, Chrome, Edge, Brave, Firefox |

### Limitations

- Zoom and Teams detection requires the respective native desktop apps to be installed. The web versions of both platforms are also supported via browser title inspection.
- Window-title inspection requires the macOS **Accessibility** permission (see [Required permissions](#required-permissions) below). Without this permission, BusyLight falls back to process-only detection, which yields low-confidence results and will not trigger `busy` by default.
- Detection is poll-based. By default, the detectors run every **3 seconds**. There is a short lag between joining a meeting and the status updating.

---

## Detection Approach

### Multi-signal confidence model

Each detector independently contributes a **confidence score** to the decision:

| Confidence | Meaning |
|---|---|
| `none` | No signals; process not found |
| `low` | Process is running but no meeting window confirmed |
| `medium` | *(reserved for future use)* |
| `high` | Process running **and** meeting window title confirmed |

Only detections that reach the configured **threshold** (default: `high`) cause the presence state to change to `busy`. This minimises false positives — for example, having Zoom open in the background without being in a call.

### Precedence with other state sources

Meeting detection follows the same precedence model as the rest of the state machine:

```
System away (screen lock / sleep)    — highest priority
 └─ Manual override (user UI / hotkey)
     └─ Meeting detection (unscheduled)
         └─ Calendar events             — lowest priority
```

- **Manual override always wins.** If you have manually set your status (e.g. "Available"), meeting detection is suppressed until you resume automatic calendar control (`Ctrl+Cmd+4`).
- **In auto mode**, a high-confidence meeting detection overrides the calendar state and marks you as `busy`.
- When the meeting ends, BusyLight requests an immediate calendar sync and reverts to the calendar-derived state.

### Privacy statement

BusyLight's meeting detection is **100% local** and **privacy-first**:

| What IS inspected | What is NOT inspected |
|---|---|
| Running application process names | Microphone or camera audio/video |
| Window titles of Zoom / Teams / browser apps | Screen content or pixels |
| *(nothing else)* | Meeting participants or content |
| | Network packets or URLs |
| | Calendar or contact data |

Window title inspection uses the macOS **Accessibility API** — the same permission used for global hotkeys. It does **not** require Screen Recording permission.

---

## Required Permissions

### Accessibility (required for window-title detection)

BusyLight already requests this permission for global hotkey support (`Ctrl+Cmd+1–6`). No additional steps are required if you have already granted it.

If you have not granted the Accessibility permission:
1. Open **System Settings → Privacy & Security → Accessibility**
2. Find **BusyLight** in the list (click `+` to add it if absent)
3. Toggle the switch **ON**
4. Restart BusyLight

Without this permission, meeting detection falls back to process-only (low confidence) and will **not** automatically mark you as busy (the default threshold is `high`).

---

## How to Enable / Disable and Configure

All settings are persisted in `UserDefaults` under the `com.busylight.agent` suite.

### Enable or disable meeting detection

```shell
# Disable all meeting detection
defaults write com.busylight.agent app.meeting_detection_enabled -bool false

# Re-enable
defaults write com.busylight.agent app.meeting_detection_enabled -bool true
```

### Enable or disable individual providers

```shell
# Disable Zoom detection
defaults write com.busylight.agent app.meeting_provider_zoom_enabled -bool false

# Disable Teams detection
defaults write com.busylight.agent app.meeting_provider_teams_enabled -bool false

# Disable browser-based detection (Google Meet, Teams web, Zoom web)
defaults write com.busylight.agent app.meeting_provider_browser_enabled -bool false
```

### Confidence threshold

The threshold is stored as an integer matching `MeetingConfidence.rawValue`:

| Value | Threshold |
|---|---|
| `0` | none (trigger on any detection — **not recommended**) |
| `1` | low (trigger if app process is running) |
| `2` | medium |
| `3` | high *(default — requires confirmed meeting window)* |

```shell
# Lower threshold to medium
defaults write com.busylight.agent app.meeting_confidence_threshold -int 2

# Reset to default (high)
defaults write com.busylight.agent app.meeting_confidence_threshold -int 3
```

### Poll interval

```shell
# Poll every 5 seconds (reduces CPU usage slightly)
defaults write com.busylight.agent app.meeting_poll_interval_seconds -float 5.0

# Reset to default (3 seconds)
defaults write com.busylight.agent app.meeting_poll_interval_seconds -float 3.0
```

> **Note:** All changes take effect after restarting BusyLight.

---

## Observability and Logs

Meeting detection emits structured log events to the `com.busylight.agent.meeting` subsystem.

### View live meeting detection logs

```bash
log stream --predicate 'subsystem == "com.busylight.agent.meeting"' --level debug
```

### Key log events

| Event | When |
|---|---|
| `meeting.detection.engine.started` | Engine starts (on app launch if enabled) |
| `meeting.detection.engine.stopped` | Engine stops (on app quit) |
| `meeting.detector.polled` | Each detector result (provider, confidence, inMeeting flag) |
| `meeting.status.changed` | Aggregate status transitions (from/to, provider, confidence) |
| `meeting.detected` | A meeting was detected above the threshold |
| `meeting.ended` | Meeting ended and calendar sync was requested |
| `meeting.provider.enabled.changed` | A provider was enabled or disabled at runtime |

### View state machine transitions driven by meetings

```bash
log stream --predicate 'subsystem == "com.busylight.agent.ui" AND eventMessage CONTAINS "meeting"' --level debug
```

---

## Manual Test Matrix

Execute these tests after making any changes to the meeting detection code:

| Scenario | Expected result |
|---|---|
| Open Zoom app, join a meeting | Status → 🔴 Busy (busyReason: zoom) |
| Leave Zoom meeting (close meeting window) | Status reverts to calendar state |
| Open Teams app, start or join a call | Status → 🔴 Busy (busyReason: teams) |
| Leave Teams call | Status reverts to calendar state |
| Open Google Meet in Chrome, join meeting | Status → 🔴 Busy (busyReason: meet) |
| Close Chrome tab with Meet | Status reverts to calendar state |
| Open Teams web meeting in Safari | Status → 🔴 Busy (busyReason: teams) |
| Open Zoom web meeting in browser | Status → 🔴 Busy (busyReason: zoom) |
| Set manual override → Available; then join Zoom | Status remains Available (manual wins) |
| Press `Ctrl+Cmd+4` (resume auto) while in meeting | Status → 🔴 Busy (meeting takes over) |
| Screen lock while in meeting | Status → ⚪ Away (system wins) |
| Unlock screen while still in meeting | Status → 🔴 Busy (meeting restored) |
| Disable meeting detection via `defaults write` + restart | No automatic busy during meeting |

---

## Architecture Reference

The meeting detection subsystem lives in `Sources/BusyLightCore/Meetings/`:

| File | Purpose |
|---|---|
| `MeetingStatus.swift` | `MeetingConfidence`, `MeetingProvider`, `MeetingStatus`, `BusyReason` value types |
| `MeetingDetectorProtocol.swift` | `MeetingDetectorProtocol` and `MeetingDetectionResult` |
| `MeetingProcessInspector.swift` | Shared utility: process detection + Accessibility-based window title inspection |
| `ZoomDetector.swift` | Zoom native app detector |
| `TeamsDetector.swift` | Microsoft Teams native app detector |
| `BrowserMeetingDetector.swift` | Browser-based detector (Meet / Teams web / Zoom web) |
| `MeetingDetectionEngine.swift` | Orchestrator: polls detectors, applies threshold, fires `onMeetingStatusChanged` |

The engine integrates into the presence state machine via a new `StateEvent.meetingDetected(MeetingStatus)` event and a new `StateSource.meeting` (priority equal to `.calendar`).
