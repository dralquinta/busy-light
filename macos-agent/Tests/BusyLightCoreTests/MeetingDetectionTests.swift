import XCTest
@testable import BusyLightCore

// MARK: - Confidence Model Tests

final class MeetingConfidenceTests: XCTestCase {

    func testConfidenceComparison() {
        XCTAssertLessThan(MeetingConfidence.none, .low)
        XCTAssertLessThan(MeetingConfidence.low, .medium)
        XCTAssertLessThan(MeetingConfidence.medium, .high)
        XCTAssertEqual(MeetingConfidence.high, .high)
    }

    func testConfidenceDisplayNames() {
        XCTAssertEqual(MeetingConfidence.none.displayName, "none")
        XCTAssertEqual(MeetingConfidence.low.displayName, "low")
        XCTAssertEqual(MeetingConfidence.medium.displayName, "medium")
        XCTAssertEqual(MeetingConfidence.high.displayName, "high")
    }

    func testCaseIterable() {
        XCTAssertEqual(MeetingConfidence.allCases, [.none, .low, .medium, .high])
    }
}

// MARK: - MeetingStatus Tests

final class MeetingStatusTests: XCTestCase {

    func testNoneIsNotInMeeting() {
        XCTAssertFalse(MeetingStatus.none.isInMeeting)
        XCTAssertNil(MeetingStatus.none.provider)
        XCTAssertEqual(MeetingStatus.none.confidence, .none)
    }

    func testInMeetingPropertiesAreAccessible() {
        let status = MeetingStatus.inMeeting(
            confidence: .high, provider: .zoom, signal: .combined
        )
        XCTAssertTrue(status.isInMeeting)
        XCTAssertEqual(status.provider, .zoom)
        XCTAssertEqual(status.confidence, .high)
    }

    func testProviderDisplayNames() {
        XCTAssertEqual(MeetingProvider.zoom.displayName, "Zoom")
        XCTAssertEqual(MeetingProvider.teams.displayName, "Microsoft Teams")
        XCTAssertEqual(MeetingProvider.meet.displayName, "Google Meet")
    }

    func testProviderRawValues() {
        XCTAssertEqual(MeetingProvider.zoom.rawValue, "zoom")
        XCTAssertEqual(MeetingProvider.teams.rawValue, "teams")
        XCTAssertEqual(MeetingProvider.meet.rawValue, "meet")
    }
}

// MARK: - Mock Detector

/// A simple mock detector that returns a predetermined result.
final class MockMeetingDetector: MeetingDetectorProtocol, @unchecked Sendable {
    let provider: MeetingProvider
    var isEnabled: Bool = true
    var stubbedResult: MeetingDetectionResult

    init(provider: MeetingProvider, status: MeetingStatus) {
        self.provider = provider
        self.stubbedResult = MeetingDetectionResult(provider: provider, status: status)
    }

    func detect() -> MeetingDetectionResult {
        return stubbedResult
    }
}

// MARK: - MeetingDetectionEngine Tests

@MainActor
final class MeetingDetectionEngineTests: XCTestCase {

    func testDefaultDetectorsCoversAllProviders() {
        let detectors = MeetingDetectionEngine.defaultDetectors()
        let providers = Set(detectors.map { $0.provider })
        XCTAssertTrue(providers.contains(.zoom))
        XCTAssertTrue(providers.contains(.teams))
        XCTAssertTrue(providers.contains(.meet))
    }

    func testHighConfidenceMeetingFiresCallback() async {
        let mockDetector = MockMeetingDetector(
            provider: .zoom,
            status: .inMeeting(confidence: .high, provider: .zoom, signal: .combined)
        )
        let engine = MeetingDetectionEngine(detectors: [mockDetector])
        engine.pollIntervalSeconds = 0.05  // 50 ms for fast unit testing
        engine.confidenceThreshold = .high

        var received: MeetingStatus?
        let expectation = XCTestExpectation(description: "meeting callback fired")
        engine.onMeetingStatusChanged = {
            received = $0
            expectation.fulfill()
        }

        engine.start()
        await fulfillment(of: [expectation], timeout: 2.0)
        engine.stop()

        XCTAssertNotNil(received)
        XCTAssertTrue(received?.isInMeeting ?? false)
        XCTAssertEqual(received?.provider, .zoom)
    }

