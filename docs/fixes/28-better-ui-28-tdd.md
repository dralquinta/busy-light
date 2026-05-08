# BusyLight UI, Office Hours, and Reconnect TDD

## Problem Statement
- Feature/bugfix mix: reorganize the menu UI, move device details under `Settings > Devices`, remove redundant top-level mode/resume clutter, show immediate WLED send feedback, add office-hours control, and recover automatically when the laptop leaves and rejoins the light's network.
- Expected behavior: BusyLight should show an ordered status menu, send visible `Signal:` feedback for every light update, run automatic presence only during office hours unless manually overridden, and rediscover/rejoin WLED devices after network reconnect.

## Assumptions
- Office hours are local-time daily windows, enabled by default for Monday-Friday 09:00-17:00.
- `Turn Off BusyLight` remains the manual ad-hoc way to keep the light off until explicit resume.
- `Automatic Calendar Control` is the resume action and replaces the redundant top-level resume item.
- The app-level reconnect hook is `NetworkClient.onDeviceReconnected`, because BusyLight already uses it to resend the current presence state.

## Target Files
- `macos-agent/Sources/BusyLightCore/UI/StatusMenuController.swift`
- `macos-agent/Sources/BusyLightCore/Models/AppConfiguration.swift`
- `macos-agent/Sources/BusyLightCore/Core/ConfigurationManager.swift`
- `macos-agent/Sources/BusyLightCore/State/PresenceStateMachine.swift`
- `macos-agent/Sources/BusyLightCore/State/StateEvent.swift`
- `macos-agent/Sources/BusyLightCore/State/StateSource.swift`
- `macos-agent/Sources/BusyLightCore/State/StateTransition.swift`
- `macos-agent/Sources/BusyLightCore/Network/NetworkClient.swift`
- `macos-agent/Sources/BusyLight/BusyLightApp.swift`
- Focused tests under `macos-agent/Tests/BusyLightCoreTests/`

## Red
- Added `StatusMenuControllerTests.testDevicesLiveUnderSettingsDevicesSubmenu`.
- Added `StatusMenuControllerTests.testSignalFeedbackUpdatesImmediately`.
- Added `StatusMenuControllerTests.testTopLevelDeviceSummarySitsBelowStatusAndShowsOnlineCount`.
- Added `StatusMenuControllerTests.testSettingsDialogSectionsSeparateDeviceConfigurationAndOfficeHours`.
- Added `StatusMenuControllerTests.testOfficeHoursIsExplicitSettingsMenuItem`.
- Added `StatusMenuControllerTests.testOfficeHoursEditorUsesOutlookStyleDayAndTimeControls` after the GUI showed the `Office Hours...` alert mostly blank/collapsed.
- Added `OfficeHoursConfigurationTests` for default weekday business hours and cross-midnight windows.
- Added `OfficeHoursPersistenceTests.testOfficeHoursPersistAcrossConfigurationManagerInstances`.
- Added `PresenceStateMachineOfficeHoursTests` for outside-hours off, automatic resume, and manual off preservation.
- Added `PresenceStateMachineOfficeHoursTests.testManualOverrideOutsideOfficeHoursIsNotImmediatelyTurnedOffAgain`.
- Added `NetworkClientDiscoveryTests.testRefreshInvokesReconnectHookWhenScanFindsDeviceAfterLoss`.
- Added `NetworkClientDiscoveryTests.testNetworkPathAvailableRevalidatesAndRequestsResendForKnownOnlineDevice`.
- Expected failures: missing menu/test APIs, no `Signal:` row, no top-level device summary, no clear office-hours settings section, no office-hours model/state event, no send result, no explicit network-path rejoin hook, and outside-hours ticks overriding manual state.
- Follow-up expected failure: office hours existed only inside the general preferences dialog and was not discoverable from the `Settings` menu.
- Follow-up expected failure: the direct `Office Hours...` alert used an intrinsically sized stack and a freeform schedule field, allowing AppKit to collapse the accessory view so the day/time controls were not visible.
- Actual focused/full test commands could not reach assertions in this environment because the active Command Line Tools Swift install cannot import `XCTest`.

