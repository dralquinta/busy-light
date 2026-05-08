import XCTest
@testable import BusyLightCore

final class OfficeHoursConfigurationTests: XCTestCase {
    func testDefaultOfficeHoursCoversWeekdayBusinessHoursOnly() throws {
        let officeHours = OfficeHoursConfiguration.defaultConfiguration
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let mondayMorning = try XCTUnwrap(calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 5,
            day: 4,
            hour: 10,
            minute: 0
        )))
        let mondayEvening = try XCTUnwrap(calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 5,
            day: 4,
            hour: 19,
            minute: 0
        )))
        let saturdayMorning = try XCTUnwrap(calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 5,
            day: 2,
            hour: 10,
            minute: 0
        )))

        XCTAssertTrue(officeHours.contains(mondayMorning, calendar: calendar))
        XCTAssertFalse(officeHours.contains(mondayEvening, calendar: calendar))
        XCTAssertFalse(officeHours.contains(saturdayMorning, calendar: calendar))
    }

    func testOfficeHoursSupportsWindowsThatCrossMidnight() throws {
        let officeHours = OfficeHoursConfiguration(
            isEnabled: true,
            startMinuteOfDay: 22 * 60,
            endMinuteOfDay: 2 * 60,
            activeWeekdays: [6]
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let fridayLate = try XCTUnwrap(calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 5,
            day: 8,
            hour: 23,
            minute: 30
        )))
        let saturdayEarly = try XCTUnwrap(calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 5,
            day: 9,
            hour: 1,
            minute: 30
        )))
        let saturdayMidday = try XCTUnwrap(calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 5,
            day: 9,
            hour: 12,
            minute: 0
        )))

        XCTAssertTrue(officeHours.contains(fridayLate, calendar: calendar))
        XCTAssertTrue(officeHours.contains(saturdayEarly, calendar: calendar))
        XCTAssertFalse(officeHours.contains(saturdayMidday, calendar: calendar))
    }

    func testParsesWeekdayRangeScheduleText() throws {
        let officeHours = try XCTUnwrap(OfficeHoursConfiguration.parseSchedule("Mon-Fri 09:00-18:00"))

        XCTAssertEqual(officeHours.startMinuteOfDay, 9 * 60)
        XCTAssertEqual(officeHours.endMinuteOfDay, 18 * 60)
        XCTAssertEqual(officeHours.activeWeekdays, [2, 3, 4, 5, 6])
        XCTAssertEqual(officeHours.scheduleDescription, "Mon-Fri 09:00-18:00")
    }

    func testParsesCommaSeparatedScheduleText() throws {
        let officeHours = try XCTUnwrap(OfficeHoursConfiguration.parseSchedule("Mon,Wed,Fri 08:30-12:15"))

        XCTAssertEqual(officeHours.startMinuteOfDay, 8 * 60 + 30)
        XCTAssertEqual(officeHours.endMinuteOfDay, 12 * 60 + 15)
        XCTAssertEqual(officeHours.activeWeekdays, [2, 4, 6])
        XCTAssertEqual(officeHours.scheduleDescription, "Mon,Wed,Fri 08:30-12:15")
    }

    func testRejectsInvalidScheduleText() {
        XCTAssertNil(OfficeHoursConfiguration.parseSchedule("weekdays"))
        XCTAssertNil(OfficeHoursConfiguration.parseSchedule("Mon-Fri 25:00-18:00"))
        XCTAssertNil(OfficeHoursConfiguration.parseSchedule("Noday 09:00-18:00"))
    }
}
