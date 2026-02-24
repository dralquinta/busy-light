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
- Calendar filtering: Select which calendars affect your presence status via "Select Calendars…" menu
- Enhanced status display showing source/reason (Calendar, Manual, Meeting provider: Zoom/Teams/Meet)
- Google Meet browser detection with "Meet:" window title pattern

### Fixed
- Added missing `AppConfiguration.defaultConfiguration` static property
- Browser meeting detection now properly identifies Google Meet sessions
- Status display now shows detailed context (automatic/manual mode, calendar, meeting type)
- Google Meet detection refined to only match active meetings (not landing page) using "meet:" pattern
- Meeting detection now properly clears when resuming calendar control (Ctrl+Cmd+4)
- Added 5-second suppression period after resuming calendar to prevent stale meeting tabs from re-triggering busy status

---

<!-- Release entries will be auto-generated below this line -->
