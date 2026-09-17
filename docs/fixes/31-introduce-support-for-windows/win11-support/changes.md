# Changes — Windows 11 Support

## Root Cause Analysis

Windows users have no BusyLight agent. The repository only contains the macOS
Swift implementation, so there is no native tray process, Windows integration,
or release artifact. Existing tests and release automation cover macOS only,
which allowed this unsupported platform gap to persist.

## How It Was Fixed

Pending implementation. The planned correction is a separately maintained
.NET 8 Windows agent with a pure Core parity layer, Windows platform adapters,
native tray UI, test corpus, packaging, CI, and platform documentation.

## Summary

Tracking artifacts created; implementation has not started.

## Validation

Not run. Tracking documentation only.