## Green
- Menu UI now has a top-level status row, top-level `Signal:` feedback row, one `Control` submenu, `Calendars`, `Settings`, and quit.
- Added a top-level device summary directly under `Status`, showing only device reachability and online count.
- Device rows moved from the top-level menu into `Settings > Devices`; device configuration is available from `Configure Devices...`.
- Removed redundant top-level `Mode` and `Resume Calendar Control` items; resume is now `Control > Automatic Calendar Control`.
- Added `SignalFeedback` and wired BusyLight to show `Sending`, then `Sent` or `Failed` using real `NetworkClient.sendState` delivery counts.
- Added `OfficeHoursConfiguration`, persisted it through `ConfigurationManager`, and exposed start/end/weekday settings.
- Added office-hours state-machine gating: outside hours sends `.off`; returning inside hours resumes auto only if office-hours logic caused the off state.
- Added a visually separated `Office Hours` section in settings below `Device Configuration`, with enablement, start/end times, and weekdays.
- Added an explicit `Settings > Office Hours...` menu item that opens the office-hours configuration directly.
- Replaced the freeform office-hours schedule field with a fixed-size Outlook-style editor: `On`, Monday-Sunday day chips, `from` and `to` 30-minute time dropdowns, and an `All day` checkbox. The direct menu item and the Preferences section now use the same editor.
- Outside-office-hours checks now leave an active manual override alone, so a manual state can intentionally be sent while outside office hours.
- Added an app-level office-hours monitor that evaluates immediately and then every 60 seconds.
- Added `WLEDStateSendResult` so send success/failure feedback is based on actual WLED deliveries.
- Added reconnect bookkeeping and `handleNetworkPathAvailable()` so a satisfied network path revalidates devices and requests a state resend.
- Added `NWPathMonitor` app wiring to call the network reconnect hook when the laptop rejoins a network.

## Refactor Notes
- Kept the existing state machine and network client structure; changes are localized to the requested behavior.
- Added DEBUG-only menu inspection helpers for AppKit menu tests rather than exposing mutable UI internals.
- Consolidated the TDD readout into this branch-correct file and removed the duplicate temporary reconnect TDD file.

## Verification
- `swift test --filter 'StatusMenuControllerTests/testTopLevelDeviceSummarySitsBelowStatusAndShowsOnlineCount|StatusMenuControllerTests/testSettingsDialogSectionsSeparateDeviceConfigurationAndOfficeHours|PresenceStateMachineOfficeHoursTests/testManualOverrideOutsideOfficeHoursIsNotImmediatelyTurnedOffAgain'`
  - Result: blocked by `no such module 'XCTest'` before assertions.
- `swift test --filter StatusMenuControllerTests/testOfficeHoursIsExplicitSettingsMenuItem`
  - Result: blocked by `no such module 'XCTest'` before assertions.
- `swift test --filter StatusMenuControllerTests/testOfficeHoursEditorUsesOutlookStyleDayAndTimeControls` from `macos-agent/`
  - Result: blocked by `no such module 'XCTest'` before assertions.
- `swift test --filter 'StatusMenuControllerTests|OfficeHours|PresenceStateMachineOfficeHours|NetworkClientDiscoveryTests/testNetworkPathAvailableRevalidatesAndRequestsResendForKnownOnlineDevice'`
  - Result: blocked by `no such module 'XCTest'` before assertions.
- `swift build`
  - Result: passed before and after the follow-up changes, including the fixed-size Outlook-style office-hours editor.
- `swift test`
  - Result: blocked by `no such module 'XCTest'` before assertions.
- `./build.sh test`
  - Result: exit 0 by repo wrapper policy; skipped tests because full Xcode is not installed.
- `git diff --check`
  - Result: passed.
- `./build.sh`
  - Result: passed before and after the follow-up changes; rebuilt `BusyLight.app`, converted icon, and applied ad-hoc codesign.

## Root Cause
- The status menu had grown into a flat list, so device status, mode, resume, timeout, calendar, settings, and debug controls competed at the same level.
- UI feedback was inferred from device-list updates rather than the actual send lifecycle, so users could not immediately tell that a WLED update was being sent and whether it succeeded.
- The existing off/manual controls were ad-hoc only; there was no persisted office-hours window to automatically turn the light off outside working time.
- The direct office-hours dialog relied on an unconstrained `NSStackView` accessory in `NSAlert`; in the real GUI that stack could collapse, leaving the dialog looking empty instead of showing schedule controls.
- Reconnect notification lived around health-check recovery, so explicit rediscovery or a network-path rejoin could repopulate devices without telling the app to resend the current state.

## Final Status
- Source fix implemented and build verified.
- Regression tests were added but cannot be executed on this machine until the selected developer toolchain includes XCTest, typically by switching to a full Xcode install.
