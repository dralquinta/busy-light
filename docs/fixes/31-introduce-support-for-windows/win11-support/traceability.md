# Requirements Traceability

## Audit basis

Status below reflects a source review of the current working tree on
2026-09-17. “Implemented in part” means named files exist and contain the
listed behavior; it is not a claim that the full acceptance criterion has
passed testing or Windows CI. No test command was run as part of this audit.

| Acceptance criterion | Current implementation/evidence | Status and remaining gap |
|---|---|---|
| AC-1 Native agent and parity | `windows-agent/BusyLight.sln` contains Core, Platform, Agent, and test projects. Agent is a `WinExe` targeting `net8.0-windows10.0.22621.0`, uses `NotifyIcon`, and has `[STAThread] Program.Main`. | **Implemented in part.** The current menu is only Status/Settings/Quit; there is no `AgentHost`, settings dialogs, tray controller, icon set, device/calendar composition, or demonstrated complete parity/no-taskbar behavior. |
| AC-2 State parity | `StateModel.cs`, `PresenceStateMachine.cs`, `StateTransitionTests.cs`, `StateMachineConformanceTests.cs`, and `docs/specs/state-machine-conformance.json` exist. | **Implemented in part.** The corpus has two cases and is executed only by C# tests. There is no Swift corpus runner. Dispatcher affinity, deterministic timer seams, all required state-machine logs, and complete SM-W1..SM-W5 scenario coverage are absent. |
| AC-3 WLED parity | Core has request/result/device types, basic broadcast, health monitor and discovery order; Platform has `HttpClient`, probe, and subnet-candidate helpers with tests. | **Implemented in part.** No mDNS discovery, complete configured-host/discovery/subnet workflow, identity/write-back, deduplication state mutation, empty-list rediscovery, reconnect resend, network-path monitoring, or real-device manual evidence exists. |
| AC-4 Inputs, UI, persistence, lifecycle | `JsonConfigurationStore`, basic `SystemPresenceMonitor`/mapper, basic tray formatter and tests exist. | **Implemented in part.** Configuration persists only schema version, one address, and busy preset; it lacks full settings, unknown-key preservation, debounce/flush, migration, logging. Calendar, meeting detection, hotkeys, office-hours scheduler, startup registration, lifecycle orchestration, settings UI, and full tray behavior are absent. |
| AC-5 Artifacts and CI | `.github/workflows/ci-windows.yml` restores, builds, and tests the solution on `windows-latest`. | **Implemented in part.** No MSIX/ZIP packaging assets/scripts, Windows release job, signing/fallback, release attachment, ARM64 publish/package verification, or Windows release validation is present. |
| AC-6 Documentation | The implementation-specific tracking documents and source specification exist. | **Not started.** Required updates to `README.md`, `docs/index.md`, `docs/architecture.md`, `docs/configuration.md`, `docs/hotkey.md`, `docs/software.md`, provider guidance, and Windows manual matrix are not present. |
| AC-7 Test coverage | Core, Platform, and Agent test projects exist; current tests cover selected primitives. | **Implemented in part.** The specified test inventory is incomplete and no targeted/full-suite or Windows-CI result is recorded in this traceability file. Platform-only manual cases are not documented. |

## Phase 1 — Core domain

