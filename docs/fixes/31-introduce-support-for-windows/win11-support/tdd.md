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