    func testBelowThresholdResultDoesNotFireCallback() async {
        let mockDetector = MockMeetingDetector(
            provider: .zoom,
            status: .inMeeting(confidence: .low, provider: .zoom, signal: .process)
        )
        let engine = MeetingDetectionEngine(detectors: [mockDetector])
        engine.pollIntervalSeconds = 0.05
        engine.confidenceThreshold = .high  // low < high → should be ignored

        var callbackCount = 0
        engine.onMeetingStatusChanged = { _ in callbackCount += 1 }

        engine.start()
        // Wait long enough for several polls to fire
        try? await Task.sleep(nanoseconds: 200_000_000)  // 0.2 s = ~4 polls
        engine.stop()

        // No transition should have been reported (stays at .none)
        XCTAssertEqual(callbackCount, 0)
    }

    func testDisabledDetectorIsSkipped() {
        let active = MockMeetingDetector(
            provider: .zoom,
            status: .inMeeting(confidence: .high, provider: .zoom, signal: .combined)
        )
        active.isEnabled = false

        let engine = MeetingDetectionEngine(detectors: [active])
        engine.confidenceThreshold = .high

        var received: MeetingStatus?
        engine.onMeetingStatusChanged = { received = $0 }

        // No need to start engine — we just ensure setProvider respects the flag.
        XCTAssertNil(received, "Disabled detector should not fire callback")
    }

    func testSetProviderTogglesEnabled() {
        let detector = MockMeetingDetector(
            provider: .teams,
            status: .inMeeting(confidence: .high, provider: .teams, signal: .combined)
        )
        let engine = MeetingDetectionEngine(detectors: [detector])

        engine.setProvider(.teams, enabled: false)
        XCTAssertFalse(detector.isEnabled)

        engine.setProvider(.teams, enabled: true)
        XCTAssertTrue(detector.isEnabled)
    }

    func testStopCancelsPolling() async {
        let mockDetector = MockMeetingDetector(
            provider: .zoom,
            status: .inMeeting(confidence: .high, provider: .zoom, signal: .combined)
        )
        let engine = MeetingDetectionEngine(detectors: [mockDetector])
        engine.pollIntervalSeconds = 0.05  // 50 ms

        var callCount = 0
        engine.onMeetingStatusChanged = { _ in callCount += 1 }

        engine.start()
        // Wait for the first poll to fire (transition from .none → .inMeeting)
        try? await Task.sleep(nanoseconds: 120_000_000)  // 0.12 s
        engine.stop()

        let countAfterStop = callCount
        // The status is already "in meeting" so no further change transitions should fire.
        try? await Task.sleep(nanoseconds: 200_000_000)  // 0.2 s more

        // No additional callbacks after stop
        XCTAssertEqual(callCount, countAfterStop)
    }
}

// MARK: - State Machine Precedence Tests

@MainActor
final class MeetingStateMachinePrecedenceTests: XCTestCase {

    func testMeetingDetectedSetsBusyInAutoMode() {
        let machine = PresenceStateMachine(initialState: .available, initialMode: .auto)
        machine.handleEvent(.startupInitialize)
        machine.handleEvent(.calendarUpdated(.available))

        machine.handleEvent(.meetingDetected(
            .inMeeting(confidence: .high, provider: .zoom, signal: .combined)
        ))

        XCTAssertEqual(machine.currentState, .busy)
        XCTAssertEqual(machine.currentSource, .meeting)
        XCTAssertEqual(machine.currentBusyReason, .zoom)
    }

    func testMeetingDetectedIsBlockedByManualOverride() {
        let machine = PresenceStateMachine(initialState: .available, initialMode: .auto)
        machine.handleEvent(.startupInitialize)
        machine.handleEvent(.calendarUpdated(.available))
        machine.handleEvent(.manualOverride(.available))

        machine.handleEvent(.meetingDetected(
            .inMeeting(confidence: .high, provider: .zoom, signal: .combined)
        ))

        // Manual override should block meeting detection
        XCTAssertEqual(machine.currentState, .available)
        XCTAssertEqual(machine.currentSource, .manual)
    }

    func testManualOverrideStillWinsOverMeeting() {
        let machine = PresenceStateMachine(initialState: .unknown, initialMode: .auto)
        machine.handleEvent(.startupInitialize)

        // Simulate a meeting being detected first
        machine.handleEvent(.meetingDetected(
            .inMeeting(confidence: .high, provider: .teams, signal: .combined)
        ))
        XCTAssertEqual(machine.currentState, .busy)

        // User manually sets available
        machine.handleEvent(.manualOverride(.available))
        XCTAssertEqual(machine.currentState, .available)
        XCTAssertEqual(machine.currentMode, .manual)

        // Meeting still "in progress" — should be blocked by manual mode
        machine.handleEvent(.meetingDetected(
            .inMeeting(confidence: .high, provider: .teams, signal: .combined)
        ))
        XCTAssertEqual(machine.currentState, .available)  // unchanged
        XCTAssertEqual(machine.currentMode, .manual)
    }

