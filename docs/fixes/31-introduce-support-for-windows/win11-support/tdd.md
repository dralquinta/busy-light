# TDD Log — Windows 11 Support

## Initial state

No Windows agent exists. The first Red cycle will establish the Core project
and a failing state-machine conformance test before Core production code is
introduced. Each subsequent behavior-bearing slice is recorded as Red, Green,
and Refactor with the exact command output summary.

## Cycle 1 — Core and transport foundations

### Red

- Added `StateMachineConformanceTests` and
  `docs/specs/state-machine-conformance.json` before Core implementation.
- Added `WledHttpClientOptionsTests` before the Platform transport-options
  implementation; it specifies the 2500 ms timeout floor, disabled proxy, and
  three-attempt retry budget.
- Attempted `dotnet --info`; this Linux authoring host has no `dotnet` SDK
  (`rtk: No such file or directory`). Therefore a compile/test failure could
  not be observed locally. The unimplemented test references were present
  before their respective production types, and Windows CI is required to
  execute the Red and Green commands.

### Green

- Added the first Platform implementation, `WledHttpClientOptions`, satisfying
  the transport-options test contract.
- Added the portable `BusyLight.Core` implementation and focused domain,
  transition, configuration, and conformance tests. Runtime Green evidence is
  pending `windows-latest` because no .NET compiler is installed locally.

### Refactor

- Deferred until the Core and Platform focused suites can run on a .NET SDK.

### Broader validation

- `swift test --package-path macos-agent` is also unavailable on this host
  (`rtk: No such file or directory`). The new Windows CI workflow installs the
  .NET 8 SDK and runs restore, build, and the full solution tests on
  `windows-latest`.

## Cycle 2 — JSON configuration persistence

### Red

- Added `JsonConfigurationStoreTests.SaveThenLoad_PreservesKnownValuesAndWritesSchemaVersion`
  before the store. It requires the `schema_version` root key and persisted
  BusyLight configuration values.
- Runtime execution remains pending Windows CI because this host has no .NET
  SDK.

### Green

- Added atomic same-directory temporary-file replacement and corrupt-document
  recovery in `JsonConfigurationStore`.

### Refactor

- The initial document covers the values exercised by this slice. The complete
  parity key set and unknown-key round-trip are scheduled for the settings
  surface expansion.

## Cycle 3 — Native system-presence monitor compile remediation

### Red

- Windows CI run `35177667095` failed to compile `SystemPresenceMonitor` with
  `CS1069`: the `Microsoft.Win32.SystemEvents` forwarded assembly was not
  referenced by the Platform project.

### Green

- Added the explicit `Microsoft.Win32.SystemEvents` 8.0.0 package reference to
  `BusyLight.Platform`. This supplies the `SessionSwitchEventArgs` and
  `PowerModeChangedEventArgs` types used by the native monitor.

### Refactor

- No behavioral refactor was needed; this is the smallest dependency fix for
  the compile-time framework type forwarder.

### Validation

- Local .NET validation remains unavailable on this Linux host. The next
  pushed Windows CI run is the authoritative build and test check.

## Cycle 4 — Agent-host system presence integration

### Red

- Added `AgentHostTests` before the host exists. The tests specify conversion
  of native away/return signals into `SystemAway`/`SystemReturned`, tray text
  updates, and post-disposal unsubscription.

### Green

- Added `AgentHost` and its `ISystemPresenceSource` boundary. It owns the
  state machine, starts/stops the native source, and maps its boolean signal
  to the matching state events.

### Refactor and validation

- Kept the platform event source behind a tiny interface so the integration is
  deterministic in xUnit. Local execution is unavailable; the next Windows CI
  run will run the new agent tests.

## Cycle 5 — Full known-configuration persistence

### Red

- Added `SaveThenLoad_PreservesAllDocumentedConfigurationValues` before
  expanding the JSON DTO. It exercises device addresses, all WLED controls,
  override/stabilization values, meeting values, startup state, and office
  hours.

### Green

- Expanded the versioned configuration document to round-trip those known
  values while retaining the existing atomic same-directory replacement.

### Refactor and validation

- The DTO remains explicit and stable-keyed rather than serializing the domain
  record directly. Unknown-key preservation and debounced writes remain open
  requirements, recorded in traceability.

## Cycle 6 — Agent host analyzer remediation

### Red

- Windows CI run `35178070818` failed the Release build with `CA1716` because
  `ISystemPresenceSource.Stop()` uses a reserved language keyword as an
  interface member.

### Green

- Renamed the boundary operation and its test fake to `StopMonitoring()`.

### Validation

- The follow-up Windows CI run will validate this analyzer-only correction.

## Cycle 7 — Native global hotkeys

### Red

- Added `GlobalHotkeyManagerTests` before the native implementation. They
  specify the six Ctrl+Alt+1–6 commands, `MOD_NOREPEAT`, independent failed
  registration reporting, `WM_HOTKEY` routing, and cleanup of successful
  registrations.

### Green

- Added a message-only Win32 window and `RegisterHotKey`/`UnregisterHotKey`
  adapter behind an injectable registration interface.

### Refactor and validation

- The registration boundary keeps the Win32 calls testable without a desktop
  session. Local .NET execution is unavailable; Windows CI remains required.
