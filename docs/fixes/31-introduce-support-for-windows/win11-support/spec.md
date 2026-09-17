# Canonical Specification — Windows 11 Support

## Source of truth

`docs/specs/win11-support.md` (Spec ID `win11-support`, tracking issue #31),
as explicitly approved by the user on 2026-09-17.

## Scope

Deliver a Windows 11 build 22000+ x64 and ARM64 BusyLight presence agent with
functional and behavioral parity to `macos-agent` v1.0.3. The implementation
is a .NET 8/C# 12 native agent: portable Core, Windows Platform adapters, and
a tray-only WinExe with WPF dialogs. It includes networking, presence state,
calendar and meeting inputs, native system/hotkey integration, persistence,
packaging, CI, and documentation.

## Non-goals

- Supported Windows 10 builds, Microsoft Store distribution, shared Swift/.NET
  binaries, firmware changes, or Windows-only presence features.
- Cloud calendar access by default; Graph remains opt-in with explicit notice.

## Assumptions

- `main` is the PR base.
- The Linux development host cannot execute Windows UI/MSIX runtime tests;
  `windows-latest` CI is the authoritative Windows validation environment.
- MSIX is primary distribution and portable ZIP falls back to Outlook COM/ICS
  when package-identity calendar access is unavailable.

## Acceptance criteria

1. A C#/.NET 8 native Windows tray agent implements all parity entries in
   sections 2 and 7 of the source specification with no taskbar/console window.
2. The state machine preserves exact states, priorities, events, guards,
   callback semantics, log event names, and JSON corpus outcomes.
3. WLED HTTP protocol, retry/no-proxy behavior, discovery, deduplication,
   health checks, and reconnect behavior match macOS semantics.
4. Calendar, meeting, system presence, hotkeys, office hours, persistence,
   tray/settings UI, diagnostics, startup, and lifecycle behavior meet their
   corresponding source-spec requirements.
5. MSIX and portable ZIP artifacts build for x64 and ARM64; CI tests, builds,
   packages, and publishes them alongside macOS artifacts.
6. Documentation covers both platforms and the manual WLED/system test matrix.
7. Core and platform behaviors have automated tests; platform-only checks have
   documented manual tests where automation is not meaningful.

## Unresolved questions

None blocking. The specification's open questions use their stated defaults.