| Requirement family | Current implementation/test evidence | Status and exact gap | Required validation |
|---|---|---|---|
| D-1 / D-2 state transition contract | `StateModel.cs`; `StateTransitionTests.cs` tests selected manual/system/priority guards and off-mode rejections. | **Implemented in part.** Add exhaustive source-for-event and target-state mapping tests, all priority tie cases, and exact raw-value tests. | `dotnet test windows-agent/tests/BusyLight.Core.Tests/BusyLight.Core.Tests.csproj -c Release` |
| SM-W1 state-machine semantics | `PresenceStateMachine.cs`; two corpus sequences plus a manual/calendar test. | **Implemented in part.** Missing test coverage for absolute resume ordering, manual expiry/never, system-away manual block, office-hours re-entry rules, meeting ended handling, no-op calendar behavior, stabilization replacement/cancellation, callback count/order, and turn-off semantics. | Core test command above |
| SM-W2 / SM-W3 timer and thread affinity | Machine uses `CancellationTokenSource` and `Task.Delay`. | **Not complete.** Timers call the machine from a background task; no `IUiDispatcher`, UI-thread assertion, injectable clock/scheduler, or deterministic cancellation test exists. | Deterministic Core timer/dispatcher tests, then Core test command |
| SM-W4 logs | No Core logging abstraction or state-machine event emission was found. | **Not started.** Implement every required state-machine event name and test canonical event/key formatting. | Focused logging/state tests |
| SM-W5 shared corpus | JSON corpus and C# runner exist; corpus is copied to test output through the Core test project. | **Implemented in part.** Expand beyond two cases and add/run an equivalent macOS Swift runner. CI-4 cannot pass until both jobs execute it. | `dotnet test windows-agent/BusyLight.sln -c Release`; `swift test --package-path macos-agent` |
| Presence/configuration model | `AppConfiguration.cs`, `ConfigurationTests.cs` cover port, timeout floor, and two preset defaults. | **Implemented in part.** Only a subset of required settings exists; missing device address array, all preset/config keys, office-hours/hotkey/provider/tray/log settings, serialization key parity, validation, and Windows additions. | Focused configuration tests |
| Office-hours parity | `OfficeHoursConfiguration.cs`; one overnight-window test. | **Implemented in part.** Missing tests and/or behavior for default schedule, all-day, disabled, weekday filtering, parser, description round-trip, empty weekday guard, and full Sunday/.NET `DayOfWeek` coverage. | Focused office-hours tests |
| Calendar availability parity | `CalendarAvailabilityResolver.cs`; NotSupported-to-busy test. | **Implemented in part.** Add resolver precedence tests for busy/unavailable, tentative, free-only, empty list, and `[start,end)` boundary behavior. | Focused availability tests |
| WLED value types and IPv4 | `WledTypes.cs`, `NetworkAddressValidator.cs`; selected request and address tests. | **Implemented in part.** Add all state-preset/default tests and strict IPv4 boundary/normalization cases; current validator test accepts leading-zero octets without documented parity evidence. | Focused Core network tests |
| Core portability | `BusyLight.Core.csproj` targets `net8.0` and source review found no Windows/WinForms/WPF/WinRT/PInvoke imports. | **Implemented in part; build evidence pending.** Must demonstrate clean standalone `net8.0` build. | `dotnet build windows-agent/src/BusyLight.Core/BusyLight.Core.csproj -c Release -f net8.0` |

## Subsequent delivery requirements observed early

| Requirement family | Current evidence | Status and remaining gap |
|---|---|---|
| CFG-1..CFG-5 configuration storage | `JsonConfigurationStore.cs`; storage tests. | **Implemented in part.** Location and basic tmp-to-final write/corrupt rename exist, but the document does not preserve unknown keys, only serializes three fields, has no 250 ms debounce/coalescing or shutdown `Flush`, and lacks logging/migration coverage. |
| N-3..N-5 HTTP transport | `WledHttpClient.cs`, options, and platform tests. | **Implemented in part.** Timeout and retry structure exists, and response status does not retry. Explicit proxy disabling and required 100/200/400 ms max-three-attempt behavior need direct verification; `HttpClient` ownership/disposal semantics also need review. |
| S-1..S-4 system presence | `SystemPresenceMonitor.cs`, mapper, tests. | **Implemented in part.** Session lock/unlock and suspend/resume are wired, but monitor has no stop method or de-duplication and no display-state notification, debug simulation, or lifecycle integration. |
| U-1..U-17 tray/UI | `Program.cs`, `TrayStatusFormatter.cs`, agent tests. | **Implemented in part.** Only a minimal tray icon/menu and formatting exist; the required menu structure, source qualifiers, device/signal/calendar feedback, controls, dialogs, menus, tooltip, debug features, assets, and UI-thread update model remain. |
| CI-1..CI-5 | `ci-windows.yml` exists. | **Implemented in part.** PR CI runs basic solution restore/build/test only. Release workflow has no Windows job; no package/sign/upload/release checks or macOS corpus execution are evidenced. |

## Validation status

Planned commands, not run by this audit:

```powershell
dotnet test windows-agent/tests/BusyLight.Core.Tests/BusyLight.Core.Tests.csproj -c Release
dotnet build windows-agent/src/BusyLight.Core/BusyLight.Core.csproj -c Release -f net8.0
dotnet test windows-agent/BusyLight.sln -c Release
swift test --package-path macos-agent
```

Windows runtime, MSIX, x64/ARM64 publish, and WLED-device evidence must run on
`windows-latest` CI and/or documented Windows 11 manual validation; they cannot
be claimed from this Linux source review.
