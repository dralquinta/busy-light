# Independent Phase 1 TDD and Traceability Audit

## Scope and method

Reviewed on 2026-09-17 against the approved source specification
`docs/specs/win11-support.md`, the tracking `plan.md`, `spec.md`,
`traceability.md`, and the macOS Core test inventory. This audit owns no
production or test code. It evaluates the first independently mergeable
increment: Phase 1, **Core domain**.

## Phase 1 acceptance gate

Phase 1 is acceptable only when all of the following are demonstrated:

| Gate | Required evidence |
|---|---|
| Portable layering | `BusyLight.Core.csproj` targets `net8.0`; compilation succeeds without Windows, WinForms, WPF, WinRT, P/Invoke, or platform project references. |
| State parity | All state-model raw values, source priorities, event-to-source/target mappings, guards, mode changes, snapshot/restore, timer cancellation, stabilization, callbacks, and required state-machine log names are covered. |
| Shared conformance | `docs/specs/state-machine-conformance.json` exists and `StateMachineConformanceTests` evaluates every case deterministically with injected time/dispatcher behavior. The macOS test job must be updated before claiming cross-platform drift protection. |
| Core scheduling/calendar behavior | Office-hours edge cases and availability resolution are tested, including Sunday/`DayOfWeek` mapping, midnight wrap, all-day, disabled, and `NotSupported => busy`. |
| Protocol/config primitives | WLED request/result types, configuration defaults/normalization, and strict IPv4 validation are unit-tested. Persistence is Phase 3, so JSON I/O itself is not a Phase 1 acceptance dependency. |

## Required Red tests before corresponding Core implementation

1. `PresenceStateModelTests`: exact lower-case raw values, display names, all six states/modes/sources, priorities, and `BusyReason` values.
2. `StateTransitionTests`: exact allowed/blocked results and exact reasons for off, manual, priority, and startup exceptions; `TurnOff`, `ResumeAuto`, and expiry mapping peculiarities.
3. `StateMachineConformanceTests`: JSON deserialization plus representative sequences for resume-before-expiry, manual/calendar blocking, system snapshot/restore, office-hours auto-off/re-entry, meeting end/calendar sync, turn-off, and stabilization replacement.
4. `PresenceStateMachineTests`: callback order/count, no-op calendar update, override expiry including never, manual blocked while away, cancellation behavior, and each Appendix A state-machine event name.
5. `OfficeHoursConfigurationTests`: weekday selection, overnight previous-day evaluation, all-day, disabled, parser/description round-trip, invalid syntax, and .NET `DayOfWeek` conversion.
6. `CalendarAvailabilityResolverTests`: busy/unavailable/not-supported dominance, tentative, free-only, and empty input behavior.
7. `AppConfigurationTests`: 27 parity settings plus Windows additions, defaults, preset bounds, timeout floor/default, pinned port, and invalid hotkey-keycode fallback contract. File persistence/migration/corruption tests belong to Phase 3 `ConfigurationStoreTests`.
8. `NetworkAddressValidatorTests`: valid boundary octets, leading-zero policy matching Swift, malformed segment count/characters/length, and normalization behavior.
9. `WledTypesTests`: JSON body is exactly `{"ps": preset, "v": true}` and per-state default preset mapping, including Off.
10. `BusyLightLogTests`: canonical `event [k=v k=v]` formatting and error context formatting, without coupling Core to a concrete sink.

## Findings

### F1 — Traceability is too coarse for parity completion (open)

`traceability.md` maps seven broad acceptance criteria but has no row-level
link from §2/§7 requirements to a concrete test/manual evidence item. That is
not sufficient to prove the specification's definition of done, which requires
every parity item to have automated or documented manual evidence.

**Required correction:** expand the matrix at least by Phase 1 requirement
families (D-1/D-2, SM-W1..SM-W5, CFG model requirements, office-hours,
availability/WLED primitives, and logging), with test names, validation
commands, owner, and final status. Expand it further phase-by-phase rather
than marking AC-1/AC-2 complete from broad suite success.

### F2 — The conformance corpus must be added before Phase 1 can pass (open)

The tracking plan lists the corpus, but it was absent at review time. The spec
requires the corpus at `docs/specs/state-machine-conformance.json`, executed by
both platform jobs. A C#-only corpus test cannot establish G2/CI-4.

**Required correction:** add the JSON corpus and C# runner in the first Red
cycle; add an equivalent Swift test runner or explicitly record the macOS
runner update and CI evidence before final completion.

### F3 — Timer/state-machine tests need deterministic seams (open)

The state machine requirements include expiry, cancellation, and stabilization.
Tests based on real `Task.Delay` will be flaky and cannot reliably establish
the ordering requirement that `ResumeAuto` precedes expiry processing.

**Required correction:** inject a clock/timer scheduler and UI dispatcher into
Core (interfaces or test fakes), then test queued callbacks and cancellation
without wall-clock sleeps.

### F4 — “27 settings” is internally ambiguous (open, non-blocking)

The source text calls the parity surface 27 settings, but its enumerated list
contains the macOS settings plus seven Windows-only settings. This should be
made mechanically unambiguous in the eventual parity test: test named keys
and defaults, not only a numeric count. The Windows-only key set must be
separately asserted.

### F5 — Current planned validation needs explicit executable commands (open)

The plan names tests but does not yet record exact Phase 1 commands. The
following commands should be used once solution paths exist:

```powershell
dotnet test windows-agent/tests/BusyLight.Core.Tests/BusyLight.Core.Tests.csproj -c Release
dotnet build windows-agent/src/BusyLight.Core/BusyLight.Core.csproj -c Release -f net8.0
dotnet test windows-agent/BusyLight.sln -c Release
swift test --package-path macos-agent
```

On the Linux authoring host, the first two commands may be run only if the
installed SDK supports them; Windows-specific build/package validation remains
authoritative on `windows-latest`. The final CI validation must also prove the
macOS conformance runner after the shared corpus changes.

## Audit conclusion

Phase 1 may proceed under TDD, but it must not be marked complete until F1–F5
are resolved or explicitly documented as blocked with a user-approved
alternative. No production behavior was inspected as implemented during this
audit; this is a requirements and verification review only.