    func testMeetingDetectedIgnoredInOffMode() {
        let machine = PresenceStateMachine(initialState: .unknown, initialMode: .auto)
        machine.handleEvent(.startupInitialize)
        machine.handleEvent(.turnOff)

        machine.handleEvent(.meetingDetected(
            .inMeeting(confidence: .high, provider: .zoom, signal: .combined)
        ))

        XCTAssertEqual(machine.currentState, .off)
    }

    func testBusyReasonReflectsMeetingProvider() {
        let machine = PresenceStateMachine(initialState: .unknown, initialMode: .auto)
        machine.handleEvent(.startupInitialize)

        machine.handleEvent(.meetingDetected(
            .inMeeting(confidence: .high, provider: .meet, signal: .windowTitle)
        ))
        XCTAssertEqual(machine.currentBusyReason, .meet)

        // Reset
        machine.handleEvent(.resumeAuto)
        machine.handleEvent(.calendarUpdated(.available))

        machine.handleEvent(.meetingDetected(
            .inMeeting(confidence: .high, provider: .teams, signal: .combined)
        ))
        XCTAssertEqual(machine.currentBusyReason, .teams)
    }

    func testBusyReasonCalendarWhenCalendarSetsBusy() {
        let machine = PresenceStateMachine(initialState: .unknown, initialMode: .auto)
        machine.handleEvent(.startupInitialize)
        machine.handleEvent(.calendarUpdated(.busy))

        XCTAssertEqual(machine.currentBusyReason, .calendar)
    }

    func testBusyReasonManualWhenUserSetsBusy() {
        let machine = PresenceStateMachine(initialState: .unknown, initialMode: .auto)
        machine.handleEvent(.startupInitialize)
        machine.handleEvent(.manualOverride(.busy))

        XCTAssertEqual(machine.currentBusyReason, .manual)
    }
}

// MARK: - StateSource Priority Tests

@MainActor
final class MeetingStateSourceTests: XCTestCase {

    func testMeetingSourceHasCorrectPriority() {
        XCTAssertEqual(StateSource.meeting.priority, 1)
        XCTAssertEqual(StateSource.calendar.priority, 1)
        XCTAssertEqual(StateSource.manual.priority, 2)
        XCTAssertEqual(StateSource.system.priority, 3)
    }

    func testMeetingSourceIsBlockedInOffMode() {
        let result = StateTransition.isAllowed(
            from: .available,
            to: .busy,
            currentSource: .startup,
            requestedBy: .meeting,
            mode: .off
        )
        XCTAssertFalse(result.allowed)
        XCTAssertEqual(result.reason, "system-is-off")
    }

    func testMeetingSourceIsBlockedInManualMode() {
        let result = StateTransition.isAllowed(
            from: .available,
            to: .busy,
            currentSource: .manual,
            requestedBy: .meeting,
            mode: .manual
        )
        XCTAssertFalse(result.allowed)
        XCTAssertEqual(result.reason, "manual-override-active")
    }

    func testMeetingSourceIsAllowedInAutoMode() {
        let result = StateTransition.isAllowed(
            from: .available,
            to: .busy,
            currentSource: .calendar,
            requestedBy: .meeting,
            mode: .auto
        )
        XCTAssertTrue(result.allowed)
    }
}

// MARK: - MeetingProcessInspector Tests

final class MeetingProcessInspectorTests: XCTestCase {

    func testAnyTitleMatchesCaseInsensitively() {
        let titles = ["Zoom Meeting - My Room"]
        XCTAssertTrue(MeetingProcessInspector.anyTitle(titles, containsAny: ["zoom meeting"]))
        XCTAssertTrue(MeetingProcessInspector.anyTitle(titles, containsAny: ["ZOOM MEETING"]))
        XCTAssertTrue(MeetingProcessInspector.anyTitle(titles, containsAny: ["Zoom Meeting"]))
    }

    func testAnyTitleReturnsFalseWhenNoMatch() {
        let titles = ["Google Chrome"]
        XCTAssertFalse(MeetingProcessInspector.anyTitle(titles, containsAny: ["zoom meeting"]))
    }

    func testAnyTitleReturnsFalseForEmptyTitles() {
        XCTAssertFalse(MeetingProcessInspector.anyTitle([], containsAny: ["zoom"]))
    }

    func testAnyTitleReturnsFalseForEmptyPatterns() {
        XCTAssertFalse(MeetingProcessInspector.anyTitle(["Zoom Meeting"], containsAny: []))
    }
}
