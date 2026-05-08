import XCTest
@testable import BusyLightCore

@MainActor
final class OfficeHoursPersistenceTests: XCTestCase {
    func testOfficeHoursPersistAcrossConfigurationManagerInstances() {
        let suiteName = "BusyLightTests.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create UserDefaults suite")
            return
        }

        userDefaults.removePersistentDomain(forName: suiteName)

        let config = ConfigurationManager(userDefaults: userDefaults)
        config.setOfficeHoursEnabled(true)
        config.setOfficeHoursStartMinuteOfDay(8 * 60)
        config.setOfficeHoursEndMinuteOfDay(18 * 60)
        config.setOfficeHoursActiveWeekdays([2, 3, 4])

        let reloaded = ConfigurationManager(userDefaults: userDefaults)
        XCTAssertTrue(reloaded.getOfficeHoursEnabled())
        XCTAssertEqual(reloaded.getOfficeHoursStartMinuteOfDay(), 8 * 60)
        XCTAssertEqual(reloaded.getOfficeHoursEndMinuteOfDay(), 18 * 60)
        XCTAssertEqual(reloaded.getOfficeHoursActiveWeekdays(), [2, 3, 4])
    }
}
