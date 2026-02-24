# Changelog

All notable changes to BusyLight will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial release automation system
- Complete DMG packaging with custom icon
- Code signing and notarization support
- GitHub Actions CI/CD workflow
- Comprehensive release documentation
- Calendar filtering: Inline submenu for selecting calendars (similar to Mode/Debug menus)
- Calendar filter validation with fallback to all calendars when no matches found
- Enhanced status display showing source/reason (Calendar, Manual, Meeting provider: Zoom/Teams/Meet)
- Google Meet browser detection with "Meet:" window title pattern
- Automatic remote calendar sync (CalDAV/Exchange) for faster Gmail/Outlook event detection
- Debug menu icon (🐛) for better visibility

### Fixed
- Added missing `AppConfiguration.defaultConfiguration` static property
- Browser meeting detection now properly identifies Google Meet sessions
- Status display now shows detailed context (automatic/manual mode, calendar, meeting type)
- Google Meet detection refined to only match active meetings (not landing page) using "meet:" pattern
- Meeting detection now properly clears when resuming calendar control (Ctrl+Cmd+4)
- Added 10-second suppression period after resuming calendar to prevent stale meeting tabs from re-triggering busy status
- Google Meet and Teams browser tabs left open after meeting ends no longer trigger busy status (requires active indicators: camera/microphone/recording/calling)
- Calendar filtering regression: Empty filter results now fall back to all calendars instead of showing no events
- Calendar menu now refreshes automatically after permissions are granted
- Leaving a meeting now immediately transitions to available instead of waiting for calendar scan

---

<!-- Release entries will be auto-generated below this line -->
