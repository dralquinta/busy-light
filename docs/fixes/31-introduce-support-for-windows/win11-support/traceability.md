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
