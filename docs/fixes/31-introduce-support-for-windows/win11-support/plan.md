# Windows 11 Support Plan

## Approved scope

Implement the complete `docs/specs/win11-support.md` specification as a native
Windows 11 BusyLight agent. The agent will be C# 12 on .NET 8, use a WinExe
with WinForms `NotifyIcon` for a tray-only process, and WPF only for settings
dialogs. The source specification remains the authority for detailed parity
rules and Windows API mappings.

## Delivery plan

1. Create the .NET solution, portable Core project, and conformance corpus;
   port domain, state machine, office hours, calendar availability, WLED
   protocol types, configuration model, and IPv4 validation using Red-Green-
   Refactor cycles.
2. Add networking: HTTP retry/proxy semantics, WLED client, mDNS, subnet scan,
   health/reconnect handling, and network-path monitoring.
3. Add configuration persistence, logging, tray/menu UI, icon assets,
   dialogs, diagnostics, composition root, and startup registration.
4. Add Windows presence events, global hotkeys, office-hours scheduling, and
   lifecycle shutdown.
5. Add meeting detection, safe window/process inspection, capture-device
   signal, and all calendar providers with their fallback behavior.
6. Add MSIX/portable packaging, CI/release automation, and Windows-facing
   documentation.
7. Verify targeted tests after every slice, then the full .NET solution,
   Windows CI build/publish/package checks, macOS regression, and the manual
   WLED matrix documented by the specification.

## Test-first inventory

- `StateMachineConformanceTests`, `StateTransitionTests`,
  `OfficeHoursConfigurationTests`, `CalendarAvailabilityResolverTests`
- `ConfigurationStoreTests`, `ConfigurationKeyParityTests`,
  `NetworkAddressValidatorTests`, `WledHttpClientTests`,
  `WledClientDiscoveryTests`
- `TrayMenuBuilderTests`, `SystemPresenceMonitorTests`,
  `HotkeyRegistrationTests`, `MeetingDetectionEngineTests`
- `CalendarEngineTests`, `CalendarProviderMappingTests`,
  `AppxManifestTests`, and platform-isolated adapter tests

## Agent roster and ownership

The roster is assigned after this tracking PR is visible and before production
implementation starts. Ownership will be non-overlapping:

| Owner | Files | Responsibility |
|---|---|---|
| Root / integration owner | `windows-agent/BusyLight.sln`, `windows-agent/Directory.Build.props`, `windows-agent/src/BusyLight.Platform/**`, `windows-agent/src/BusyLight.Agent/**`, `windows-agent/tests/BusyLight.Platform.Tests/**`, packaging, CI, shared docs | coordinate slices, platform/agent implementation, and final integration |
| `/root/core` | `windows-agent/src/BusyLight.Core/**`, `windows-agent/tests/BusyLight.Core.Tests/**`, `docs/specs/state-machine-conformance.json` | pure domain and conformance behavior |
| `/root/auditor` | `docs/fixes/31-introduce-support-for-windows/win11-support/audit.md` | independent TDD and traceability review |

There are no overlapping owned paths. The root is the integration owner.

## Tracking

- Draft PR: https://github.com/dralquinta/busy-light/pull/32
- Base branch: `main`.
- No implementation files are modified by this tracking commit.
