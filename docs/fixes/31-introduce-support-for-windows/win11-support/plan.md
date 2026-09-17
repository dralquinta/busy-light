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
| Integration owner | solution, shared docs, final merge | coordinate slices and validate end-to-end |
| Core owner | `windows-agent/src/BusyLight.Core/**`, Core tests | pure domain and conformance behavior |
| Platform owner | `windows-agent/src/BusyLight.Platform/**`, Platform tests | Windows adapters and networking |
| Verification owner | test audit and docs only | independent TDD/traceability review |

## Tracking

- Draft PR: pending creation.
- Base branch: `main`.
- No implementation files are modified by this tracking commit.
