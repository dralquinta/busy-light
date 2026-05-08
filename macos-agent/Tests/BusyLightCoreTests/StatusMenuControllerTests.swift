import XCTest
@testable import BusyLightCore

@MainActor
final class StatusMenuControllerTests: XCTestCase {
    func testDevicesLiveUnderSettingsDevicesSubmenu() {
        let controller = StatusMenuController()

        let topLevelTitles = controller.menuTitlesForTesting()
        XCTAssertFalse(topLevelTitles.contains("Mode"))
        XCTAssertFalse(topLevelTitles.contains("Resume Calendar Control"))
        XCTAssertFalse(topLevelTitles.contains { $0.hasPrefix("Device:") })
        XCTAssertFalse(topLevelTitles.contains { $0.hasPrefix("Connected to:") })
        XCTAssertFalse(topLevelTitles.contains { $0.hasPrefix("Last sync:") })

        let settingsTitles = controller.menuTitlesForTesting(path: ["Settings"])
        XCTAssertTrue(settingsTitles.contains("Devices"))

        let deviceTitles = controller.menuTitlesForTesting(path: ["Settings", "Devices"])
        XCTAssertTrue(deviceTitles.contains { $0.hasPrefix("Device:") })
        XCTAssertTrue(deviceTitles.contains { $0.hasPrefix("Connected to:") })
        XCTAssertTrue(deviceTitles.contains { $0.hasPrefix("Last sync:") })
        XCTAssertTrue(deviceTitles.contains("Configure Devices..."))
    }

    func testTopLevelDeviceSummarySitsBelowStatusAndShowsOnlineCount() {
        let controller = StatusMenuController()
        let devices = [
            WLEDDevice(id: "one", address: "192.168.1.10", port: 80, name: "One", isOnline: true),
            WLEDDevice(id: "two", address: "192.168.1.11", port: 80, name: "Two", isOnline: true),
            WLEDDevice(id: "three", address: "192.168.1.12", port: 80, name: "Three", isOnline: false),
        ]

        controller.updateDeviceList(devices)

        let topLevelTitles = controller.menuTitlesForTesting()
        XCTAssertTrue(topLevelTitles.first?.hasPrefix("Status:") == true)
        XCTAssertEqual(topLevelTitles.dropFirst().first, "Devices: Online (2 online)")
    }

    func testSignalFeedbackUpdatesImmediately() {
        let controller = StatusMenuController()

        controller.updateSignalFeedback(.sending(.busy))
        XCTAssertTrue(controller.menuTitlesForTesting().contains("Signal: Sending Busy..."))

        controller.updateSignalFeedback(.sent(state: .busy, deliveredCount: 1, totalCount: 1, date: Date(timeIntervalSince1970: 0)))
        XCTAssertTrue(controller.menuTitlesForTesting().contains { $0.hasPrefix("Signal: Sent Busy") })

        controller.updateSignalFeedback(.failed(state: .busy, deliveredCount: 0, totalCount: 1, date: Date(timeIntervalSince1970: 0)))
        XCTAssertTrue(controller.menuTitlesForTesting().contains { $0.hasPrefix("Signal: Failed Busy") })
    }

    func testSettingsDialogSectionsSeparateDeviceConfigurationAndOfficeHours() {
        let controller = StatusMenuController()

        XCTAssertEqual(controller.settingsSectionTitlesForTesting(), ["Device Configuration", "Office Hours"])
    }

    func testOfficeHoursIsExplicitSettingsMenuItem() {
        let controller = StatusMenuController()

        let settingsTitles = controller.menuTitlesForTesting(path: ["Settings"])

        XCTAssertTrue(settingsTitles.contains("Office Hours..."))
    }

    func testOfficeHoursEditorUsesOutlookStyleDayAndTimeControls() {
        let controller = StatusMenuController()

        XCTAssertEqual(controller.officeHoursDayLabelsForTesting(), ["M", "T", "W", "T", "F", "S", "S"])
        XCTAssertEqual(controller.officeHoursTimeControlLabelsForTesting(), ["from", "to", "All day"])
        XCTAssertTrue(controller.officeHoursTimeOptionsForTesting().contains("5:30 PM"))
        XCTAssertTrue(controller.officeHoursTimeOptionsForTesting().contains("6:30 PM"))
        XCTAssertGreaterThanOrEqual(controller.officeHoursEditorSizeForTesting().width, 420)
        XCTAssertGreaterThanOrEqual(controller.officeHoursEditorSizeForTesting().height, 96)
    }
}
