# Requirements Traceability

| Acceptance criterion | Planned implementation | Planned evidence | Status |
|---|---|---|---|
| AC-1 Native agent and parity | `windows-agent/src/{BusyLight.Core,BusyLight.Platform,BusyLight.Agent}` | solution build; tray/manual matrix | Planned |
| AC-2 State parity | Core `State/**`; `docs/specs/state-machine-conformance.json` | `StateMachineConformanceTests`, transition tests | Planned |
| AC-3 WLED parity | Core network contracts; Platform HTTP/discovery; WLED client | HTTP/discovery tests; WLED manual matrix | Planned |
| AC-4 Inputs, UI, persistence, lifecycle | Core engines; Platform adapters; Agent tray/dialogs | unit/integration tests; Windows manual matrix | Planned |
| AC-5 Artifacts and CI | `windows-agent/packaging/**`, scripts, workflows | Windows CI x64/ARM64 build, test, publish, package | Planned |
| AC-6 Documentation | README and specified `docs/**` files | documentation review | Planned |
| AC-7 Test coverage | `windows-agent/tests/**` | targeted and full `dotnet test` plus CI | Planned |

## Phase 1 detail

| Requirement family | Implementation/test evidence | Validation command | Status |
|---|---|---|---|
| D-1/D-2 and SM-W1..SM-W5 | Core State models/machine; `StateMachineConformanceTests`, `StateTransitionTests` | `dotnet test windows-agent/tests/BusyLight.Core.Tests/BusyLight.Core.Tests.csproj -c Release` | Implemented; CI pending |
| Office-hours parity | Core scheduling model; `CoreDomainTests` | focused Core tests | Implemented; CI pending |
| Calendar availability parity | Core Calendar resolver; `CoreDomainTests` | focused Core tests | Implemented; CI pending |
| WLED model and IPv4 primitives | Core Network types/validator; `CoreDomainTests` | focused Core tests | Implemented; CI pending |
| Transport defaults | Platform `WledHttpClientOptions`; `WledHttpClientOptionsTests` | `dotnet test windows-agent/tests/BusyLight.Platform.Tests/BusyLight.Platform.Tests.csproj -c Release` | In progress |
| Cross-agent corpus protection | C# and Swift corpus runners; CI jobs | `dotnet test windows-agent/BusyLight.sln -c Release`; `swift test --package-path macos-agent` | Planned |
