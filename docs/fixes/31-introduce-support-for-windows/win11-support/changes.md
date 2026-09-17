# Changes — Windows 11 Support

## Root Cause Analysis

Windows users have no BusyLight agent. The repository only contains the macOS
Swift implementation, so there is no native tray process, Windows integration,
or release artifact. Existing tests and release automation cover macOS only,
which allowed this unsupported platform gap to persist.

## How It Was Fixed

Implemented the initial .NET 8 Windows agent foundation: a portable Core state
machine and configuration model, WLED transport/discovery/health primitives,
native system-presence mapping and monitor, a tray host skeleton, platform
tests, and Windows CI. The Platform project now explicitly references
`Microsoft.Win32.SystemEvents` so the native session and power event types
compile on Windows.

## Summary

The Windows implementation is in progress. Native presence monitor compilation
has been repaired after Windows CI reported the missing forwarded assembly.

## Validation

Windows CI run `35177667095` exposed the `CS1069` dependency failure. A new
Windows CI run is required to validate the package-reference remediation;
local .NET execution is unavailable on the authoring host.
