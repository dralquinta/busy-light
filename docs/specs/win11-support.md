---
layout: default
title: Windows 11 Support — Technical Specification
description: Full-parity specification for porting the BusyLight presence agent to Windows 11, covering architecture, calendar integration, meeting detection, hotkeys, networking, packaging, and test strategy.
---

# Windows 11 Support — Technical Specification

**Spec ID:** `win11-support`
**Tracking issue:** [#31 — Introduce support for Windows](https://github.com/dralquinta/busy-light/issues/31)
**Status:** Draft — pending approval
**Target platform:** Windows 11 (build 22000+), x64 and ARM64
**Reference implementation:** `macos-agent/` at `v1.0.3`
**Author:** BusyLight maintainers
**Date:** 2026-09-17

---

## Table of Contents

1. [Purpose and Scope](#1-purpose-and-scope)
2. [Baseline: Complete Inventory of Current macOS Functionality](#2-baseline-complete-inventory-of-current-macos-functionality)
3. [Platform Capability Mapping](#3-platform-capability-mapping)
4. [Technology Decision](#4-technology-decision)
5. [Target Architecture](#5-target-architecture)
6. [Repository Layout](#6-repository-layout)
7. [Component Specifications](#7-component-specifications)
   - [7.1 Domain Model](#71-domain-model-presencestate-operatingmode-statesource)
   - [7.2 State Machine](#72-state-machine)
   - [7.3 Configuration and Persistence](#73-configuration-and-persistence)
   - [7.4 Calendar Integration](#74-calendar-integration)
   - [7.5 Meeting Detection](#75-meeting-detection)
   - [7.6 System Presence Monitor](#76-system-presence-monitor)
   - [7.7 Global Hotkeys](#77-global-hotkeys)
   - [7.8 Office Hours Scheduler](#78-office-hours-scheduler)
   - [7.9 WLED Network Layer](#79-wled-network-layer)
   - [7.10 Tray UI](#710-tray-ui)
   - [7.11 Settings UI](#711-settings-ui)
   - [7.12 Logging and Diagnostics](#712-logging-and-diagnostics)
   - [7.13 Launch on Startup](#713-launch-on-startup)
   - [7.14 Application Lifecycle](#714-application-lifecycle)
8. [Concurrency and Threading Model](#8-concurrency-and-threading-model)
9. [Permissions and Consent Model](#9-permissions-and-consent-model)
10. [Build, Packaging, and Distribution](#10-build-packaging-and-distribution)
11. [CI/CD](#11-cicd)
12. [Test Strategy](#12-test-strategy)
13. [Observability and Support](#13-observability-and-support)
14. [Delivery Plan](#14-delivery-plan)
15. [Risk Register](#15-risk-register)
16. [Open Questions](#16-open-questions)
17. [Appendix A — Event Name Catalogue](#appendix-a--event-name-catalogue)
18. [Appendix B — Configuration Key Reference](#appendix-b--configuration-key-reference)
19. [Appendix C — Win32 API Reference](#appendix-c--win32-api-reference)

---

## 1. Purpose and Scope

### 1.1 Problem statement

BusyLight today ships a single agent: a macOS 14+ menu-bar application written in Swift 6 that reads the user's calendar, detects unscheduled meetings, tracks screen-lock/sleep, accepts global hotkeys and manual overrides, resolves all of those inputs through a priority state machine, and broadcasts the resulting presence state to one or more WLED/ESP32 devices over HTTP on the local network.

Windows users have no agent at all. Issue #31 requires that "Windows needs the same level of support that macOS currently has."

### 1.2 Goals

- **G1 — Functional parity.** Every user-visible behaviour listed in [§2](#2-baseline-complete-inventory-of-current-macos-functionality) is available on Windows 11, with the same semantics, the same precedence rules, and the same defaults.
- **G2 — Behavioural equivalence of the state machine.** The presence state machine is a literal port: identical events, identical priorities, identical transition-guard outcomes, identical logs. Two machines fed the same event sequence must produce the same state sequence.
- **G3 — Hardware protocol identity.** The Windows agent speaks the exact same WLED JSON API (`POST /json/state`, `GET /json/info`) with the same request bodies, retry policy, deduplication, and health-check cadence. A single WLED device must be drivable by either agent with no reconfiguration.
- **G4 — Local-first by default.** The default configuration performs no network calls outside the user's LAN. Any cloud-backed calendar source is strictly opt-in and clearly labelled.
- **G5 — Low overhead.** Idle CPU < 1% on a modern laptop; working set < 150 MB; no window in the taskbar, no console window, tray-only presence.
- **G6 — Shippable artefacts.** Signed MSIX package plus a portable ZIP, produced by CI from a tag, published to the same GitHub Release as the macOS DMG.

### 1.3 Non-goals

- **NG1** — Windows 10 support. Windows 10 may work incidentally but is not tested and not supported. `MinVersion` is set to 10.0.22000.0.
- **NG2** — A shared cross-platform codebase with the Swift agent. See [§4](#4-technology-decision) for the rationale. Parity is maintained by specification and by a shared conformance test corpus, not by shared binaries.
- **NG3** — Rewriting or re-specifying the ESP32/WLED firmware side. Hardware docs (`docs/hardware.md`, `docs/module-assembly.md`) are platform-neutral and unchanged.
- **NG4** — Windows-only features that macOS lacks (Focus Assist integration, Teams presence API, Slack status sync). Recorded as future work in [§16](#16-open-questions), explicitly out of scope for v1.
- **NG5** — Store distribution via the Microsoft Store. The MSIX is sideloaded/winget-installed for v1; Store submission is future work.

### 1.4 Definition of done

Windows support is complete when:

1. All parity items in [§2](#2-baseline-complete-inventory-of-current-macos-functionality) are implemented and each has at least one automated test or a documented manual test case in `docs/module-testing.md`.
2. The 12 hardware test cases in `docs/module-testing.md` pass against a real WLED device driven by the Windows agent.
3. `windows-agent` builds green in CI on `windows-latest` for `win-x64` and `win-arm64`.
4. A tagged release produces a signed MSIX and a portable ZIP attached to the GitHub Release.
5. `README.md`, `docs/index.md`, `docs/architecture.md`, `docs/configuration.md`, `docs/hotkey.md`, and `docs/software.md` document both platforms.

---

## 2. Baseline: Complete Inventory of Current macOS Functionality

This section is the authoritative parity checklist. Each row is a requirement on the Windows agent. Source references are to `macos-agent/Sources/`.

### 2.1 Presence model

| ID | Behaviour | macOS source |
|----|-----------|--------------|
| P-1 | Six presence states: `available`, `busy`, `away`, `tentative`, `unknown`, `off`, each with a display name | `BusyLightCore/Models/PresenceState.swift` |
| P-2 | Three operating modes: `auto` (calendar-driven), `manual` (user override active), `off` (suspended) | `BusyLightCore/State/OperatingMode.swift` |
| P-3 | Six state sources with numeric priority: `system`=3, `officeHours`=2, `manual`=2, `calendar`=1, `meeting`=1, `startup`=0 | `BusyLightCore/State/StateSource.swift` |
| P-4 | `BusyReason` metadata attached to every busy state: `calendar`, `zoom`, `teams`, `meet`, `manual`, `unknown` | `BusyLightCore/Meetings/MeetingStatus.swift` |
| P-5 | `DeviceConnectionStatus`: `online` / `offline` / `unknown` | `BusyLightCore/Models/DeviceConnectionStatus.swift` |

### 2.2 State machine

| ID | Behaviour | macOS source |
|----|-----------|--------------|
| SM-1 | Eleven events: `calendarUpdated`, `manualOverride`, `systemAway`, `systemReturned`, `resumeAuto`, `startupInitialize`, `checkOverrideExpiry`, `turnOff`, `officeHoursChanged`, `hotkeyPressed`, `meetingDetected` | `State/StateEvent.swift` |
| SM-2 | `resumeAuto` is processed with **absolute priority** before any other handling, including before expiry checks | `State/PresenceStateMachine.swift:handleEvent` |
| SM-3 | In `off` mode, `calendar`, `system`, and `meeting` sources are rejected with reason `system-is-off` | `State/StateTransition.swift` |
| SM-4 | `system` source overrides everything except `off` mode | `State/StateTransition.swift` |
| SM-5 | In `manual` mode, `calendar` and `meeting` sources are rejected with reason `manual-override-active` | `State/StateTransition.swift` |
| SM-6 | Lower-priority sources cannot override higher-priority ones (reason `insufficient-priority`), except when the current source is `startup` | `State/StateTransition.swift` |
| SM-7 | Calendar updates that match the current state are dropped as no-ops | `PresenceStateMachine.handleCalendarUpdate` |
| SM-8 | Manual overrides expire after a configurable timeout (default 30 min; `nil` = never) and auto-resume calendar control | `PresenceStateMachine.scheduleExpiryCheck` |
| SM-9 | Manual override is blocked while `system` away is active (reason `system-away-active`) | `PresenceStateMachine.handleManualOverride` |
| SM-10 | `systemAway` snapshots `(state, source)` and `systemReturned` restores it; falls back to `unknown` | `PresenceStateMachine.handleSystemAway/Returned` |
| SM-11 | `resumeAuto` cancels the override timer, cancels stabilization, resets `currentSource` to `startup`, sets mode `auto`, and requests an immediate calendar sync | `PresenceStateMachine.handleResumeAuto` |
| SM-12 | `turnOff` cancels timers, sets mode `off`, forces state `off` | `PresenceStateMachine.turnOff` |
| SM-13 | Office hours: leaving the window forces `off` with source `officeHours`, but only from `auto` mode; re-entering resumes auto **only if** the machine turned itself off (`isOffBecauseOutsideOfficeHours`) | `PresenceStateMachine.applyOfficeHours` |
| SM-14 | Meeting detected → `busy` with source `meeting`; meeting ended while source is `meeting` → force `available` then request a calendar sync | `PresenceStateMachine.handleMeetingDetected` |
| SM-15 | Optional stabilization delay (`stateStabilizationSeconds`, default 0) debounces transitions; a newer transition cancels a pending one | `PresenceStateMachine.applyStateTransition` |
| SM-16 | Three callbacks: `onStateChanged(state, source, busyReason)`, `onModeChanged(mode)`, `onRequestCalendarSync()` | `PresenceStateMachine` |

### 2.3 Calendar

| ID | Behaviour | macOS source |
|----|-----------|--------------|
| C-1 | Requests calendar read permission at startup; distinguishes not-determined / authorized / denied / restricted / write-only | `Calendar/CalendarPermissionManager.swift` |
| C-2 | Polls every 60 s, plus an immediate scan on start, plus an event-driven scan on store change | `Calendar/CalendarEngine.swift` |
| C-3 | Queries a ±12 h window and then filters to events whose `[start, end)` contains *now* | `Calendar/CalendarScanner.swift` |
| C-4 | Availability resolution priority: any `busy`/`unavailable`/`notSupported` → `busy`; else any `tentative` → `tentative`; else `available` | `Calendar/CalendarAvailabilityResolver.swift` |
| C-5 | `notSupported` is deliberately treated as **busy** (Google/Outlook events often omit TRANSP) | `CalendarAvailabilityResolver.swift` |
| C-6 | Forces a remote source refresh (CalDAV/Exchange) before every scan | `CalendarScanner.refreshRemoteSources` |
| C-7 | Per-calendar filtering by title; empty list means "all calendars"; a filter matching zero calendars falls back to all calendars and logs `calendar.filter.no_matches` | `CalendarScanner.fetchEventsOverlapping` |
| C-8 | Filter validation logs `ok` / `warning` (some titles unmatched) / `error` (none matched) | `CalendarScanner.validateCalendarFilter` |
| C-9 | Diagnostics: logs every overlapping event's title/availability/start/end; when zero events found, logs every visible calendar and its account | `CalendarScanner.fetchCurrentEvents` |
| C-10 | `scanNow()` resets the cache, forces `currentState = .away` so the callback always fires, and rescans | `CalendarEngine.scanNow` |
| C-11 | Exposes `(title, source)` pairs for the calendar picker UI | `CalendarEngine.getAvailableCalendars` |

### 2.4 Meeting detection

| ID | Behaviour | macOS source |
|----|-----------|--------------|
| M-1 | Five detectors by default: Zoom native, Teams native, and browser detectors for Meet, Teams-web, Zoom-web | `Meetings/MeetingDetectionEngine.defaultDetectors` |
| M-2 | Polls all enabled detectors every `meetingPollIntervalSeconds` (default 3.0 s) | `MeetingDetectionEngine.start` |
| M-3 | Confidence ladder `none`=0 < `low`=1 < `medium`=2 < `high`=3; results below `confidenceThreshold` (default `high`) are treated as `none` | `Meetings/MeetingStatus.swift` |
| M-4 | Highest-confidence detector wins; aggregate status is debounced — callback only on change of (confidence, provider) | `MeetingDetectionEngine.poll` |
| M-5 | Native detectors: process running + matching window title → `high`/`combined`; process running only → `low`/`process`; not running → `none` | `Meetings/ZoomDetector.swift`, `TeamsDetector.swift` |
| M-6 | Browser detector reads window titles of Chrome, Safari, Edge, Brave, Chromium, Firefox; matches per-provider title patterns | `Meetings/BrowserMeetingDetector.swift` |
| M-7 | For Meet and Teams-web, a title match alone is insufficient — an "active indicator" (camera / microphone / recording / screen shar / calling) must also be present, to avoid stale-tab false positives | `BrowserMeetingDetector.detect` |
| M-8 | `clearAndSuppressFor(seconds:)` clears status and suppresses polling for a window (used for 5 s after "Resume Calendar Control") | `MeetingDetectionEngine.clearAndSuppressFor` |
| M-9 | Per-provider enable/disable at runtime | `MeetingDetectionEngine.setProvider` |
| M-10 | No screen recording, no audio capture, no pixel reads, no tab URLs — window titles and process names only | `Meetings/MeetingProcessInspector.swift` |

### 2.5 System presence

| ID | Behaviour | macOS source |
|----|-----------|--------------|
| S-1 | Away on display sleep, system sleep, or screen lock | `System/SystemPresenceMonitor.swift` |
| S-2 | Return on display wake, system wake, or screen unlock | `System/SystemPresenceMonitor.swift` |
| S-3 | Away/return are de-duplicated — multiple triggers in sequence fire the callback once | `SystemPresenceMonitor.handleAway/handleReturn` |
| S-4 | `simulateAway()` / `simulateReturn()` for debug-menu testing | `SystemPresenceMonitor` |

### 2.6 Hotkeys

| ID | Behaviour | macOS source |
|----|-----------|--------------|
| H-1 | Six global hotkeys: Available, Tentative, Busy, Resume-Calendar, Turn-Off, Away | `System/HotkeyManager.swift` |
| H-2 | Hotkeys work regardless of which application has focus | `NSEvent.addGlobalMonitorForEvents` |
| H-3 | Hotkey presses are equivalent to manual overrides (same code path, same expiry) | `PresenceStateMachine.handleHotkeyOverride` |
| H-4 | Resume-Calendar also clears and suppresses meeting detection for 5 s and triggers an immediate scan | `BusyLightApp.swift` |
| H-5 | Bindings are persisted and user-reconfigurable | `Core/ConfigurationManager.swift`, `UI/HotkeyPreferencesController.swift` |
| H-6 | Legacy F13–F17 bindings are auto-migrated to the modern combinations on load | `ConfigurationManager.loadConfiguration` |

### 2.7 Office hours

| ID | Behaviour | macOS source |
|----|-----------|--------------|
| O-1 | Daily local-time window with a per-weekday mask; default enabled, Mon–Fri, 09:00–17:00 | `Models/AppConfiguration.swift` |
| O-2 | Evaluated every 60 s and on every settings change | `BusyLightApp.startOfficeHoursMonitoring` |
| O-3 | Supports windows that wrap past midnight; the weekday test then applies to the *previous* day | `OfficeHoursConfiguration.contains(_:calendar:)` |
| O-4 | `start == end` means "all day" | `OfficeHoursConfiguration.contains` |
| O-5 | When disabled, `contains()` always returns `true` (never gates) | `OfficeHoursConfiguration.contains` |
| O-6 | Human-readable description and a parser for `Mon-Fri 09:00-17:00` syntax | `OfficeHoursConfiguration.scheduleDescription/parseSchedule` |

### 2.8 WLED networking

| ID | Behaviour | macOS source |
|----|-----------|--------------|
| N-1 | `POST /json/state` with `{"ps": <preset>, "v": true}`; `GET /json/info` for identity/health | `Network/WLEDTypes.swift`, `HTTPAdapter.swift` |
| N-2 | Per-state preset IDs, defaults Available=1, Tentative=2, Busy=3, Away=4, Unknown=5, Off=6, range 1–250 | `Models/AppConfiguration.swift` |
| N-3 | Configurable HTTP timeout, floor **and** default 2500 ms | `AppConfiguration.normalizedWledHttpTimeout` |
| N-4 | Retry with exponential backoff 100/200/400 ms, max 3 attempts; **never** retry on an HTTP 4xx/5xx response | `HTTPAdapter.executeWithRetry` |
| N-5 | Proxies explicitly disabled for all WLED traffic | `HTTPAdapter.makeRawHTTPParameters` |
| N-6 | Connection discovery order: (1) verify configured addresses, (2) if none verified and discovery enabled, mDNS browse, (3) if still none, /24 subnet scan | `NetworkClient.performConnect` |
| N-7 | A host is accepted as WLED only if `/json/info` returns a version containing `0.` or `wled` | `NetworkClient.isWLEDInfo` |
| N-8 | Device identity is the MAC from `/json/info`; address is the `ip` field when it is a valid IPv4, else the probed host | `NetworkClient.verifyConfiguredDevices` |
| N-9 | Discovered addresses are written back to configuration automatically | `NetworkClient.persistDiscoveredDeviceAddresses` |
| N-10 | Parallel broadcast to all online devices via a task group | `NetworkClient.sendState` |
| N-11 | Per-device deduplication — skip the POST when `lastPresetSent == presetId` | `NetworkClient.sendPresetToDevice` |
| N-12 | Send returns `(state, deliveredCount, totalCount)` for UI feedback | `WLEDStateSendResult` |
| N-13 | If the device list is empty at send time, force a rediscovery and retry once | `NetworkClient.sendState` |
| N-14 | Health poll every `wledHealthCheckInterval` s (default 10) via `GET /json/info`, with a 1-retry probe client | `NetworkClient.performHealthCheck` |
| N-15 | Offline→online transition clears `lastPresetSent` and fires `onDeviceReconnected`, which re-sends the current state | `NetworkClient`, `BusyLightApp` |
| N-16 | When no devices are known, background rediscovery is rate-limited to once per 5 s | `NetworkClient.recoverDevices` |
| N-17 | OS network-path-available notification triggers reconnect + re-send | `BusyLightApp.startNetworkPathMonitoring` |
| N-18 | Manual host override tears down monitoring, cancels in-flight requests, reconnects, restarts monitoring | `NetworkClient.applyDeviceHostOverride` |
| N-19 | Subnet scan enumerates `x.y.z.1–254` for every private IPv4 interface, 64-way concurrency, priority addresses probed first, skips the host's own addresses, obeys an overall timeout | `Network/LocalNetworkScanner.swift` |
| N-20 | IPv4 validation: exactly 4 dot-separated octets, each 1–3 digits, each 0–255 | `Network/NetworkAddressValidator.swift` |
| N-21 | Raw HTTP/1.1 client handles `Content-Length` and `Transfer-Encoding: chunked` responses | `HTTPAdapter.parseRawHTTPResponse` |

### 2.9 Tray / menu UI

| ID | Behaviour | macOS source |
|----|-----------|--------------|
| U-1 | Tray-only application — no Dock/taskbar entry, no main window | `BusyLightApp.applicationDidFinishLaunching` |
| U-2 | Icon reflects state: 🟢 available, 🔴 busy, 🟠 tentative, ⚪ away, ⚫ unknown, ⬛ off | `StatusMenuController.updateButtonAppearance` |
| U-3 | Menu order: Status → Devices summary → Signal → sep → Control → Manual Status (hidden unless manual) → sep → Calendar status → sep → Override Timeout (hidden unless manual) → [Debug] → sep → Calendars → Settings → Quit | `StatusMenuController.setupMenu` |
| U-4 | `Status:` line shows state + qualifier: `(Calendar)`, `(Zoom Meeting)`, `(Teams Meeting)`, `(Google Meet)`, `(Meeting)`, `(System)`, `(Office Hours)`, `(Automatic)`, `(Manual)`, `(Manual Override)`, `(Disabled)` | `StatusMenuController.updatePresenceState` |
| U-5 | `Devices: <Online\|Searching> (N online)` summary line | `StatusMenuController.deviceSummaryTitle` |
| U-6 | `Signal:` line shows `Sending X...` → `Sent X (n/m)` or `Failed X (n/m)` | `StatusMenuController.updateSignalFeedback` |
| U-7 | Control submenu: Automatic Calendar Control (⌃⌘4 accelerator), Manual Override, Turn Off BusyLight | `StatusMenuController.setupMenu` |
| U-8 | Manual Status submenu: Set Available / Set Tentative / Set Busy, with a checkmark on the active one | `StatusMenuController` |
| U-9 | Calendar status line: `Starting…`, `Active`, `Permission required`, `Overridden`, `Disabled`, `Resuming…`, `Scanning…`, `<State> ●` | `StatusMenuController.setCalendarEngineStatus` |
| U-10 | Override Timeout submenu: 15 / 30 / 60 min, 2 h, 4 h, Never — with a checkmark, visible only in manual mode | `StatusMenuController` |
| U-11 | Calendars submenu: "All Calendars" plus one checkable item per `<title> (<account>)`; selecting every calendar persists as "all" (empty list) | `StatusMenuController.buildCalendarMenu` |
| U-12 | Settings submenu: Devices (status / connected-to / last-sync / Configure Devices…), Office Hours…, Preferences… | `StatusMenuController.setupMenu` |
| U-13 | Preferences dialog: WLED host (IPv4), four preset IDs, and the office-hours editor; validation errors raise dedicated alerts | `StatusMenuController.openSettings` |
| U-14 | Office-hours editor: On checkbox, 7 day toggles (M T W T F S S), From/To 30-minute pickers, All-day checkbox; rejects an empty weekday set | `StatusMenuController.makeOfficeHoursEditor` |
| U-15 | Device tooltip lists each online device as `● <name> (<address>:<port>)` | `StatusMenuController.updateDeviceList` |
| U-16 | Debug submenu (debug builds only): Scan Calendar Now, Hotkey Debug Info, Simulate Screen Lock/Unlock, Simulate Manual Override → each state, Clear Override | `StatusMenuController.setupMenu` |
| U-17 | Quit item | `StatusMenuController.quitApp` |

### 2.10 Configuration, logging, lifecycle

| ID | Behaviour | macOS source |
|----|-----------|--------------|
| X-1 | 27 persisted settings under `app.*` keys, loaded at startup and saved on every mutation | `Models/AppConfiguration.swift`, `Core/ConfigurationManager.swift` |
| X-2 | Legacy single `deviceNetworkAddress` migrates into the `deviceNetworkAddresses` array | `ConfigurationManager.loadConfiguration` |
| X-3 | Device port is pinned to 80 regardless of stored value | `ConfigurationManager.getDeviceNetworkPort` |
| X-4 | Structured logging across 8 subsystems: lifecycle, ui, configuration, device, error, calendar, network, meeting | `Core/Logger.swift` |
| X-5 | Log format `event [k=v k=v]` at info level; errors carry a context prefix | `Logger.logEvent/logError` |
| X-6 | Graceful shutdown stops every monitor, cancels every task, and saves configuration | `BusyLightApp.applicationWillTerminate` |
| X-7 | The accessibility/permission prompt is deferred ~5 s after launch so it cannot block device discovery and the first state send | `BusyLightApp.applicationDidFinishLaunching` |

---

## 3. Platform Capability Mapping

| Capability | macOS mechanism | Windows 11 mechanism | Parity |
|---|---|---|---|
| Tray presence | `NSStatusItem` + `NSMenu` | `NOTIFYICONDATA` / `NotifyIcon` + `ContextMenuStrip` | Full — icon is an image, not text (see [§7.10](#710-tray-ui)) |
| Hidden from task switcher | `LSUIElement` + `.prohibited` activation policy | WinExe with no main window; `WS_EX_TOOLWINDOW` on the message window | Full |
| Calendar read | EventKit `EKEventStore` | `Windows.ApplicationModel.Appointments.AppointmentStore` (primary), Outlook COM, Graph, ICS | **Partial — see [§7.4](#74-calendar-integration)** |
| Calendar change notification | `EKEventStoreChanged` | `AppointmentStore.StoreChanged` event | Full |
| Free/busy semantics | `EKEventAvailability` | `AppointmentBusyStatus` | Full — mapping in [§7.4.4](#744-availability-mapping) |
| Process enumeration | `NSWorkspace.runningApplications` | `Process.GetProcesses()` | Full, no permission required |
| Window title enumeration | Accessibility API, **requires TCC grant** | `EnumWindows` + `GetWindowText`, **no permission required** | Better than macOS |
| Camera / mic in use | not used | `CapabilityAccessManager` consent-store registry keys | Windows-only improvement |
| Screen lock / unlock | `com.apple.screenIsLocked` distributed notification | `SystemEvents.SessionSwitch` (`SessionLock`/`SessionUnlock`) | Full, more reliable |
| Display sleep / wake | `NSWorkspace.screensDidSleep/Wake` | `RegisterPowerSettingNotification(GUID_CONSOLE_DISPLAY_STATE)` | Full |
| System sleep / wake | `NSWorkspace.willSleep/didWake` | `SystemEvents.PowerModeChanged` (`Suspend`/`Resume`) | Full |
| Global hotkeys | `NSEvent.addGlobalMonitorForEvents`, **requires Accessibility grant** | `RegisterHotKey`, **no permission required** | Better than macOS |
| mDNS / Bonjour | `NetServiceBrowser` | `Makaretu.Dns.Multicast` (managed mDNS over UDP 5353) | Full, requires a firewall rule |
| Local network consent | `NSLocalNetworkUsageDescription` TCC prompt | none required; Windows Firewall prompt on first inbound bind | Simpler |
| Raw HTTP | `NWConnection` hand-rolled HTTP/1.1 | `HttpClient` + `SocketsHttpHandler` | Full — the hand-rolled parser is unnecessary |
| Network path monitor | `NWPathMonitor` | `NetworkChange.NetworkAddressChanged` / `NetworkAvailabilityChanged` | Full |
| Local interface enumeration | `getifaddrs` | `NetworkInterface.GetAllNetworkInterfaces()` | Full, with prefix length available |
| Settings persistence | `UserDefaults` | JSON file in `%LOCALAPPDATA%\BusyLight\` | Full |
| Structured logging | `os_log` + `log stream` | `Microsoft.Extensions.Logging` → rolling file + `EventSource` (ETW) | Full |
| Launch at login | `LSSharedFileList` (declared, not implemented) | `HKCU\...\Run` value, or MSIX `StartupTask` | Parity-plus |
| Main-thread isolation | `@MainActor` | Single UI thread + `SynchronizationContext` | Full |
| Structured concurrency | Swift `Task` / `TaskGroup` | `Task` / `Parallel.ForEachAsync` / `CancellationToken` | Full |
| App packaging | `.app` bundle → DMG | MSIX package + portable ZIP | Full |
| Code signing | `codesign` + notarization | Authenticode `signtool` + timestamping | Full |

---

## 4. Technology Decision

### 4.1 Options considered

**Option A — Port Swift to Windows.** The Swift toolchain supports Windows and `swift-corelibs-foundation` provides `Date`, `JSONEncoder`, `URL`, etc. In principle `BusyLightCore` could be shared.

Rejected. Of the 14 source files in `BusyLightCore`, only 6 are free of Apple frameworks (`PresenceState`, `OperatingMode`, `StateSource`, `StateEvent`, `StateTransition`, `NetworkAddressValidator`, plus most of `PresenceStateMachine` and `OfficeHoursConfiguration`). Everything else imports `EventKit`, `AppKit`, `Network`, `ApplicationServices`, or `os.log`. Every UI surface, every OS integration, and the entire networking stack would need a Win32 interop layer written in Swift, a combination with almost no ecosystem, no mature tray/windowing library, and a small pool of contributors. The shared surface — roughly 900 lines of pure logic — is not worth the toolchain risk.

**Option B — .NET 8 (C#) desktop agent.** Rejected nothing; this is the recommendation. Rationale in §4.2.

**Option C — Electron / Tauri.** Rejected. A Chromium runtime for a tray icon violates G5 (overhead). Global hotkey and window-title enumeration still require native modules. Tauri (Rust) is lighter but has the same small-ecosystem problem as Swift-on-Windows for the calendar integration, which is the hardest part of this port.

**Option D — C++/WinRT.** Rejected. Best raw platform access, worst development velocity and contributor accessibility, no test ecosystem comparable to xUnit.

### 4.2 Decision

> **Build `windows-agent/` as a .NET 8 (LTS) application targeting `net8.0-windows10.0.22621.0`, written in C#, using WinForms `NotifyIcon` for the tray and WPF for dialogs, with WinRT projections enabled for calendar access.**

Justification against the goals:

- **G1/G2** — C# `async`/`await`, `Task`, and `CancellationToken` map 1:1 onto Swift concurrency, so the state machine, network client, and engines port as near-literal translations. This keeps the two agents reviewable side by side.
- **G3** — `HttpClient` over `SocketsHttpHandler` gives full control of timeouts, proxy bypass, and connection lifetime.
- **G4/§7.4** — `net8.0-windows10.0.22621.0` as the TFM turns on the CsWinRT projections needed for `AppointmentStore`, which is the only *local* calendar source on Windows.
- **G5** — Framework-dependent or ReadyToRun self-contained publish; measured idle footprint of an equivalent tray agent is ~40–60 MB working set.
- **G6** — First-class MSIX/SignTool/winget tooling, and `windows-latest` GitHub runners.
- Mixed `<UseWindowsForms>true</UseWindowsForms>` + `<UseWPF>true</UseWPF>` in one project is supported and lets us use the battle-tested `NotifyIcon`/`ContextMenuStrip` for the tray while building the Preferences and Office Hours dialogs in XAML.

### 4.3 Dependency budget

Third-party dependencies are kept minimal and must be permissively licensed (MIT/Apache-2.0/BSD) to remain compatible with the project's source-available licence.

| Package | Purpose | Licence | Alternative if rejected |
|---|---|---|---|
| `Makaretu.Dns.Multicast` | mDNS browse/resolve for WLED discovery | MIT | Hand-rolled UDP 5353 client (~400 LoC) |
| `Microsoft.Extensions.Logging` + `Microsoft.Extensions.Logging.Console` | Logging abstraction | MIT | — |
| `Serilog.Sinks.File` *(or a 100-line rolling file sink)* | Rolling file log | Apache-2.0 | In-house sink |
| `Microsoft.Windows.CsWinRT` (implicit via TFM) | WinRT projections | MIT | — |
| `xunit`, `xunit.runner.visualstudio`, `Moq` *(or hand-written fakes)* | Tests | Apache-2.0 / MIT / BSD | Hand-written fakes (preferred; see [§12](#12-test-strategy)) |
| `Microsoft.Graph` + `Microsoft.Identity.Client` | **Optional** Graph calendar provider only | MIT | Feature omitted |

`Microsoft.Office.Interop.Outlook` is *not* referenced; the Outlook COM provider uses late binding via `Type.GetTypeFromProgID("Outlook.Application")` + `dynamic`, so the agent has no build-time or run-time dependency on Office being installed.

---

## 5. Target Architecture

```
┌────────────────────────────────────────────────────────────────────────────┐
│                          BusyLight.Agent (WinExe)                          │
│                                                                            │
│  ┌──────────────────┐  ┌───────────────────────┐  ┌────────────────────┐   │
│  │ ICalendarProvider │  │  PresenceStateMachine │  │   WledClient       │   │
│  │  ├ AppointmentStore│─▶│                       │─▶│  (broadcast +      │   │
│  │  ├ OutlookCom     │  │  system      (prio 3) │  │   health + resend) │   │
│  │  ├ MicrosoftGraph │  │  officeHours (prio 2) │  └─────────┬──────────┘   │
│  │  └ IcsUrl         │  │  manual      (prio 2) │            │              │
│  └──────────────────┘  │  calendar    (prio 1) │            │              │
│                        │  meeting     (prio 1) │            │              │
│  ┌──────────────────┐  │  startup     (prio 0) │            │              │
│  │ MeetingDetection │─▶│                       │            │              │
│  │  ├ ZoomDetector  │  └───────┬───────────────┘            │              │
│  │  ├ TeamsDetector │          │                            │              │
│  │  ├ BrowserDetector│         ▼                            │              │
│  │  └ CaptureDevice │  ┌───────────────────────┐            │              │
│  └──────────────────┘  │  TrayUiController     │            │              │
│                        │  (NotifyIcon + menus) │            │              │
│  ┌──────────────────┐  └───────────────────────┘            │              │
│  │ SystemPresence   │─▶                                     │              │
│  │  SessionSwitch   │      ┌──────────────────────┐         │              │
│  │  PowerMode       │      │  ConfigurationStore  │         │              │
│  │  DisplayState    │      │  %LOCALAPPDATA%\...  │         │              │
│  └──────────────────┘      └──────────────────────┘         │              │
│                                                              │              │
│  ┌──────────────────┐      ┌──────────────────────┐         │              │
│  │  HotkeyManager   │─▶    │  OfficeHoursScheduler│─▶       │              │
│  │  RegisterHotKey  │      │  (60 s tick)         │         │              │
│  └──────────────────┘      └──────────────────────┘         │              │
└──────────────────────────────────────────────────────────────┼──────────────┘
                                                               │ HTTP/JSON
                                                               ▼
                                                  ┌────────────────────────┐
                                                  │  WLED (ESP32)          │
                                                  │  POST /json/state      │
                                                  │  GET  /json/info       │
                                                  └────────────────────────┘
```

The topology is identical to `docs/architecture.md`. Only the leaf adapters differ.

### 5.1 Layering rules

1. **`BusyLight.Core`** — no `using System.Windows.*`, no `using Windows.*`, no P/Invoke. Pure domain: presence model, state machine, office hours, WLED protocol types, availability resolver, IPv4 validator, configuration model. 100% unit-testable, no UI thread required.
2. **`BusyLight.Platform`** — all OS integration behind interfaces declared in `Core`: `ICalendarProvider`, `IMeetingDetector`, `ISystemPresenceMonitor`, `IHotkeyManager`, `IWledHttpClient`, `IDeviceDiscovery`, `IDeviceScanner`, `IConfigurationStore`, `IStartupRegistrar`, `IUiDispatcher`.
3. **`BusyLight.Agent`** — composition root, tray UI, dialogs, `Program.Main`. Wires `Core` to `Platform` exactly as `BusyLightApp.swift` does.
4. Dependency direction is strictly `Agent → Platform → Core`. `Core` references nothing.

---

## 6. Repository Layout

```
busy-light/
├── macos-agent/                       # unchanged
├── windows-agent/                     # NEW
│   ├── BusyLight.sln
│   ├── Directory.Build.props           # shared TFM, nullable, analyzers, version
│   ├── src/
│   │   ├── BusyLight.Core/
│   │   │   ├── BusyLight.Core.csproj              # net8.0 (no -windows) — portable
│   │   │   ├── Models/
│   │   │   │   ├── PresenceState.cs
│   │   │   │   ├── DeviceStatus.cs
│   │   │   │   ├── DeviceConnectionStatus.cs
│   │   │   │   ├── AppConfiguration.cs
│   │   │   │   └── OfficeHoursConfiguration.cs
│   │   │   ├── State/
│   │   │   │   ├── OperatingMode.cs
│   │   │   │   ├── StateSource.cs
│   │   │   │   ├── StateEvent.cs
│   │   │   │   ├── StateTransition.cs
│   │   │   │   └── PresenceStateMachine.cs
│   │   │   ├── Calendar/
│   │   │   │   ├── ICalendarProvider.cs
│   │   │   │   ├── CalendarEvent.cs
│   │   │   │   ├── CalendarAvailability.cs
│   │   │   │   ├── CalendarAvailabilityResolver.cs
│   │   │   │   └── CalendarEngine.cs
│   │   │   ├── Meetings/
│   │   │   │   ├── MeetingStatus.cs
│   │   │   │   ├── MeetingProvider.cs
│   │   │   │   ├── MeetingConfidence.cs
│   │   │   │   ├── IMeetingDetector.cs
│   │   │   │   └── MeetingDetectionEngine.cs
│   │   │   ├── Network/
│   │   │   │   ├── WledTypes.cs
│   │   │   │   ├── IWledHttpClient.cs
│   │   │   │   ├── IDeviceDiscovery.cs
│   │   │   │   ├── IDeviceScanner.cs
│   │   │   │   ├── NetworkAddressValidator.cs
│   │   │   │   └── WledClient.cs
│   │   │   ├── Scheduling/OfficeHoursScheduler.cs
│   │   │   └── Diagnostics/BusyLightLog.cs
│   │   ├── BusyLight.Platform/
│   │   │   ├── BusyLight.Platform.csproj          # net8.0-windows10.0.22621.0
│   │   │   ├── Calendar/
│   │   │   │   ├── AppointmentStoreCalendarProvider.cs
│   │   │   │   ├── OutlookComCalendarProvider.cs
│   │   │   │   ├── MicrosoftGraphCalendarProvider.cs
│   │   │   │   ├── IcsUrlCalendarProvider.cs
│   │   │   │   └── CompositeCalendarProvider.cs
│   │   │   ├── Meetings/
│   │   │   │   ├── WindowEnumerator.cs
│   │   │   │   ├── ProcessInspector.cs
│   │   │   │   ├── CaptureDeviceMonitor.cs
│   │   │   │   ├── ZoomDetector.cs
│   │   │   │   ├── TeamsDetector.cs
│   │   │   │   └── BrowserMeetingDetector.cs
│   │   │   ├── System/
│   │   │   │   ├── SystemPresenceMonitor.cs
│   │   │   │   ├── PowerNotificationWindow.cs
│   │   │   │   ├── HotkeyManager.cs
│   │   │   │   ├── HotkeyWindow.cs
│   │   │   │   └── StartupRegistrar.cs
│   │   │   ├── Network/
│   │   │   │   ├── WledHttpClient.cs
│   │   │   │   ├── MdnsDeviceDiscovery.cs
│   │   │   │   ├── LocalSubnetScanner.cs
│   │   │   │   └── NetworkPathMonitor.cs
│   │   │   ├── Storage/JsonConfigurationStore.cs
│   │   │   └── Interop/NativeMethods.cs
│   │   └── BusyLight.Agent/
│   │       ├── BusyLight.Agent.csproj             # WinExe, UseWindowsForms + UseWPF
│   │       ├── Program.cs
│   │       ├── AgentHost.cs                       # ≡ BusyLightApp.swift
│   │       ├── Tray/
│   │       │   ├── TrayUiController.cs
│   │       │   └── TrayMenuBuilder.cs
│   │       ├── Dialogs/
│   │       │   ├── PreferencesWindow.xaml(.cs)
│   │       │   ├── OfficeHoursWindow.xaml(.cs)
│   │       │   └── HotkeyPreferencesWindow.xaml(.cs)
│   │       ├── Assets/
│   │       │   ├── tray-available-{light,dark}.ico
│   │       │   ├── tray-busy-{light,dark}.ico
│   │       │   ├── tray-tentative-{light,dark}.ico
│   │       │   ├── tray-away-{light,dark}.ico
│   │       │   ├── tray-unknown-{light,dark}.ico
│   │       │   ├── tray-off-{light,dark}.ico
│   │       │   └── BusyLight.ico
│   │       └── app.manifest
│   ├── tests/
│   │   ├── BusyLight.Core.Tests/
│   │   └── BusyLight.Platform.Tests/
│   ├── packaging/
│   │   ├── msix/
│   │   │   ├── Package.appxmanifest
│   │   │   ├── Assets/                             # Store logos, 44x44, 150x150, …
│   │   │   └── priconfig.xml
│   │   ├── winget/dralquinta.BusyLight.yaml
│   │   └── firewall/BusyLight-Firewall.ps1
│   ├── build.ps1                                   # ≡ build.sh
│   ├── debug.ps1                                   # ≡ debug.sh
│   └── release.ps1                                 # ≡ release.sh (Windows artefacts)
├── docs/
│   └── specs/win11-support.md                      # this document
└── .github/workflows/release.yml                   # gains a windows job
```

---

## 7. Component Specifications

### 7.1 Domain model (`PresenceState`, `OperatingMode`, `StateSource`)

Direct translation. String values on the wire and in the config file **must** match the Swift `rawValue`s exactly, so logs and config files are comparable across platforms.

```csharp
public enum PresenceState { Available, Busy, Away, Tentative, Unknown, Off }

public static class PresenceStateExtensions
{
    // rawValue parity: "available", "busy", "away", "tentative", "unknown", "off"
    public static string ToRawValue(this PresenceState s) => s switch { ... };
    public static PresenceState? FromRawValue(string raw) => ...;
    public static string DisplayName(this PresenceState s) => s switch { ... };
}

public enum OperatingMode { Auto, Manual, Off }          // "auto" | "manual" | "off"

public enum StateSource { Calendar, Meeting, Manual, OfficeHours, System, Startup }

public static class StateSourceExtensions
{
    public static int Priority(this StateSource s) => s switch
    {
        StateSource.System      => 3,
        StateSource.OfficeHours => 2,
        StateSource.Manual      => 2,
        StateSource.Calendar    => 1,
        StateSource.Meeting     => 1,
        StateSource.Startup     => 0,
        _ => 0
    };
}

public enum BusyReason { Calendar, Zoom, Teams, Meet, Manual, Unknown }
```

`StateEvent` is a discriminated union. Swift enums with payloads become a sealed record hierarchy:

```csharp
public abstract record StateEvent
{
    public sealed record CalendarUpdated(PresenceState State) : StateEvent;
    public sealed record ManualOverride(PresenceState State) : StateEvent;
    public sealed record HotkeyPressed(PresenceState State) : StateEvent;
    public sealed record MeetingDetected(MeetingStatus Status) : StateEvent;
    public sealed record OfficeHoursChanged(bool IsWithinOfficeHours) : StateEvent;
    public sealed record SystemAway : StateEvent;
    public sealed record SystemReturned : StateEvent;
    public sealed record ResumeAuto : StateEvent;
    public sealed record StartupInitialize : StateEvent;
    public sealed record CheckOverrideExpiry : StateEvent;
    public sealed record TurnOff : StateEvent;
}
```

**Requirement D-1.** `StateTransition.IsAllowed(...)` returns `(bool Allowed, string? Reason)` and reproduces `StateTransition.swift` line for line, including the exact reason strings `"system-is-off"`, `"manual-override-active"`, `"insufficient-priority"`.

**Requirement D-2.** `StateTransition.SourceForEvent` and `StateTransition.TargetStateForEvent` reproduce the Swift mappings exactly — including the two non-obvious ones: `TurnOff` reports source `Startup`, and `ResumeAuto`/`CheckOverrideExpiry` report source `Manual`.

### 7.2 State machine

**Requirement SM-W1.** `PresenceStateMachine` is ported from `PresenceStateMachine.swift` with no behavioural change. Every branch listed in [§2.2](#22-state-machine) is preserved, including the ordering constraint that `ResumeAuto` short-circuits at the top of `HandleEvent` before the expiry check.

**Requirement SM-W2.** Swift `Task` + `Task.sleep` for the expiry and stabilization timers becomes `CancellationTokenSource` + `Task.Delay(ct)`. Cancellation semantics are identical: a new transition cancels the pending stabilization; `ResumeAuto` and `TurnOff` cancel both timers.

```csharp
private CancellationTokenSource? _expiryCts;
private CancellationTokenSource? _stabilizationCts;

private void ScheduleExpiryCheck(int minutes)
{
    _expiryCts?.Cancel();
    _expiryCts = new CancellationTokenSource();
    var token = _expiryCts.Token;
    _ = Task.Run(async () =>
    {
        try { await Task.Delay(TimeSpan.FromMinutes(minutes), token); }
        catch (OperationCanceledException) { return; }
        _dispatcher.Post(() => HandleEvent(new StateEvent.CheckOverrideExpiry()));
    });
}
```

**Requirement SM-W3.** All mutation of machine state happens on the UI dispatcher thread (see [§8](#8-concurrency-and-threading-model)), mirroring `@MainActor`. `HandleEvent` asserts `_dispatcher.IsOnUiThread` in Debug builds.

**Requirement SM-W4.** The machine emits the same log events with the same key/value pairs: `state.machine.initialized`, `state.transition.success`, `state.transition.blocked`, `state.transition.ignored`, `state.override.set`, `state.override.expired`, `state.mode.changed`, `state.system.off`, `state.system.returned`, `state.calendar.sync.requested`, `state.stabilization.cancelled`, `meeting.detected`, `meeting.ended`.

**Requirement SM-W5 (conformance corpus).** A JSON corpus at `docs/specs/state-machine-conformance.json` enumerates event sequences and expected `(state, mode, source, busyReason)` after each step. Both agents run it as a test. Adding a state-machine behaviour means adding a corpus case. This is how G2 is enforced mechanically rather than by review.

Corpus entry shape:

```json
{
  "name": "manual-override-blocks-calendar",
  "config": { "manualOverrideTimeoutMinutes": 30, "stateStabilizationSeconds": 0 },
  "steps": [
    { "event": { "kind": "startupInitialize" },
      "expect": { "state": "unknown", "mode": "auto", "source": "startup" } },
    { "event": { "kind": "manualOverride", "state": "busy" },
      "expect": { "state": "busy", "mode": "manual", "source": "manual", "busyReason": "manual" } },
    { "event": { "kind": "calendarUpdated", "state": "available" },
      "expect": { "state": "busy", "mode": "manual", "source": "manual",
                  "blockedReason": "manual-override-active" } }
  ]
}
```

### 7.3 Configuration and persistence

#### 7.3.1 Storage location and format

**Requirement CFG-1.** Settings live in a single JSON document:

- Unpackaged: `%LOCALAPPDATA%\BusyLight\config.json`
- Packaged (MSIX): the same path, transparently redirected by the package container to `%LOCALAPPDATA%\Packages\<PackageFamilyName>\LocalCache\Local\BusyLight\config.json`.

Resolve via `Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData)`; do not special-case MSIX.

**Requirement CFG-2.** The JSON uses the **same key strings** as the Swift `CodingKeys` (`app.presence_state`, `app.device_network_addresses`, …). See [Appendix B](#appendix-b--configuration-key-reference). A user can diff a macOS `defaults export com.busylight.agent` against a Windows `config.json` and see the same keys.

**Requirement CFG-3.** The document carries `"schema_version": 1` at the root. Unknown keys are preserved on round-trip (round-trip through `JsonNode`, patch, re-serialize) so a downgrade does not destroy newer settings.

**Requirement CFG-4.** Writes are atomic: serialize to `config.json.tmp` in the same directory, `File.Move(tmp, config.json, overwrite: true)`. A corrupt or unparseable file is renamed to `config.corrupt-<timestamp>.json`, defaults are loaded, and `configuration.load.failed` is logged at error level — the agent never refuses to start because of bad config.

**Requirement CFG-5.** Saves are debounced by 250 ms and coalesced. The Swift implementation writes on every setter; on Windows that is a file write, so `ConfigurationStore.Save()` schedules a flush rather than writing synchronously. A synchronous `Flush()` runs on shutdown.

#### 7.3.2 Settings surface

All 27 settings from `AppConfiguration.swift` are supported with identical defaults. Windows adds the settings in the second table.

Parity settings (defaults identical to macOS): `presenceState`, `deviceNetworkAddress`, `deviceNetworkPort` (pinned to 80), `deviceNetworkAddresses`, `wledPresetAvailable`=1, `wledPresetTentative`=2, `wledPresetBusy`=3, `wledPresetAway`=4, `wledPresetUnknown`=5, `wledPresetOff`=6, `wledHttpTimeout`=2500 (floor 2500), `wledHealthCheckInterval`=10, `wledEnableDiscovery`=true, `launchOnStartup`=false, `showMenuBarText`=true, `manualOverrideTimeoutMinutes`=30, `stateStabilizationSeconds`=0, `officeHours` (enabled, Mon–Fri, 540–1020), `hotkeyBindings`, `meetingDetectionEnabled`=true, `meetingProviderZoomEnabled`=true, `meetingProviderTeamsEnabled`=true, `meetingProviderBrowserEnabled`=true, `meetingConfidenceThreshold`=3, `meetingPollIntervalSeconds`=3.0, `enabledCalendarTitles`=[].

New Windows-only settings:

| Key | Type | Default | Purpose |
|---|---|---|---|
| `app.calendar_provider` | string | `"auto"` | `auto` \| `appointments` \| `outlook` \| `graph` \| `ics` — see [§7.4](#74-calendar-integration) |
| `app.calendar_ics_urls` | string[] | `[]` | ICS subscription URLs when provider is `ics` |
| `app.calendar_graph_account` | string | `""` | Cached MSAL home account id; never a token |
| `app.meeting_provider_capture_enabled` | bool | `true` | Enable the mic/camera capture-device signal |
| `app.hotkey_modifiers` | uint | `MOD_CONTROL\|MOD_ALT` | Modifier mask applied to all numeric hotkeys |
| `app.tray_icon_theme` | string | `"auto"` | `auto` \| `light` \| `dark` |
| `app.log_level` | string | `"information"` | `trace`…`error` |

**Requirement CFG-6.** `launchOnStartup` is *honoured* on Windows (macOS persists but ignores it). Toggling it writes/removes the `Run` registry value or enables/disables the MSIX `StartupTask`.

**Requirement CFG-7.** Hotkey bindings are stored as Windows virtual-key codes, not macOS Carbon codes. Because both platforms share the key name `app.hotkey_bindings` but not the value space, the loader rejects any stored value outside `0x01–0xFE` and falls back to defaults, logging `hotkey.bindings.reset.invalid_keycode`. This also implements the Windows equivalent of H-6 (legacy binding migration).

### 7.4 Calendar integration

This is the highest-risk component and the only one where exact parity is not achievable with a single API. macOS has one aggregated, locally-cached, permission-gated calendar store (EventKit). Windows 11 does not.

#### 7.4.1 Provider abstraction

```csharp
public interface ICalendarProvider : IAsyncDisposable
{
    string Name { get; }
    Task<CalendarAccessResult> RequestAccessAsync(CancellationToken ct);
    Task<IReadOnlyList<CalendarInfo>> GetCalendarsAsync(CancellationToken ct);
    Task<IReadOnlyList<CalendarEvent>> FetchEventsOverlappingAsync(
        DateTimeOffset instant,
        TimeSpan tolerance,
        IReadOnlyList<string> enabledCalendarTitles,
        CancellationToken ct);
    Task RefreshSourcesAsync(CancellationToken ct);
    event EventHandler? StoreChanged;
}

public enum CalendarAccessResult { Granted, Denied, Restricted, NotDetermined, Unavailable }
public sealed record CalendarInfo(string Title, string Source);
public sealed record CalendarEvent(
    string? Id, string? Title, DateTimeOffset Start, DateTimeOffset End,
    bool IsAllDay, CalendarAvailability Availability, string CalendarTitle);
public enum CalendarAvailability { Busy, Free, Tentative, Unavailable, NotSupported }
```

`CalendarEngine`, `CalendarScanner`-equivalent logic, and `CalendarAvailabilityResolver` live in `BusyLight.Core` and depend only on this interface — exactly as the Swift versions depend on `CalendarEventStoreProtocol` and `CalendarPermissionManaging`.

#### 7.4.2 Providers

**(a) `AppointmentStoreCalendarProvider` — default, local-first.**

Uses `Windows.ApplicationModel.Appointments`:

```csharp
var store = await AppointmentManager.RequestStoreAsync(AppointmentStoreAccessType.AllCalendarsReadOnly);
var appointments = await store.FindAppointmentsAsync(
    windowStart, windowDuration,
    new FindAppointmentsOptions { MaxCount = 200, FetchProperties = { AppointmentProperties.Subject,
        AppointmentProperties.StartTime, AppointmentProperties.Duration,
        AppointmentProperties.AllDay, AppointmentProperties.BusyStatus } });
var calendars = await store.FindAppointmentCalendarsAsync(FindAppointmentCalendarsOptions.IncludeHidden);
```

- **Local-first:** reads the on-device Windows appointment store. No network calls by BusyLight.
- **Aggregation:** surfaces every account registered with Windows (Outlook/M365, Google, iCloud via the account provider), matching EventKit's behaviour.
- **Change notification:** subscribe to `AppointmentStore.StoreChanged` → raise `StoreChanged` → `CalendarEngine` resets and rescans. This is the direct analogue of `EKEventStoreChanged`.
- **Consent:** `AppointmentManager.RequestStoreAsync` triggers the Windows "Let this app access your calendar?" consent flow and is gated by Settings → Privacy & security → Calendar. This requires the `appointments` capability, which requires **package identity** — i.e. the app must run from the MSIX (or be registered with a sparse package). This is the single hardest constraint on the port and the main reason MSIX is the primary distribution format ([§10](#10-build-packaging-and-distribution)).
- **Known limitation:** users who use only the *new* Outlook client and have never added an account to the Windows account system may see an empty store. Detection: `FindAppointmentCalendarsAsync` returns zero calendars → report `CalendarAccessResult.Unavailable`, log `calendar.diagnostic.no_calendars` (same event name as macOS), and let the composite provider fall through.

**(b) `OutlookComCalendarProvider` — classic Outlook desktop.**

Late-bound COM automation, no Office reference:

```csharp
var progId = Type.GetTypeFromProgID("Outlook.Application");
dynamic outlook = Activator.CreateInstance(progId);
dynamic ns = outlook.GetNamespace("MAPI");
dynamic folder = ns.GetDefaultFolder(9 /* olFolderCalendar */);
dynamic items = folder.Items;
items.IncludeRecurrences = true;
items.Sort("[Start]");
dynamic restricted = items.Restrict($"[Start] <= '{end:g}' AND [End] >= '{start:g}'");
```

- `AppointmentItem.BusyStatus` (`OlBusyStatus`: 0=Free, 1=Tentative, 2=Busy, 3=OutOfOffice, 4=WorkingElsewhere) maps per [§7.4.4](#744-availability-mapping).
- `IncludeRecurrences = true` plus a `Restrict` on the window is mandatory for recurring events — a plain `Items` enumeration returns only masters.
- Enumerate `ns.Folders` recursively to list shared/secondary calendars for the picker.
- Change notification: poll only (`ItemChange` COM events are unreliable across the automation boundary); the 60 s engine tick covers this.
- Availability probe: `Marshal.GetActiveObject` / ProgID lookup fails → provider reports `Unavailable`, cheaply and without launching Outlook.
- **Requirement CAL-COM-1.** Every `dynamic` COM object is released with `Marshal.FinalReleaseComObject` in a `finally` block; the whole provider runs on a dedicated STA thread. COM leaks here manifest as an un-closable Outlook process, which would be an unacceptable user-visible bug.

**(c) `MicrosoftGraphCalendarProvider` — opt-in, cloud.**

`GET /me/calendarView?startDateTime=…&endDateTime=…` with MSAL interactive auth, scope `Calendars.Read`, token cached in DPAPI-protected storage (`ProtectedData.Protect` with `DataProtectionScope.CurrentUser`).

- **Requirement CAL-GRAPH-1.** Disabled by default. Enabling it shows a modal that states plainly: *"This sends your calendar queries to Microsoft's servers and requires sign-in. BusyLight's other calendar sources read only local data."* This is required by G4.
- `ShowAs` (`free`/`tentative`/`busy`/`oof`/`workingElsewhere`/`unknown`) maps per [§7.4.4](#744-availability-mapping).
- No refresh token or access token is ever written to `config.json`; only the MSAL home account id.

**(d) `IcsUrlCalendarProvider` — opt-in, works everywhere.**

Polls one or more published `.ics` URLs on the engine tick, honours `Cache-Control`/`ETag`, parses `VEVENT` with `DTSTART`/`DTEND`/`RRULE`/`TRANSP`/`X-MICROSOFT-CDO-BUSYSTATUS`. `TRANSP:TRANSPARENT` → `Free`; `TRANSP:OPAQUE` → `Busy`; absent → `NotSupported` (which resolves to busy, matching C-5). This is the escape hatch for Google Workspace users with no Windows account integration.

#### 7.4.3 Composite provider and selection

**Requirement CAL-1.** `CompositeCalendarProvider` implements the `auto` mode: probe in order `appointments` → `outlook` → `ics` (Graph is never auto-selected because it is cloud). The first provider returning `Granted` *and* at least one calendar wins. The chosen provider is logged as `calendar.provider.selected [provider=… calendars=N]` and surfaced in the tray under `Calendar: Active (Outlook)`.

**Requirement CAL-2.** An explicit `app.calendar_provider` value pins the provider and disables probing.

**Requirement CAL-3.** If no provider yields calendars, the engine reports `Permission required` in the tray, logs `calendar.diagnostic.no_calendars`, and the state machine simply never receives `calendarUpdated` events. Meeting detection, hotkeys, manual overrides, and office hours all keep working. The agent is useful without a calendar.

#### 7.4.4 Availability mapping

| BusyLight `CalendarAvailability` | EventKit (macOS) | `AppointmentBusyStatus` | `OlBusyStatus` | Graph `showAs` | ICS |
|---|---|---|---|---|---|
| `Busy` | `.busy` | `Busy` | `olBusy` (2) | `busy` | `TRANSP:OPAQUE` |
| `Free` | `.free` | `Free` | `olFree` (0) | `free` | `TRANSP:TRANSPARENT` |
| `Tentative` | `.tentative` | `Tentative` | `olTentative` (1) | `tentative` | `X-MICROSOFT-CDO-BUSYSTATUS:TENTATIVE` |
| `Unavailable` | `.unavailable` | `OutOfOffice` | `olOutOfOffice` (3) | `oof` | `X-…:OOF` |
| `NotSupported` | `.notSupported` | `WorkingElsewhere`, or absent | `olWorkingElsewhere` (4) | `unknown`, or absent | property absent |

**Requirement CAL-4.** `CalendarAvailabilityResolver` is a literal port: `Busy`/`Unavailable`/`NotSupported` → `busy`; else any `Tentative` → `tentative`; else `available`. `NotSupported` → busy is deliberate and is re-asserted here because the same Google/Outlook TRANSP-omission problem exists on Windows.

#### 7.4.5 Engine behaviour

`CalendarEngine` (in `Core`) reproduces `CalendarEngine.swift`:

- `StartAsync()` → request access → validate filter → immediate scan → start 60 s timer → subscribe to `StoreChanged`.
- `ScanNowAsync()` → set `_currentState = Away` so the change callback always fires → refresh sources → scan.
- `PerformScanAsync()` → `RefreshSourcesAsync` → `FetchEventsOverlappingAsync(now, 12 h, enabledTitles)` → resolve → `ApplyState`.
- `ApplyState` fires `OnAvailabilityChange` only on change.
- Query window is ±12 h, then filtered to `start <= now && now < end`, matching C-3 and the `occursAt` semantics.
- Filter semantics, fallback-to-all, and the three validation outcomes match C-7 and C-8 exactly.
- The same diagnostic logging as C-9, with the same event names.

**Requirement CAL-5.** The scan is fully cancellable and never blocks the UI thread; the provider call runs on the thread pool (or a dedicated STA thread for Outlook COM) and the result is posted back to the dispatcher.

### 7.5 Meeting detection

The engine (`MeetingDetectionEngine`) is a literal port of the Swift engine — polling, threshold, highest-confidence-wins, debounce, suppression window, per-provider toggles. Only the detectors change, and on Windows they get *better* signals.

#### 7.5.1 Window and process inspection

`WindowEnumerator` replaces `MeetingProcessInspector.windowTitles(for:)`:

```csharp
public static IReadOnlyList<WindowInfo> EnumerateTopLevelWindows()
{
    var results = new List<WindowInfo>();
    NativeMethods.EnumWindows((hWnd, _) =>
    {
        if (!NativeMethods.IsWindowVisible(hWnd)) return true;
        var length = NativeMethods.GetWindowTextLength(hWnd);
        if (length == 0) return true;
        var sb = new StringBuilder(length + 1);
        NativeMethods.GetWindowText(hWnd, sb, sb.Capacity);
        NativeMethods.GetWindowThreadProcessId(hWnd, out var pid);
        results.Add(new WindowInfo(hWnd, sb.ToString(), (int)pid));
        return true;
    }, IntPtr.Zero);
    return results;
}
```

**Requirement MD-1.** No Accessibility-equivalent permission is required. `EnumWindows`/`GetWindowText` work for any process at the same or lower integrity level. This removes the macOS failure mode where the browser detector silently returns `.none` without the TCC grant.

**Requirement MD-2.** For UWP/packaged hosts whose top-level title is `ApplicationFrameWindow`, fall back to UI Automation (`AutomationElement.FromHandle(hWnd).Current.Name`) or walk to the `Windows.UI.Core.CoreWindow` child. Relevant for some Teams builds.

**Requirement MD-3.** Enumeration is snapshotted once per poll and shared by all detectors (the macOS version re-enumerates per detector). Process list likewise. Target: a full poll costs < 15 ms.

**Requirement MD-4.** Privacy invariant, unchanged from macOS: window titles and process names only. No tab URLs, no page content, no screen capture, no audio capture, no input capture. The capture-device signal ([§7.5.3](#753-capture-device-signal)) reads a usage timestamp, never a stream.

#### 7.5.2 Detectors

| Detector | Process names / bundle equivalents | High-confidence signal | Low-confidence signal |
|---|---|---|---|
| `ZoomDetector` | `Zoom.exe`, `Zoom` | `CptHost.exe` present **or** a window titled `Zoom Meeting` / `Zoom Webinar` | `Zoom.exe` running only |
| `TeamsDetector` | `ms-teams.exe`, `Teams.exe`, `Microsoft Teams` | a window title containing `meeting`, `call`, or `calling`; **or** `ms-teams.exe` holding the mic | `ms-teams.exe` running only |
| `BrowserMeetingDetector(Meet)` | `chrome.exe`, `msedge.exe`, `firefox.exe`, `brave.exe`, `chromium.exe`, `opera.exe`, `vivaldi.exe` | title matches `meet:` **and** an active indicator | — |
| `BrowserMeetingDetector(TeamsWeb)` | as above | title matches `microsoft teams` / `teams meeting` / `calling \| microsoft teams` / `meeting \| microsoft teams` **and** an active indicator | — |
| `BrowserMeetingDetector(ZoomWeb)` | as above | title matches `zoom meeting` / `zoom – ` / `zoom - ` / `zoom.us` | — |
| `CaptureDeviceDetector` *(new)* | any | the browser or a native client currently holds the microphone | — |

**Requirement MD-5.** `CptHost.exe` is a Windows-specific, near-definitive Zoom in-meeting signal — the process exists only while a meeting window is open. It raises the Zoom detector to `High`/`Combined` even without a title match, which is strictly better than the macOS heuristic.

**Requirement MD-6.** The "active indicator" rule from M-7 is preserved verbatim for Meet and Teams-web: a title match alone is not enough; the title set must also contain `camera`, `microphone`, `recording`, `screen shar`, or `calling`. On Windows this rule is *augmented*, not replaced, by the capture-device signal — if the browser holds the microphone, that also satisfies the active-indicator requirement. Rationale: browsers localise and truncate the "camera/mic in use" title decoration inconsistently, and the registry signal is language-independent.

**Requirement MD-7.** Browser process names are matched case-insensitively against `Process.ProcessName` (which excludes `.exe`), and the window→process association is done by PID so a title from an unrelated app can never be attributed to a browser.

#### 7.5.3 Capture-device signal

```
HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone\NonPackaged\<mangled-exe-path>
HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone\<PackageFamilyName>
  LastUsedTimeStart : QWORD (FILETIME)
  LastUsedTimeStop  : QWORD (FILETIME)  -- 0 means "in use right now"
```

Also read the parallel `…\ConsentStore\webcam\…` tree.

**Requirement MD-8.** `CaptureDeviceMonitor` enumerates both trees, treats `LastUsedTimeStop == 0` as "in use now", maps the mangled path (`#` in place of `\`) back to an executable path, and resolves it to a process name. It exposes `IsMicrophoneInUseBy(processName)` and `IsCameraInUseBy(processName)`.

**Requirement MD-9.** Registry reads are cached for one poll interval. Also watch for changes with `RegNotifyChangeKeyValue` on a background thread to avoid hot polling; fall back to per-poll reads if the notification fails.

**Requirement MD-10.** `HKLM` is also checked for services, but the practical cases are all `HKCU`. Missing keys are not an error — the signal degrades to "unknown", never to a false positive.

**Requirement MD-11.** The capture signal is contributory, never standalone at high confidence on its own: microphone-in-use by a *non-meeting* app (a voice recorder, a game) must not mark the user busy. It raises confidence only for a process already identified as a meeting client or a browser. `app.meeting_provider_capture_enabled` disables it entirely.

#### 7.5.4 Engine parity

**Requirement MD-12.** `MeetingDetectionEngine` reproduces: 3.0 s default poll, `High` default threshold, highest-confidence-wins aggregation, debounce on `(confidence, provider)`, `ClearAndSuppressFor(TimeSpan)`, `SetProvider(provider, enabled)`, and the log events `meeting.detection.engine.started/stopped`, `meeting.detector.polled`, `meeting.status.changed`, `meeting.detection.suppressed`, `meeting.detection.suppression_ended`, `meeting.provider.enabled.changed`.

**Requirement MD-13.** The engine's poll loop uses a `PeriodicTimer` and runs detector `Detect()` calls on the thread pool; only the aggregation and the callback run on the dispatcher.

### 7.6 System presence monitor

**Requirement SP-1.** Away is raised by any of:

| Trigger | API |
|---|---|
| Workstation lock | `SystemEvents.SessionSwitch` with `SessionSwitchReason.SessionLock` |
| Session disconnect / fast user switch / RDP disconnect | `SessionSwitchReason.ConsoleDisconnect`, `RemoteDisconnect`, `SessionLogoff` |
| System suspend | `SystemEvents.PowerModeChanged` with `PowerModes.Suspend` |
| Display turned off | `WM_POWERBROADCAST` / `PBT_POWERSETTINGCHANGE` for `GUID_CONSOLE_DISPLAY_STATE` with data `0` |

**Requirement SP-2.** Return is raised by `SessionUnlock`, `ConsoleConnect`, `RemoteConnect`, `SessionLogon`, `PowerModes.Resume`, and `GUID_CONSOLE_DISPLAY_STATE` data `1` (on) or `2` (dimmed → treated as on).

**Requirement SP-3.** The same de-duplication as S-3: an `_isAwake` flag means the *first* away trigger fires the callback and subsequent ones are ignored until a return. Necessary because lock + display-off + suspend commonly fire within a second of each other.

**Requirement SP-4.** `GUID_CONSOLE_DISPLAY_STATE` requires a window handle, so `PowerNotificationWindow` is a message-only window (`HWND_MESSAGE` parent) created on the UI thread; it registers via `RegisterPowerSettingNotification` and unregisters on dispose. It is also the natural host for the hotkey messages ([§7.7](#77-global-hotkeys)) — one message window serves both.

**Requirement SP-5.** `SimulateAway()` / `SimulateReturn()` are exposed for the debug menu, matching S-4.

**Requirement SP-6.** `SystemEvents` handlers arrive on a dedicated system thread; every handler immediately marshals to the dispatcher. Failing to do so is a latent race against the state machine's thread affinity.

**Requirement SP-7.** Log events match: `system.presence.monitor.started`, `system.presence.monitor.stopped`, `system.presence.away [trigger=…]`, `system.presence.returned [trigger=…]`. Trigger strings are the Windows reason names (`SessionLock`, `PowerModes.Suspend`, `ConsoleDisplayState.Off`, `simulated`).

### 7.7 Global hotkeys

#### 7.7.1 Default bindings

macOS uses `Ctrl+Cmd+<n>`. The Windows analogue of Cmd is Win, but `Win+1`–`Win+9` are reserved by the shell for taskbar activation and `Ctrl+Win+<arrow>` for virtual desktops. **`Ctrl+Alt+<n>` is the default** — unreserved, unlikely to collide, and ergonomically equivalent.

| Action | macOS | Windows default | Modifier mask | VK |
|---|---|---|---|---|
| Mark as Available | ⌃⌘1 | `Ctrl+Alt+1` | `MOD_CONTROL\|MOD_ALT` | `0x31` |
| Mark as Tentative | ⌃⌘2 | `Ctrl+Alt+2` | `MOD_CONTROL\|MOD_ALT` | `0x32` |
| Mark as Busy | ⌃⌘3 | `Ctrl+Alt+3` | `MOD_CONTROL\|MOD_ALT` | `0x33` |
| Resume Calendar Control | ⌃⌘4 | `Ctrl+Alt+4` | `MOD_CONTROL\|MOD_ALT` | `0x34` |
| Turn Off | ⌃⌘5 | `Ctrl+Alt+5` | `MOD_CONTROL\|MOD_ALT` | `0x35` |
| Mark as Away | ⌃⌘6 | `Ctrl+Alt+6` | `MOD_CONTROL\|MOD_ALT` | `0x36` |

**Requirement HK-1.** All six are registered with `RegisterHotKey(hWnd, id, fsModifiers | MOD_NOREPEAT, vk)` on the message window. `MOD_NOREPEAT` prevents auto-repeat storms — the macOS monitor has the same effective behaviour because a key-down repeat re-applies the same state as a no-op, but being explicit is cheaper.

**Requirement HK-2.** `RegisterHotKey` returns `false` when the combination is already owned by another process. The agent then:
1. logs `hotkey.register.failed [action=… combo=… error=1409]`,
2. continues registering the remaining hotkeys (a single conflict must not disable the rest),
3. shows a one-time tray balloon: *"BusyLight could not register Ctrl+Alt+3 — another app is using it. Open Settings → Hotkeys to choose a different key."*,
4. marks the action as unbound in the Hotkeys dialog.

This is materially better than macOS, where a failed monitor registration is silent.

**Requirement HK-3.** `WM_HOTKEY` arrives on the message window's thread — already the UI thread — so the handler dispatches `StateEvent.HotkeyPressed` directly, no marshalling.

**Requirement HK-4.** Semantics match H-3 and H-4 exactly:
- Available / Tentative / Busy / Away → `HotkeyPressed(state)` → identical code path to a manual override, including the expiry timer.
- Resume Calendar → `ResumeAuto` **plus** `meetingEngine.ClearAndSuppressFor(5 s)` **plus** an immediate `ScanNowAsync()`.
- Turn Off → `TurnOff`.

**Requirement HK-5.** `UpdateBindings(...)` unregisters all ids and re-registers; the message window and its `hWnd` are stable across rebinding.

**Requirement HK-6.** The Hotkeys dialog (`HotkeyPreferencesWindow`) mirrors `HotkeyPreferencesController.swift`: one row per action, click-to-capture using a keyboard hook scoped to the dialog, live conflict checking (attempt a temporary `RegisterHotKey`, report failure before saving), a Reset-to-Defaults button, Save/Cancel.

**Requirement HK-7.** Elevated (admin) windows swallow low-integrity input, so a hotkey pressed while an elevated window has focus will not reach a non-elevated BusyLight. This matches the macOS secure-input limitation. Document it in `docs/hotkey.md`; do not attempt to work around it by requesting elevation.

**Requirement HK-8.** Log events: `hotkey.manager.initialized`, `hotkey.monitor.started`, `hotkey.monitor.stopped`, `hotkey.pressed [keyCode=… targetState=…]`, `hotkey.resume_calendar`, `hotkey.turn_off`, `hotkey.bindings.updated`, `hotkey.register.failed`.

### 7.8 Office hours scheduler

**Requirement OH-1.** `OfficeHoursConfiguration` is a literal port, including:
- minute-of-day normalisation clamped to `[0, 1439]`,
- weekday set filtered to `1–7` with **Sunday = 1** (the `Calendar.component(.weekday)` convention). `DayOfWeek.Sunday` is `0` in .NET, so the converter is `((int)dt.DayOfWeek) + 1`. Getting this wrong shifts the entire schedule by one day; it is called out explicitly and has a dedicated test.
- `start == end` → all day,
- `start < end` → `[start, end)` on an active weekday,
- `start > end` → wraps midnight; the post-midnight tail belongs to the **previous** weekday,
- `isEnabled == false` → `Contains()` always `true`.

**Requirement OH-2.** `ScheduleDescription` and `ParseSchedule` produce/accept the same `Mon-Fri 09:00-17:00` grammar, including comma lists and ranges (`Mon-Wed,Fri`), and the `Mon-Fri` / `Sun-Sat` special-cased descriptions.

**Requirement OH-3.** Evaluation uses **local time**. The scheduler subscribes to `SystemEvents.TimeChanged` and `SystemEvents.PowerModeChanged(Resume)` and re-evaluates immediately, so waking a laptop in a different time zone does not leave the light stuck for up to 60 s.

**Requirement OH-4.** A 60 s `PeriodicTimer` posts `OfficeHoursChanged(officeHours.Contains(DateTimeOffset.Now))` to the state machine, matching O-2. The settings dialog also triggers an immediate evaluation on save.

### 7.9 WLED network layer

#### 7.9.1 HTTP client

**Requirement NW-1.** `WledHttpClient` implements `IWledHttpClient` with `PostStateAsync` and `GetInfoAsync`. It uses one shared `HttpClient` over a `SocketsHttpHandler` configured as:

```csharp
new SocketsHttpHandler
{
    UseProxy = false,                                        // ≡ preferNoProxies
    Proxy = null,
    AllowAutoRedirect = false,
    UseCookies = false,
    ConnectTimeout = TimeSpan.FromMilliseconds(timeoutMs),
    PooledConnectionLifetime = TimeSpan.FromMinutes(2),
    PooledConnectionIdleTimeout = TimeSpan.FromSeconds(20),
    MaxConnectionsPerServer = 4,
    EnableMultipleHttp2Connections = false
};
```

Per-request deadline via `CancellationTokenSource(timeoutMs)`. `DefaultRequestVersion = HttpVersion.Version11`.

This replaces the hand-rolled `NWConnection` HTTP/1.1 implementation including the chunked-transfer decoder — `HttpClient` handles `Content-Length` and `Transfer-Encoding: chunked` natively, satisfying N-21 for free.

**Requirement NW-2.** Timeout floor and default are 2500 ms, identical to `AppConfiguration.normalizedWledHttpTimeout`. The probe/health client is constructed with `maxRetries: 1`, the state client with `maxRetries: 3`, mirroring `NetworkClient.init`.

**Requirement NW-3.** Retry policy is a literal port of `executeWithRetry`:
- delays `100 ms`, `200 ms`, `400 ms` (`100 * 2^(attempt-1)`),
- max 3 attempts,
- **no retry** when the failure is an HTTP status error (4xx/5xx) — only on transport/timeout failures,
- logs `http.request.retry [url method attempt next_delay_ms error]` and `http.request.failed.max_retries`.

**Requirement NW-4.** Success logs match byte for byte: `http.post.state.success [address port preset latency_ms]`, `http.get.info.success [address port name version latency_ms]`.

**Requirement NW-5.** Error taxonomy mirrors `NetworkError`: `Timeout`, `DeviceUnavailable`, `InvalidResponse(details)`, `HttpError(statusCode, message)`, `JsonParsingFailed(inner)`, `InvalidUrl`, `NoData` — as a `WledNetworkException` hierarchy with the same `Message` texts.

**Requirement NW-6.** JSON contracts:
```csharp
public sealed record WledStateRequest([property: JsonPropertyName("ps")] int PresetId,
                                      [property: JsonPropertyName("v")]  bool IncludeResponse = true);
public sealed record WledStateResponse(bool On, int Bri, int Ps);
public sealed record WledInfoResponse(string Ver, string Name, int Uptime, string? Ip, string Mac);
```
Source-generated `JsonSerializerContext` so the client is trim/AOT-safe.

#### 7.9.2 Discovery

**Requirement NW-7.** `MdnsDeviceDiscovery` browses **both** `_wled._tcp.local` (WLED's own advertisement) and `_http._tcp.local` (what the macOS agent browses), deduplicating by resolved address. Resolve each instance to an IPv4 address, then verify with `GET /json/info` and the same `ver.Contains("0.") || ver.ToLower().Contains("wled")` test (N-7).

**Requirement NW-8.** Discovery timeout is 5 s, matching `NetworkClient.performConnect`. Log events `discovery.started`, `discovery.service.found`, `discovery.service.resolved`, `discovery.wled.verified`, `discovery.not_wled`, `discovery.verification_failed`, `discovery.completed`.

**Requirement NW-9.** mDNS needs to receive UDP on port 5353. Windows Firewall blocks unsolicited inbound UDP by default, so:
- the MSIX declares the `privateNetworkClientServer` capability;
- the installer (and `packaging/firewall/BusyLight-Firewall.ps1`) adds an inbound allow rule for the agent executable on UDP 5353, Private + Domain profiles only;
- if the rule is missing, discovery degrades to the subnet scan rather than failing. Log `discovery.mdns.unavailable` and continue.

**Requirement NW-10.** `LocalSubnetScanner` is a literal port of `LocalNetworkScanner.swift`:
- enumerate interfaces via `NetworkInterface.GetAllNetworkInterfaces()`, keep `OperationalStatus.Up`, skip `Loopback` and `Tunnel`,
- take IPv4 unicast addresses in RFC 1918 ranges (`10/8`, `172.16/12`, `192.168/16`),
- priority addresses first, then `x.y.z.1` … `x.y.z.254` for each interface's /24, excluding the host's own addresses,
- 64-way concurrency (`SemaphoreSlim(64)` or `Parallel.ForEachAsync` with `MaxDegreeOfParallelism = 64`),
- a 1000 ms per-probe timeout with `maxRetries: 1`,
- an overall timeout checked between batches,
- deduplicate by MAC or address,
- log `discovery.scan.started [local_addresses priority_addresses candidate_count port]`, `discovery.scan.wled.verified`, `discovery.scan.completed [devices_found duration_ms]`.

**Requirement NW-11.** The scanner respects the interface prefix length where it is not /24 but still scans only the /24 containing the host address, exactly as the Swift version does. Deviating here would change scan duration and is out of scope.

#### 7.9.3 Client orchestration

**Requirement NW-12.** `WledClient` is a literal port of `NetworkClient.swift`, preserving:

- `ConnectAsync()` join semantics — a concurrent call awaits the in-flight connect instead of starting a second one (`network_client.connect.joined`),
- the three-stage discovery order N-6,
- write-back of discovered addresses to configuration (N-9),
- `hasSeenOnlineDevice` / `didReconnectAfterLoss` logic that clears `lastPresetSent` and raises `OnDeviceReconnected` (N-15),
- parallel broadcast with per-device dedup (N-10, N-11),
- `WledStateSendResult(state, deliveredCount, totalCount)` and `DidDeliverToEveryDevice` (N-12),
- empty-device-list recovery with a forced rediscovery and one retry (N-13),
- health monitoring at `wledHealthCheckInterval` with an immediate first check (N-14),
- 5 s rate-limited background rediscovery when no devices are known (N-16),
- `ApplyDeviceHostOverrideAsync` teardown/reconnect sequence (N-18),
- `HandleNetworkPathAvailableAsync` (N-17), driven by `NetworkChange.NetworkAddressChanged` + `NetworkChange.NetworkAvailabilityChanged`,
- all `network_client.*` log events from [Appendix A](#appendix-a--event-name-catalogue).

**Requirement NW-13.** `NetworkChange` events fire on a thread-pool thread and can arrive in bursts (one per interface per change). Coalesce with a 1 s trailing debounce before calling `HandleNetworkPathAvailableAsync`, then marshal to the dispatcher.

**Requirement NW-14.** Device port is pinned to 80 (X-3).

### 7.10 Tray UI

#### 7.10.1 Icon

macOS renders the state as a coloured emoji in the status-bar button title. The Windows tray takes an `HICON`, so the state is expressed by swapping icons.

**Requirement UI-1.** Ship 6 states × 2 themes = 12 ICO files, each containing 16×16, 20×20, 24×24, 32×32, 40×40, and 48×48 frames (covering 100–300% DPI scaling).

| State | Glyph | Light-theme fill | Dark-theme fill |
|---|---|---|---|
| Available | filled circle | `#2E9E4F` | `#4ADE80` |
| Busy | filled circle | `#C62828` | `#F87171` |
| Tentative | filled circle | `#E07C00` | `#FBBF24` |
| Away | hollow circle | `#6B7280` | `#D1D5DB` |
| Unknown | filled circle | `#111827` | `#9CA3AF` |
| Off | filled rounded square | `#374151` | `#6B7280` |

**Requirement UI-2.** Theme selection follows `app.tray_icon_theme`; in `auto`, read `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize\SystemUsesLightTheme` and re-evaluate on `WM_SETTINGCHANGE` with `lParam == "ImmersiveColorSet"`. Note the tray uses `SystemUsesLightTheme`, not `AppsUseLightTheme`.

**Requirement UI-3.** Shape differs per state as well as colour, so the tray remains readable for colour-vision-deficient users and in monochrome high-contrast themes. High-contrast mode (`SystemParameters.HighContrast`) forces the monochrome glyph set.

**Requirement UI-4.** The tooltip carries what macOS puts in the button plus the status line, e.g. `BusyLight — Busy (Zoom Meeting)`. Truncate to 127 characters. Update on every state change.

**Requirement UI-5.** Handle `TaskbarCreated` (the registered window message broadcast when Explorer restarts) by re-adding the notify icon. Without this, the tray icon vanishes permanently after an Explorer crash — a common and confusing failure.

#### 7.10.2 Menu

**Requirement UI-6.** The context menu reproduces U-3 exactly, in order:

```
Status: Available (Calendar)                 [disabled label]
Devices: Online (1 online)                   [disabled label]
Signal: Sent Available (1/1)                 [disabled label]
─────────────────────────────────────────
Control                                      ▸
   ✓ Automatic Calendar Control   Ctrl+Alt+4
     Manual Override
     Turn Off BusyLight
Manual Status                                ▸   [hidden unless mode == manual]
   ✓ Set Available
     Set Tentative
     Set Busy
─────────────────────────────────────────
Calendar: Active                             [disabled label]
─────────────────────────────────────────
Override Timeout                             ▸   [hidden unless mode == manual]
     15 minutes
   ✓ 30 minutes
     60 minutes
     2 hours
     4 hours
     Never
─────────────────────────────────────────    [DEBUG builds only]
🐛 Debug                                      ▸
     Scan Calendar Now
     ─────────
     Hotkey Debug Info
     ─────────
     Simulate Screen Lock (Away)
     Simulate Screen Unlock (Return)
     ─────────
     Simulate Manual Override                ▸
        Override → Available
        Override → Busy
        Override → Tentative
        Override → Away
        ─────────
        Clear Override (Resume Calendar)
─────────────────────────────────────────
Calendars                                    ▸
   ✓ All Calendars
     ─────────
   ✓ Work (Outlook)
   ✓ Personal (Google)
Settings                                     ▸
     Devices                                 ▸
        Device: Online                       [disabled label, tooltip lists devices]
        Connected to: 192.168.1.42           [disabled label]
        Last sync: 17/09/2026 14:22          [disabled label]
        ─────────
        Configure Devices...
     ─────────
     Office Hours...
     Hotkeys...                              [Windows addition — see below]
     Preferences…                            Ctrl+,
Quit BusyLight                               Ctrl+Q
```

**Requirement UI-7.** The `Status:` qualifier strings match U-4 exactly, including `(Calendar)`, `(Zoom Meeting)`, `(Teams Meeting)`, `(Google Meet)`, `(Meeting)`, `(System)`, `(Office Hours)`, `(Automatic)`, `(Manual)`, `(Manual Override)`, `(Disabled)`.

**Requirement UI-8.** `Signal:` transitions `Sending X...` → `Sent X (n/m)` / `Failed X (n/m)` on every send, matching U-6. The `Sending` label is set synchronously when the state changes, before the HTTP call, so the user always sees the attempt.

**Requirement UI-9.** Item visibility is mode-driven and identical to macOS: `Manual Status` and `Override Timeout` are hidden outside manual mode; `Turn Off BusyLight` is hidden in off mode.

**Requirement UI-10.** `Hotkeys...` is a Windows addition to `Settings` because Windows hotkey registration can fail and needs a first-class remediation path ([§7.7](#77-global-hotkeys)). macOS has an equivalent controller (`HotkeyPreferencesController`) that is simply not wired into its menu; wiring it on macOS is optional follow-up, not part of this spec.

**Requirement UI-11.** Left-click on the tray icon opens the same context menu (Windows convention is that left-click opens a primary UI, but this agent has no primary window). Double-click opens Preferences.

**Requirement UI-12.** The device tooltip lists `● <name> (<address>:<port>)` per online device, matching U-15, capped at the 127-character tooltip limit with an `…and N more` suffix.

**Requirement UI-13.** Menu labels are set from a single `TrayViewModel` updated on the dispatcher. `ContextMenuStrip` items are created once at startup and mutated, never rebuilt, except for the Calendars submenu which rebuilds on `RefreshCalendarMenu()`.

### 7.11 Settings UI

**Requirement UI-14 — Preferences.** WPF dialog reproducing U-13:
- `WLED Host (IPv4)` text box, validated by `NetworkAddressValidator.NormalizeIPv4Address` (N-20). Invalid → modal *"Invalid Device Address — Please enter a valid IPv4 address (example: 192.168.1.42)."*
- `Preset: Available / Tentative / Busy / Away` numeric boxes, each validated to 1–250. Invalid → *"Invalid Preset ID — Preset IDs must be numbers between 1 and 250."*
- An embedded Office Hours editor (same control as the standalone dialog).
- Save / Cancel. Save applies the host override through `ApplyDeviceHostOverrideAsync`, persists presets, persists office hours, and triggers an office-hours re-evaluation.

The macOS dialog does not expose the Unknown and Off presets; the Windows dialog matches that omission for parity. Both remain editable in `config.json`.

**Requirement UI-15 — Office Hours.** Reproduces U-14: `On` checkbox; seven day toggle buttons labelled `M T W T F S S` mapped to weekdays `2,3,4,5,6,7,1`; `from` and `to` drop-downs with 48 half-hour entries formatted `h:mm tt`; `All day` checkbox that, when checked, saves `start = end = 0`. An empty weekday selection is rejected with *"Invalid Office Hours — Select at least one weekday."*

**Requirement UI-16 — Calendars.** The Calendars submenu behaves exactly as U-11: `All Calendars` maps to an empty `enabledCalendarTitles`; toggling individual calendars edits the list; selecting *every* calendar collapses back to the empty "all" representation. Entries are labelled `<title> (<account>)`.

**Requirement UI-17.** Dialogs are shown with `ShowDialog()` from the dispatcher, are `Topmost` on first show, and set `ShowInTaskbar = false` to preserve the tray-only character of the app (U-1).

**Requirement UI-18.** All dialogs are keyboard-navigable, expose `AutomationProperties.Name` on every control, and respect the system DPI (`PerMonitorV2` in `app.manifest`).

### 7.12 Logging and diagnostics

**Requirement LOG-1.** Eight logger categories matching X-4: `BusyLight.Lifecycle`, `BusyLight.Ui`, `BusyLight.Configuration`, `BusyLight.Device`, `BusyLight.Error`, `BusyLight.Calendar`, `BusyLight.Network`, `BusyLight.Meeting`.

**Requirement LOG-2.** `BusyLightLog.LogEvent(string eventName, params (string Key, string Value)[] details)` renders exactly `event [k=v k=v]`, matching X-5, so log lines are directly comparable with macOS `log stream` output. `LogError(Exception, string context)` renders `context: message`.

**Requirement LOG-3.** Sinks:
1. Rolling file at `%LOCALAPPDATA%\BusyLight\logs\busylight-yyyyMMdd.log`, 7-day retention, 10 MB cap per file, UTF-8, one line per event with an ISO-8601 timestamp and the category.
2. `EventSource` named `BusyLight-Agent` for ETW, so PerfView/`dotnet-trace` can capture without the file sink.
3. Console sink in Debug builds only.

**Requirement LOG-4.** Level from `app.log_level`, default `Information`. Event names never change with level — only verbosity of additional detail.

**Requirement LOG-5.** `debug.ps1` reproduces `debug.sh`: build if needed, launch the agent, then `Get-Content -Wait -Tail 50` the current log file, with `Ctrl+C` stopping the agent.

**Requirement LOG-6.** A `Settings → Open Log Folder` item (Windows addition, low cost, high support value) opens the log directory in Explorer.

**Requirement LOG-7.** No PII in logs: calendar event titles are already logged by the macOS agent under `calendar.event.found` and that parity is kept, but the log directory is user-local and the file sink is off by default at `Trace`. Meeting detection logs window titles only at `Debug` level and above (the macOS version logs them at info; the Windows version demotes them, because window titles are more sensitive than the other fields and the macOS behaviour is a diagnostic leftover).

### 7.13 Launch on startup

**Requirement ST-1.** Unpackaged: set/remove `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` value `BusyLight` = `"<exe path>" --startup`.

**Requirement ST-2.** Packaged (MSIX): declare a `windows.startupTask` extension with `TaskId = BusyLightStartupTask` and toggle it via `StartupTask.GetAsync(...)` → `RequestEnableAsync()` / `Disable()`. The OS may report `StartupTaskState.DisabledByUser`; in that case the checkbox reflects reality and a tooltip explains that the user disabled it in Task Manager → Startup apps.

**Requirement ST-3.** `--startup` suppresses any first-run window and delays discovery by 3 s to avoid competing with shell startup.

**Requirement ST-4.** `IStartupRegistrar` abstracts (1) and (2); the implementation is selected by checking package identity via `GetCurrentPackageFullName`.

### 7.14 Application lifecycle

`AgentHost` is the literal counterpart of `BusyLightApp.swift`. Startup sequence, in order:

1. Single-instance guard: a named mutex `Global\BusyLight.Agent.SingleInstance`. A second instance surfaces the existing tray icon (balloon tip) and exits with code 0.
2. Load configuration; on failure, load defaults and log.
3. Create the message window (power + hotkeys).
4. Create `TrayUiController`, show the icon with state `Available` from persisted config.
5. Create `PresenceStateMachine` with `manualOverrideTimeoutMinutes` and `stateStabilizationSeconds` from config.
6. Wire `OnStateChanged` → update tray, set `Signal: Sending …`, update calendar label for `calendar`/`startup` sources when the state is not `off`, then `await wledClient.SendStateAsync(state)` and set `Signal: Sent/Failed`.
7. Wire `OnModeChanged` → tray mode display.
8. Create the calendar provider chain and `CalendarEngine`; wire `OnAvailabilityChange` → `CalendarUpdated`; wire `OnRequestCalendarSync` → `ScanNowAsync`.
9. Wire tray callbacks: resume, manual override, turn off, timeout changed, device address configured, office hours changed, calendar list get/update.
10. Start the calendar engine (async, non-blocking); on completion set the calendar label to `Active` / `Permission required` and refresh the Calendars submenu.
11. Start `SystemPresenceMonitor`; wire away/returned.
12. Kick an immediate `ScanNowAsync`.
13. Start `HotkeyManager`; wire the six actions.
14. Start `MeetingDetectionEngine` if enabled, configured from settings.
15. Create `WledClient`; wire `OnDeviceStatusChanged` and `OnDeviceReconnected` (skip the re-send when the state is `off`).
16. `ConnectAsync()` → `StartHealthMonitoring()` → start the network-change monitor.
17. `HandleEvent(StartupInitialize)`; start the office-hours 60 s loop.

**Requirement LC-1.** Step 6's ordering is load-bearing: the `Sending` label must be set before the await so the user sees feedback for slow or failing devices.

**Requirement LC-2.** X-7 (the deferred permission prompt) has a Windows analogue: the calendar consent prompt in step 10 runs **after** the tray is visible and **concurrently with** steps 11–17, so device discovery and the first state send are never blocked by a modal consent dialog.

**Requirement LC-3.** Shutdown (`Quit`, `WM_ENDSESSION`, `WM_QUERYENDSESSION`, `SystemEvents.SessionEnding`, Ctrl+C in console builds) performs X-6: stop the system monitor, unregister hotkeys, stop the calendar engine, stop the meeting engine, cancel the office-hours loop, dispose the network monitor, stop health monitoring, disconnect, flush configuration, remove the tray icon, dispose the message window. A 3 s watchdog force-exits if a component hangs.

**Requirement LC-4.** Unhandled exceptions (`AppDomain.CurrentDomain.UnhandledException`, `TaskScheduler.UnobservedTaskException`, `Application.ThreadException`) are logged at error level with a full stack trace and do **not** terminate the agent unless the exception is on the UI thread and the app is already shutting down. A presence agent that dies silently is worse than one that degrades.

---

## 8. Concurrency and Threading Model

macOS uses `@MainActor` isolation for the state machine, configuration, calendar engine, meeting engine, system monitor, hotkey manager, network client, and UI. The Windows agent reproduces this with a single UI thread.

**Requirement TH-1.** `Program.Main` is `[STAThread]`. It installs a `WindowsFormsSynchronizationContext`, creates the message window and tray on that thread, and runs `Application.Run()`.

**Requirement TH-2.** `IUiDispatcher` is the `@MainActor` analogue:

```csharp
public interface IUiDispatcher
{
    bool IsOnUiThread { get; }
    void Post(Action action);                 // fire-and-forget, ordered
    Task InvokeAsync(Func<Task> action);      // awaitable
    TaskScheduler Scheduler { get; }
}
```

**Requirement TH-3.** Every type that is `@MainActor` in Swift is documented as "UI-thread affine" in C# and asserts affinity in Debug via `Debug.Assert(_dispatcher.IsOnUiThread)` at each public entry point.

**Requirement TH-4.** I/O (HTTP, mDNS, subnet scan, registry reads, COM calls, file writes) runs off the UI thread; results are posted back. `ConfigureAwait(false)` is used in `Core` and `Platform` library code; the `Agent` layer relies on the captured context.

**Requirement TH-5.** Swift `withTaskGroup` becomes `Task.WhenAll` over a bounded `SemaphoreSlim`, or `Parallel.ForEachAsync` with an explicit `MaxDegreeOfParallelism`. Concurrency limits match the Swift values: unbounded for the device broadcast (device counts are tiny), 64 for the subnet scan.

**Requirement TH-6.** Every long-lived loop (health check, meeting poll, office hours) uses `PeriodicTimer` + a linked `CancellationToken` and is awaited during shutdown.

**Requirement TH-7.** The Outlook COM provider owns a dedicated STA thread with its own message pump; all COM interaction is marshalled onto it.

---

## 9. Permissions and Consent Model

| Permission | macOS | Windows 11 |
|---|---|---|
| Read calendar | TCC prompt, `NSCalendarsFullAccessUsageDescription`, revocable in System Settings → Privacy & Security → Calendars | Windows consent prompt via `AppointmentManager.RequestStoreAsync`, revocable in Settings → Privacy & security → Calendar. **Requires package identity** (MSIX). The Outlook COM and ICS providers need no consent. |
| Read window titles | Accessibility TCC grant; the user must add the app manually and relaunch | **None required.** `EnumWindows`/`GetWindowText` are unrestricted. |
| Global hotkeys | Accessibility TCC grant | **None required.** `RegisterHotKey` is unrestricted. |
| Local network | `NSLocalNetworkUsageDescription` TCC prompt + `NSBonjourServices` + `NSAllowsLocalNetworking` | No consent prompt. Outbound HTTP is allowed by default. Inbound mDNS needs a firewall rule ([§7.9.2](#792-discovery)). |
| Camera/mic usage *reading* | n/a | None — the consent-store registry is readable by the user without a capability. BusyLight never opens a capture device. |
| Run at login | n/a (declared, unimplemented) | None for `HKCU\...\Run`; MSIX `StartupTask` needs a user confirmation the first time. |

**Requirement PERM-1.** The Windows first-run experience is materially simpler than macOS. There is no equivalent of the macOS "remove the old Accessibility registration, rebuild, relaunch" dance in `README.md`, because Windows hotkeys and window enumeration are not code-signature-bound. The Windows section of the README must say so explicitly rather than mirroring the macOS instructions.

**Requirement PERM-2.** The MSIX manifest declares exactly:
```xml
<Capabilities>
  <uap:Capability Name="appointments" />
  <Capability Name="privateNetworkClientServer" />
  <Capability Name="internetClient" />   <!-- only if Graph/ICS is built in -->
  <rescap:Capability Name="runFullTrust" />
</Capabilities>
```
No `microphone`, no `webcam`, no `broadFileSystemAccess`. The capability list is part of the privacy story and is reviewed on every release.

**Requirement PERM-3.** When the `appointments` consent is denied, the tray shows `Calendar: Permission required` and a menu item `Open Calendar Privacy Settings` launching `ms-settings:privacy-calendar`.

---

## 10. Build, Packaging, and Distribution

### 10.1 Build

**Requirement BLD-1.** `windows-agent/build.ps1` mirrors `build.sh`:

```powershell
.\build.ps1                 # Debug build
.\build.ps1 release         # Release build (win-x64 + win-arm64)
.\build.ps1 test            # dotnet test
.\build.ps1 package         # produce MSIX + portable ZIP
.\build.ps1 clean           # remove bin/obj/artifacts
```

**Requirement BLD-2.** Publish profile: `-c Release -r win-x64|win-arm64 --self-contained true -p:PublishReadyToRun=true -p:PublishSingleFile=false`. Self-contained removes the "install .NET" support burden; ReadyToRun cuts cold start. `PublishTrimmed` is **off** — reflection-heavy WinRT projections and `dynamic` COM binding are not trim-safe.

**Requirement BLD-3.** `Directory.Build.props` pins `<Nullable>enable</Nullable>`, `<TreatWarningsAsErrors>true</TreatWarningsAsErrors>`, `<AnalysisLevel>latest-recommended</AnalysisLevel>`, `<LangVersion>12.0</LangVersion>`, and derives `Version`/`FileVersion`/`InformationalVersion` from the tag, mirroring `release.sh stamp_version`.

**Requirement BLD-4.** `app.manifest` declares `PerMonitorV2` DPI awareness, `requestedExecutionLevel level="asInvoker"` (never elevate), and `supportedOS` for Windows 10/11.

### 10.2 Packaging

Two artefacts per release, matching the DMG's role on macOS.

**Requirement PKG-1 — MSIX (primary).** `BusyLight-<version>-x64.msix` and `-arm64.msix`, bundled as `BusyLight-<version>.msixbundle`.
- Required for the `appointments` capability, therefore required for the default calendar provider.
- Declares the `windows.startupTask` extension (ST-2).
- Assets: 44×44, 50×50, 150×150, 310×150, 310×310 tiles plus scale variants, generated from `img/busy-light-icon.png`.
- `Identity Name="dralquinta.BusyLight"`, `Publisher` matching the signing certificate subject exactly, `ProcessorArchitecture` per package.
- `MinVersion="10.0.22000.0"`, `MaxVersionTested="10.0.26100.0"`.

**Requirement PKG-2 — Portable ZIP (secondary).** `BusyLight-<version>-win-x64.zip` containing the self-contained publish output plus `README-windows.txt`. For users who cannot or will not install an MSIX. Calendar support falls back to Outlook COM / ICS because there is no package identity.

**Requirement PKG-3 — winget.** `packaging/winget/dralquinta.BusyLight.yaml` manifest targeting the MSIX, submitted to `microsoft/winget-pkgs` on each release. `winget install dralquinta.BusyLight`.

**Requirement PKG-4 — Signing.** Authenticode via `signtool sign /fd SHA256 /tr http://timestamp.digicert.com /td SHA256`. Sign the executable **and** the MSIX. The MSIX `Publisher` string must exactly equal the certificate subject or installation fails with `0x800B0100`.
- With no certificate configured, `build.ps1 package` produces an unsigned MSIX and prints the sideload instructions (`Add-AppxPackage` after trusting a self-signed test certificate) — the analogue of `release.sh --skip-sign`.
- Without an EV certificate, SmartScreen will warn until reputation accrues. Document this in `docs/releasing.md`.

**Requirement PKG-5 — Firewall.** `packaging/firewall/BusyLight-Firewall.ps1` adds the inbound UDP 5353 rule. The MSIX cannot add firewall rules itself, so the agent detects the missing rule, logs `discovery.mdns.unavailable`, and offers a one-click elevated fix from the tray (`Settings → Fix Network Discovery…`) that runs the script via `Start-Process -Verb RunAs`.

### 10.3 Documentation updates

**Requirement DOC-1.** The following files gain Windows content: `README.md` (platform badges, Windows quick start, Windows hotkey table, Windows permissions), `docs/index.md`, `docs/architecture.md` (Windows adapter column), `docs/configuration.md` (config file location and Windows-only keys), `docs/hotkey.md` (Windows bindings, conflicts, elevated-window limitation), `docs/software.md`, `docs/releasing.md` (Windows release flow), `docs/module-testing.md` (Windows execution of the 12 hardware cases).

**Requirement DOC-2.** A new `docs/windows-calendar-providers.md` explains the four providers, how `auto` picks one, the packaged-vs-portable consequence, and troubleshooting for the empty-AppointmentStore case. This is the question Windows users will ask most.

---

## 11. CI/CD

**Requirement CI-1.** `.github/workflows/release.yml` gains a `release-windows` job running on `windows-latest`, parallel to the existing macOS job, both triggered by `v*.*.*` tags.

```yaml
release-windows:
  name: Build and Release Windows MSIX
  runs-on: windows-latest
  permissions:
    contents: write
  steps:
    - uses: actions/checkout@v4
      with: { fetch-depth: 0 }
    - uses: actions/setup-dotnet@v4
      with: { dotnet-version: '8.0.x' }
    - name: Restore
      run: dotnet restore windows-agent/BusyLight.sln
    - name: Build
      run: dotnet build windows-agent/BusyLight.sln -c Release --no-restore
    - name: Test
      run: dotnet test windows-agent/BusyLight.sln -c Release --no-build --logger "trx;LogFileName=results.trx"
    - name: Publish x64 and arm64
      run: |
        dotnet publish windows-agent/src/BusyLight.Agent -c Release -r win-x64   --self-contained true -p:PublishReadyToRun=true -o artifacts/win-x64
        dotnet publish windows-agent/src/BusyLight.Agent -c Release -r win-arm64 --self-contained true -p:PublishReadyToRun=true -o artifacts/win-arm64
    - name: Import signing certificate
      if: ${{ secrets.WINDOWS_CERT_PFX_BASE64 != '' }}
      run: # decode PFX to a temp file, import into the machine store
    - name: Package MSIX
      run: .\windows-agent\build.ps1 package -Version ${{ env.VERSION }}
    - name: Sign
      if: ${{ secrets.WINDOWS_CERT_PFX_BASE64 != '' }}
      run: # signtool sign /fd SHA256 /tr <timestamp> /td SHA256 on exe + msix/msixbundle
    - name: Verify package
      run: # Get-AppxPackageManifest validation + Test-AppxPackage-equivalent checks
    - name: Upload artifacts
      uses: actions/upload-artifact@v4
    - name: Attach to release
      run: gh release upload ${{ env.VERSION }} artifacts/*.msixbundle artifacts/*.zip --clobber
```

**Requirement CI-2.** New secrets: `WINDOWS_CERT_PFX_BASE64`, `WINDOWS_CERT_PASSWORD`, `WINDOWS_SIGN_TIMESTAMP_URL`. Absent secrets → unsigned build, matching the existing macOS `--skip-sign` behaviour rather than failing the job.

**Requirement CI-3.** A `ci-windows.yml` PR workflow runs restore + build + test on every push to a PR touching `windows-agent/**`, with no packaging and no signing.

**Requirement CI-4.** The state-machine conformance corpus ([§7.2](#72-state-machine)) is executed by both the macOS and Windows test jobs. A corpus change that breaks either platform fails CI.

**Requirement CI-5.** `scripts/validate-release.sh` gains a Windows counterpart check — the release is not considered complete until both the DMG and the MSIX bundle are attached.

---

## 12. Test Strategy

The macOS agent has 67 tests across 10 files. Windows must meet or exceed that, with the same coverage shape.

### 12.1 Port map

| macOS test file | Windows counterpart | Notes |
|---|---|---|
| `ConfigurationManagerTests` | `ConfigurationStoreTests` | Load/save round-trip, defaults, legacy address migration, invalid-keycode reset, atomic write, corrupt-file recovery |
| `OfficeHoursConfigurationTests` | `OfficeHoursConfigurationTests` | Normalisation, weekday filtering, midnight wrap, all-day, disabled, parse/format round-trip, **plus** the `DayOfWeek` +1 conversion |
| `OfficeHoursPersistenceTests` | `OfficeHoursPersistenceTests` | JSON round-trip |
| `PresenceStateMachineOfficeHoursTests` | `PresenceStateMachineOfficeHoursTests` | Auto-off outside hours, resume only when auto-off, manual mode not gated |
| `HTTPAdapterTests` | `WledHttpClientTests` | Retry/backoff, no-retry on 4xx/5xx, timeout, chunked and content-length responses (via a loopback `HttpListener`) |
| `NetworkAddressValidatorTests` | `NetworkAddressValidatorTests` | Valid/invalid IPv4 forms |
| `NetworkClientDiscoveryTests` | `WledClientDiscoveryTests` | Discovery ordering, manual verification, address write-back, dedup, reconnect detection, rate-limited recovery, send result counting |
| `MeetingDetectionTests` | `MeetingDetectionEngineTests` | Threshold, highest-confidence-wins, debounce, suppression, provider toggles — using fake detectors |
| `StatusMenuControllerTests` | `TrayMenuBuilderTests` | Menu structure, ordering, submenu paths, accelerators, visibility rules, label formatting |
| `InfoPlistNetworkPermissionTests` | `AppxManifestTests` | Asserts the manifest declares exactly the expected capabilities and no more |

### 12.2 Additional Windows tests

- `StateMachineConformanceTests` — runs `docs/specs/state-machine-conformance.json` (CI-4).
- `CalendarAvailabilityResolverTests` — the full priority matrix including `NotSupported` → busy.
- `CalendarProviderMappingTests` — `AppointmentBusyStatus`, `OlBusyStatus`, Graph `showAs`, and ICS `TRANSP` → `CalendarAvailability`.
- `CompositeCalendarProviderTests` — probe order, first-usable-wins, `Unavailable` fallthrough, pinned provider.
- `CalendarEngineTests` — scan interval, immediate scan, store-changed rescan, `ScanNowAsync` forcing a callback, filter fallback when zero calendars match.
- `HotkeyRegistrationTests` — conflict handling with a deliberately pre-registered hotkey; partial registration must not abort the rest.
- `CaptureDeviceMonitorTests` — registry parsing against a synthetic key tree under `HKCU\Software\BusyLightTests`.
- `WindowEnumeratorTests` — enumerate a window created by the test host and assert title/PID association.
- `SubnetScannerCandidateTests` — candidate generation, private-range filter, self-address exclusion, priority ordering.
- `ConfigurationKeyParityTest` — parses `macos-agent/Sources/BusyLightCore/Models/AppConfiguration.swift` and asserts every `CodingKeys` raw value exists in the Windows `AppConfiguration`. This catches key drift mechanically.
- `LogEventNameParityTest` — asserts every event name in [Appendix A](#appendix-a--event-name-catalogue) is emitted by at least one code path.

### 12.3 Integration and manual tests

**Requirement TST-1.** The 12 hardware test cases in `docs/module-testing.md` are executed against a real WLED device from the Windows agent and recorded in that document with a Windows column.

**Requirement TST-2.** Manual matrix, per release:

| Scenario | Expected |
|---|---|
| Lock the workstation (Win+L) | Light → away within 2 s |
| Unlock | Previous state restored |
| Close the lid / display off | Light → away |
| Sleep and resume | Away then restore; office hours re-evaluated immediately |
| Fast user switch away and back | Away then restore |
| RDP disconnect / reconnect | Away then restore |
| Join a Zoom meeting | Busy `(Zoom Meeting)` within one poll interval |
| Leave a Zoom meeting | Returns to calendar state |
| Join a Google Meet in Chrome | Busy `(Google Meet)`; a stale Meet tab with no camera/mic does **not** trigger busy |
| Join a Teams meeting (native and web) | Busy `(Teams Meeting)` |
| Press each of the six hotkeys | Corresponding transition; Resume clears meeting suppression |
| Hotkey while an elevated window is focused | Documented as not delivered |
| Unplug the WLED device, wait, re-plug | Device goes offline, then reconnects and the current state is re-sent |
| Switch Wi-Fi networks | Rediscovery, reconnect, re-send |
| Change the system time zone | Office-hours boundary re-evaluated immediately |
| Cross an office-hours boundary | Light off outside the window; resumes on re-entry |
| Manual override then wait for the timeout | Auto-resume to calendar control |
| Restart Explorer | Tray icon reappears |
| Reboot with launch-on-startup enabled | Agent starts, tray appears, state syncs |

**Requirement TST-3.** Soak test: 72 h continuous run with `dotnet-counters` sampling. Acceptance: no monotonic growth in working set or handle count; `GC Heap Size` stable; thread count stable.

---

## 13. Observability and Support

**Requirement OBS-1.** `Settings → Diagnostics → Copy Diagnostics` copies a redacted bundle to the clipboard: OS build, agent version, architecture, packaged/unpackaged, selected calendar provider, calendar count, device count and addresses, hotkey registration results, mDNS availability, last 100 log lines. Intended to be pasted into a GitHub issue.

**Requirement OBS-2.** Support-facing counters exposed through `EventCounters` on the `BusyLight-Agent` `EventSource`: `state-transitions`, `wled-sends`, `wled-send-failures`, `calendar-scans`, `calendar-scan-failures`, `meeting-polls`, `discovery-runs`.

**Requirement OBS-3.** The tray tooltip is the first-line diagnostic; it must always reflect reality, including the failure cases (`Device: Searching`, `Calendar: Permission required`, `Signal: Failed Busy (0/1)`).

---

## 14. Delivery Plan

Seven phases. Each is independently mergeable and leaves `main` shippable.

### Phase 0 — Spikes (est. 3–5 days)

**Objective:** retire the two unknowns before committing to the plan.

- **Spike A — AppointmentStore.** Build a minimal MSIX-packaged console app; call `AppointmentManager.RequestStoreAsync(AllCalendarsReadOnly)`; enumerate calendars and today's appointments on: (1) a clean Windows 11 box with a Microsoft account, (2) a box with new Outlook and an M365 account, (3) a box with classic Outlook and an Exchange account, (4) a box with a Google account added via Settings → Accounts.
- **Spike B — Sparse package.** Determine whether a sparse package / external-location MSIX can grant the `appointments` capability to the portable build, which would let PKG-2 keep the default provider.

**Exit criteria:** a written answer on which providers are needed for which user population, and whether PKG-2 can use AppointmentStore. If Spike A finds the store empty for the majority population, the default provider order in CAL-1 changes and `docs/windows-calendar-providers.md` is written accordingly. **No other phase is blocked by this.**

### Phase 1 — Core domain (est. 5 days)

Scope: `BusyLight.Core` — presence model, state machine, state transition, office hours, availability resolver, WLED types, IPv4 validator, configuration model, log abstraction. Plus `BusyLight.Core.Tests` and the conformance corpus runner.

**Acceptance:** conformance corpus passes; all `Core`-level ported tests pass; zero platform references in `BusyLight.Core.csproj`; `net8.0` (not `-windows`) builds clean.

### Phase 2 — Networking and hardware (est. 5 days)

Scope: `WledHttpClient`, `MdnsDeviceDiscovery`, `LocalSubnetScanner`, `NetworkPathMonitor`, `WledClient`. Firewall script.

**Acceptance:** a real WLED device is discovered by mDNS on a clean machine; discovered by subnet scan with mDNS blocked; all six presets drive the correct colour; the 12 cases in `docs/module-testing.md` pass; unplug/replug and Wi-Fi-switch recovery verified.

### Phase 3 — Tray UI and settings (est. 6 days)

Scope: `TrayUiController`, `TrayMenuBuilder`, icon assets, Preferences, Office Hours, Hotkeys dialogs, `JsonConfigurationStore`, logging sinks, `AgentHost` wiring for everything built so far.

**Acceptance:** menu structure matches U-3 item for item (asserted by `TrayMenuBuilderTests`); manual overrides drive the light end to end; settings persist across restart; icons correct at 100/150/200/300% DPI in light, dark, and high-contrast themes; the icon survives an Explorer restart.

### Phase 4 — System integration (est. 4 days)

Scope: `SystemPresenceMonitor`, `PowerNotificationWindow`, `HotkeyManager`, `HotkeyWindow`, `StartupRegistrar`, `OfficeHoursScheduler` wiring.

**Acceptance:** every row of the TST-2 system/hotkey matrix passes; a hotkey conflict is reported and recoverable; launch-on-startup works packaged and unpackaged.

### Phase 5 — Meeting detection (est. 5 days)

Scope: `WindowEnumerator`, `ProcessInspector`, `CaptureDeviceMonitor`, the three detectors, engine wiring.

**Acceptance:** Zoom, Teams (native and web), and Google Meet each drive busy within one poll interval; a stale Meet tab does not; leaving a meeting returns to the calendar state; poll cost < 15 ms; the capture signal can be disabled.

### Phase 6 — Calendar (est. 8 days)

Scope: `ICalendarProvider` and the four implementations, `CompositeCalendarProvider`, `CalendarEngine` wiring, Calendars submenu, consent handling.

**Acceptance:** busy/tentative/free events drive the light on at least two provider paths; per-calendar filtering works including the zero-match fallback; consent denial degrades gracefully; store-changed triggers a rescan; `docs/windows-calendar-providers.md` published.

### Phase 7 — Packaging, CI, docs (est. 5 days)

Scope: MSIX manifest and assets, `build.ps1`/`debug.ps1`/`release.ps1`, signing, winget manifest, CI jobs, all documentation updates.

**Acceptance:** a tag produces a signed MSIX bundle and a portable ZIP attached to the GitHub Release; a clean Windows 11 VM installs from the MSIX and reaches a working light in under five minutes with no developer tooling; the soak test (TST-3) passes.

**Total estimate:** ~41 working days of focused effort, sequential. Phases 1–5 have no dependency on Phase 0's outcome and can proceed in parallel with it.

---

## 15. Risk Register

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R1 | `AppointmentStore` is empty for users of the new Outlook client, so the default local-first calendar path yields nothing | **High** | **High** | Phase 0 Spike A quantifies it; the composite provider falls through to Outlook COM and ICS; `docs/windows-calendar-providers.md` documents the fix; the agent stays useful via meeting detection and manual control |
| R2 | The `appointments` capability requires package identity, so the portable ZIP loses the default calendar provider | High | Medium | MSIX is the primary artefact; Spike B evaluates sparse packages; the ZIP is documented as Outlook-COM/ICS only |
| R3 | Outlook COM automation leaks objects or leaves `OUTLOOK.EXE` running | Medium | High | Dedicated STA thread; `Marshal.FinalReleaseComObject` in `finally`; a test that asserts the process count is unchanged after 100 scan cycles |
| R4 | Recurring events are missed by the Outlook provider | Medium | High | `IncludeRecurrences = true` + `Sort("[Start]")` + `Restrict` is mandatory and tested; the AppointmentStore and Graph providers expand recurrences server-side |
| R5 | Windows Firewall blocks mDNS, so discovery silently degrades | High | Low | Subnet scan fallback already covers it; detect and log; offer the one-click elevated firewall fix |
| R6 | Default hotkeys collide with another app | Medium | Medium | `Ctrl+Alt+N` chosen to minimise collisions; partial registration; visible balloon; rebinding UI |
| R7 | Browser window-title heuristics break when a browser changes its title format | Medium | Medium | The capture-device signal is title-independent and covers the regression; patterns live in one file and are unit-tested |
| R8 | SmartScreen warns on the unsigned/low-reputation installer, deterring installs | High | Medium | Sign with Authenticode; pursue an EV certificate; distribute via winget which carries its own trust; document the warning |
| R9 | The two agents' state machines drift apart over time | Medium | High | The shared conformance corpus is executed by both CI jobs (CI-4); a behaviour change requires a corpus change |
| R10 | ARM64 has untested behaviour differences (P/Invoke, ReadyToRun) | Low | Medium | Build and smoke-test `win-arm64` in CI; manual verification on an ARM64 device before the first release that claims support |
| R11 | Scope creep from Windows-only opportunities (Focus Assist, Teams presence API) | Medium | Medium | Explicit non-goal NG4; parked in [§16](#16-open-questions) |
| R12 | Capture-device registry keys are absent or restructured in a future Windows build | Low | Low | Signal is contributory only (MD-11); absence degrades to "unknown", never to a false positive |
| R13 | The 60 s office-hours tick misses a boundary after a laptop resumes in a new time zone | Medium | Low | OH-3 re-evaluates on `TimeChanged` and on resume |

---

## 16. Open Questions

Each needs an answer before the phase that depends on it; none blocks starting work.

| # | Question | Needed by | Default if unanswered |
|---|---|---|---|
| Q1 | Do we pursue a code-signing certificate (OV or EV) for this project, and who holds it? | Phase 7 | Ship unsigned with documented sideload instructions, matching the current macOS `--skip-sign` posture |
| Q2 | Is the Microsoft Graph provider acceptable given the local-first philosophy, even as strictly opt-in? | Phase 6 | Build it behind an opt-in with the explicit consent modal (CAL-GRAPH-1); it is the only path for some M365 users |
| Q3 | Should `launchOnStartup` also be implemented on macOS for symmetry? | Post-v1 | Leave macOS as-is; Windows is parity-plus |
| Q4 | Should the macOS `Hotkeys...` dialog be wired into its menu to match UI-10? | Post-v1 | Leave as-is; note the asymmetry in the docs |
| Q5 | Do we support Windows 10 22H2 on a best-effort basis? | Phase 7 | No — `MinVersion 10.0.22000.0`, per NG1 |
| Q6 | Should the tray expose Unknown/Off preset IDs that the macOS Preferences dialog omits? | Phase 3 | Match macOS; keep them config-file-only |
| Q7 | Future: Windows Focus Assist / Do Not Disturb as a presence input? | Post-v1 | Out of scope (NG4) |
| Q8 | Future: a shared cross-platform conformance harness beyond the state machine (e.g. for the WLED protocol)? | Post-v1 | State machine only for now |

---

## Appendix A — Event Name Catalogue

Every event name below is emitted by the macOS agent and **must** be emitted by the Windows agent from the equivalent code path, with the same detail keys. This is what makes cross-platform log comparison possible.

**Lifecycle:** `Application launched`, `Configuration manager initialized`, `Status menu controller created`, `State machine initialized`, `System presence monitor started`, `Hotkey manager started`, `Meeting detection engine started`, `Network client initialized and connected`, `Application terminating`, `Monitors stopped`, `Configuration saved at shutdown`, `device.host.override.updated`, `override.timeout.updated`, `accessibility.permission.granted`, `accessibility.permission.not_granted`

**Configuration:** `Loading configuration`, `Configuration loaded successfully`, `Saving configuration`, `Configuration saved`, `Migrated legacy deviceNetworkAddress to deviceNetworkAddresses`, `device.address.updated`, `device.addresses.updated`, `resetHotkeysToDefaults`, `hotkey.bindings.saved`

**State machine:** `state.machine.initialized`, `state.transition.success`, `state.transition.blocked`, `state.transition.ignored`, `state.override.set`, `state.override.expired`, `state.mode.changed`, `state.system.off`, `state.system.returned`, `state.calendar.sync.requested`, `state.stabilization.cancelled`

**Calendar:** `calendar.permission.request`, `calendar.permission.result`, `calendar.engine.start`, `calendar.engine.stop`, `calendar.scan.start`, `calendar.scan.execute`, `calendar.scan.result`, `calendar.scan.complete`, `calendar.event.found`, `calendar.state.changed`, `calendar.store.changed`, `calendar.filter.applied`, `calendar.filter.no_matches`, `calendar.filter.validation`, `calendar.filter.updated`, `calendar.diagnostic.no_calendars`, `calendar.diagnostic.visible_calendar`, *(Windows addition)* `calendar.provider.selected`

**Meetings:** `meeting.detection.engine.started`, `meeting.detection.engine.stopped`, `meeting.detector.polled`, `meeting.status.changed`, `meeting.detected`, `meeting.ended`, `meeting.detection.suppressed`, `meeting.detection.suppression_ended`, `meeting.provider.enabled.changed`, `meeting.browser.detector_disabled`, `meeting.browser.window_titles`, `meeting.browser.window_title`, `meeting.browser.match_found`, `meeting.browser.no_match`, `meeting.browser.tab_inactive`, *(Windows additions)* `meeting.capture.in_use`, `meeting.capture.unavailable`; *(macOS-only, no Windows equivalent)* `meeting.browser.no_accessibility`

**Network:** `network_client.initialized`, `network_client.connect.started`, `network_client.connect.joined`, `network_client.connect.discovered`, `network_client.connect.completed`, `network_client.connect.manual.verified`, `network_client.connect.manual.offline`, `network_client.connect.reconnect_detected`, `network_client.refresh`, `network_client.disconnect`, `network_client.device_override.requested`, `network_client.device_auto_configured`, `network_client.send_state`, `network_client.send.success`, `network_client.send.failed`, `network_client.send.skipped.duplicate`, `network_client.send_state.no_online_devices`, `network_client.health.started`, `network_client.health.stopped`, `network_client.health.already_running`, `network_client.health.check`, `network_client.health.ping`, `network_client.health.transition`, `network_client.health.reconnect_detected`, `network_client.path.available`, `network_client.path.resend_requested`, `network_client.rediscover`, `http.post.state.success`, `http.get.info.success`, `http.request.retry`, `http.request.failed.max_retries`, `discovery.started`, `discovery.service.found`, `discovery.service.removed`, `discovery.service.resolved`, `discovery.service.resolve_failed`, `discovery.wled.verified`, `discovery.not_wled`, `discovery.verification_failed`, `discovery.error`, `discovery.completed`, `discovery.scan.started`, `discovery.scan.wled.verified`, `discovery.scan.completed`, *(Windows addition)* `discovery.mdns.unavailable`

**System / hotkeys:** `system.presence.monitor.started`, `system.presence.monitor.stopped`, `system.presence.away`, `system.presence.returned`, `hotkey.manager.initialized`, `hotkey.monitor.starting`, `hotkey.monitor.started`, `hotkey.monitor.stopped`, `hotkey.pressed`, `hotkey.resume_calendar`, `hotkey.turn_off`, `hotkey.bindings.updated`, *(Windows addition)* `hotkey.register.failed`; *(macOS-only)* `hotkey.monitor.failed_to_register`

**UI:** `StatusMenuController initialized`, `Menu structure initialized`, `Menu bar icon displayed`, `Presence state updated`, `Mode display updated`, `Device status updated`, `Device list updated`, `Calendar menu built`, `device.configured.status.updated`, `calendar.control.resume.requested`, `manual.mode.requested`, `manual.override.requested`, `system.off.requested`, `override.timeout.changed`, `Quit requested from menu`

---

## Appendix B — Configuration Key Reference

| Key | Type | Default | macOS | Windows |
|---|---|---|---|---|
| `app.presence_state` | string | `"available"` | ✅ | ✅ |
| `app.device_network_address` | string | `""` | ✅ | ✅ (legacy, migrated) |
| `app.device_network_port` | int | `80` (pinned) | ✅ | ✅ |
| `app.device_network_addresses` | string[] | `[]` | ✅ | ✅ |
| `app.wled_preset_available` | int | `1` | ✅ | ✅ |
| `app.wled_preset_tentative` | int | `2` | ✅ | ✅ |
| `app.wled_preset_busy` | int | `3` | ✅ | ✅ |
| `app.wled_preset_away` | int | `4` | ✅ | ✅ |
| `app.wled_preset_unknown` | int | `5` | ✅ | ✅ |
| `app.wled_preset_off` | int | `6` | ✅ | ✅ |
| `app.wled_http_timeout` | int (ms) | `2500` (floor `2500`) | ✅ | ✅ |
| `app.wled_health_check_interval` | int (s) | `10` | ✅ | ✅ |
| `app.wled_enable_discovery` | bool | `true` | ✅ | ✅ |
| `app.launch_on_startup` | bool | `false` | stored only | **implemented** |
| `app.show_menu_bar_text` | bool | `true` | ✅ | ✅ (tooltip verbosity) |
| `app.manual_override_timeout` | int? (min) | `30` (`-1` = never) | ✅ | ✅ |
| `app.state_stabilization` | int (s) | `0` | ✅ | ✅ |
| `app.office_hours` | object | enabled, Mon–Fri, 540–1020 | ✅ | ✅ |
| `app.hotkey_bindings` | map<string,int> | platform-specific key codes | Carbon codes | VK codes |
| `app.meeting_detection_enabled` | bool | `true` | ✅ | ✅ |
| `app.meeting_provider_zoom_enabled` | bool | `true` | ✅ | ✅ |
| `app.meeting_provider_teams_enabled` | bool | `true` | ✅ | ✅ |
| `app.meeting_provider_browser_enabled` | bool | `true` | ✅ | ✅ |
| `app.meeting_confidence_threshold` | int | `3` (high) | ✅ | ✅ |
| `app.meeting_poll_interval_seconds` | double | `3.0` | ✅ | ✅ |
| `app.enabled_calendar_titles` | string[] | `[]` (= all) | ✅ | ✅ |
| `app.calendar_provider` | string | `"auto"` | — | ✅ |
| `app.calendar_ics_urls` | string[] | `[]` | — | ✅ |
| `app.calendar_graph_account` | string | `""` | — | ✅ |
| `app.meeting_provider_capture_enabled` | bool | `true` | — | ✅ |
| `app.hotkey_modifiers` | uint | `MOD_CONTROL\|MOD_ALT` | — | ✅ |
| `app.tray_icon_theme` | string | `"auto"` | — | ✅ |
| `app.log_level` | string | `"information"` | — | ✅ |
| `schema_version` | int | `1` | — | ✅ |

---

## Appendix C — Win32 API Reference

Everything the port needs from `NativeMethods.cs`, grouped by component.

**Message window (power + hotkeys)**
`CreateWindowEx` (with `HWND_MESSAGE` parent), `DefWindowProc`, `RegisterClassEx`, `DestroyWindow`, `RegisterWindowMessage("TaskbarCreated")`

**Power / display state**
`RegisterPowerSettingNotification`, `UnregisterPowerSettingNotification`, `GUID_CONSOLE_DISPLAY_STATE` (`6fe69556-704a-47a0-8f24-c28d936fda47`), `GUID_SESSION_USER_PRESENCE` (`3c0f4548-c03f-4c4d-b9f2-237ede686376`), `WM_POWERBROADCAST`, `PBT_POWERSETTINGCHANGE`, `PBT_APMSUSPEND`, `PBT_APMRESUMEAUTOMATIC`

**Session state**
`Microsoft.Win32.SystemEvents.SessionSwitch`, `.PowerModeChanged`, `.SessionEnding`, `.TimeChanged`, `.DisplaySettingsChanged` (managed wrappers over `WM_WTSSESSION_CHANGE` / `WM_POWERBROADCAST`)

**Hotkeys**
`RegisterHotKey`, `UnregisterHotKey`, `WM_HOTKEY`, `MOD_ALT` (0x0001), `MOD_CONTROL` (0x0002), `MOD_SHIFT` (0x0004), `MOD_WIN` (0x0008), `MOD_NOREPEAT` (0x4000)

**Window enumeration**
`EnumWindows`, `EnumChildWindows`, `GetWindowText`, `GetWindowTextLength`, `IsWindowVisible`, `GetWindowThreadProcessId`, `GetClassName`

**Tray icon**
`Shell_NotifyIcon` (via `System.Windows.Forms.NotifyIcon`), `NIF_ICON`, `NIF_TIP`, `NIF_MESSAGE`, `NIM_ADD`, `NIM_MODIFY`, `NIM_DELETE`

**Theme**
`WM_SETTINGCHANGE` with `lParam == "ImmersiveColorSet"`, registry `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize\SystemUsesLightTheme`

**Package identity**
`GetCurrentPackageFullName` (returns `APPMODEL_ERROR_NO_PACKAGE` = 15700 when unpackaged)

**Capture-device consent store (registry, not P/Invoke)**
`HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone\{,NonPackaged}\*`, same tree for `webcam`, values `LastUsedTimeStart` / `LastUsedTimeStop`, plus `RegNotifyChangeKeyValue` for change notification

---

*End of specification.*
