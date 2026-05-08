import XCTest
@testable import BusyLightCore

@MainActor
final class PresenceStateMachineOfficeHoursTests: XCTestCase {
    func testOutsideOfficeHoursTurnsLightOff() {
        let machine = PresenceStateMachine(initialState: .busy, initialMode: .auto)

        machine.handleEvent(.officeHoursChanged(isWithinOfficeHours: false))

        XCTAssertEqual(machine.currentMode, .off)
        XCTAssertEqual(machine.currentState, .off)
        XCTAssertEqual(machine.currentSource, .officeHours)
    }

    func testReturningInsideOfficeHoursResumesAutomaticControl() {
        let machine = PresenceStateMachine(initialState: .busy, initialMode: .auto)
        var syncRequestCount = 0
        machine.onRequestCalendarSync = {
            syncRequestCount += 1
        }

        machine.handleEvent(.officeHoursChanged(isWithinOfficeHours: false))
        machine.handleEvent(.officeHoursChanged(isWithinOfficeHours: true))

        XCTAssertEqual(machine.currentMode, .auto)
        XCTAssertEqual(machine.currentSource, .startup)
        XCTAssertEqual(syncRequestCount, 1)
    }

    func testUserTurnOffIsNotAutomaticallyResumedByOfficeHoursTick() {
        let machine = PresenceStateMachine(initialState: .busy, initialMode: .auto)
        var syncRequestCount = 0
        machine.onRequestCalendarSync = {
            syncRequestCount += 1
        }

        machine.handleEvent(.turnOff)
        machine.handleEvent(.officeHoursChanged(isWithinOfficeHours: true))

        XCTAssertEqual(machine.currentMode, .off)
        XCTAssertEqual(machine.currentState, .off)
        XCTAssertEqual(syncRequestCount, 0)
    }

    func testManualOverrideOutsideOfficeHoursIsNotImmediatelyTurnedOffAgain() {
        let machine = PresenceStateMachine(initialState: .busy, initialMode: .auto)

        machine.handleEvent(.officeHoursChanged(isWithinOfficeHours: false))
        machine.handleEvent(.manualOverride(.busy))
        machine.handleEvent(.officeHoursChanged(isWithinOfficeHours: false))

        XCTAssertEqual(machine.currentMode, .manual)
        XCTAssertEqual(machine.currentState, .busy)
        XCTAssertEqual(machine.currentSource, .manual)
    }
}
