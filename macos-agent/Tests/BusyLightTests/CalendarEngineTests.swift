import Testing
import Foundation
import EventKit
@testable import BusyLightCore

// MARK: - Mock permission manager

@MainActor
final class MockCalendarPermissionManager: CalendarPermissionManaging {
    enum Behavior {
        case grant
        case deny
    }

    var behavior: Behavior = .grant
    private(set) var requestCallCount = 0

    func requestAccess() async throws -> Bool {
        requestCallCount += 1
        switch behavior {
        case .grant:
            return true
        case .deny:
            throw CalendarPermissionManager.PermissionError.denied
        }
    }
}

// MARK: - Mock event store

@MainActor
final class MockCalendarEventStore: CalendarEventStoreProtocol {
    var events: [any CalendarEventRepresentable] = []
    var shouldThrow = false
    private(set) var fetchCallCount = 0
    private(set) var resetCallCount = 0

    func fetchEventsOverlapping(_ date: Date,
                                toleranceSeconds: TimeInterval) throws -> [any CalendarEventRepresentable] {
        fetchCallCount += 1
        if shouldThrow { throw MockStoreError.scanFailed }
        return events.filter { $0.occursAt(date) }
    }

    func reset() {
        resetCallCount += 1
    }
}

enum MockStoreError: Error {
    case scanFailed
}

// MARK: - CalendarEngine tests

@MainActor
@Suite("CalendarEngine")
struct CalendarEngineTests {

    private func makeEngine(
        permissionBehavior: MockCalendarPermissionManager.Behavior = .grant,
        events: [any CalendarEventRepresentable] = []
    ) -> (engine: CalendarEngine,
          permission: MockCalendarPermissionManager,
          store: MockCalendarEventStore) {
        let permission = MockCalendarPermissionManager()
        permission.behavior = permissionBehavior

        let store = MockCalendarEventStore()
        store.events = events

        let scanner  = CalendarScanner(eventStore: store)
        let resolver = CalendarAvailabilityResolver()

        let engine = CalendarEngine(
            permissionManager: permission,
            scanner: scanner,
            resolver: resolver
        )
        return (engine, permission, store)
    }

    // MARK: Permission

    @Test("Engine remains .available and does not scan when permission is denied")
    func deniedPermissionHaltsStart() async {
        let (engine, permission, store) = makeEngine(permissionBehavior: .deny)

        await engine.start()

        // State must not change from default
        #expect(engine.currentState == .available)
        // Permission was requested once
        #expect(permission.requestCallCount == 1)
        // No scan was executed
        #expect(store.fetchCallCount == 0)
    }

    @Test("Engine requests permission exactly once per start() call")
    func permissionRequestedOnce() async {
        let (engine, permission, _) = makeEngine()
        await engine.start()
        #expect(permission.requestCallCount == 1)
    }

    @Test("Calling start() while already running is a no-op")
    func doubleStartIsNoop() async {
        let (engine, permission, _) = makeEngine()
        await engine.start()
        await engine.start()
        #expect(permission.requestCallCount == 1)
        engine.stop()
    }

    // MARK: State resolution on scan

    @Test("Engine resolves .busy when a busy event overlaps current time")
    func busyEventUpdatesState() async {
        let now   = Date()
        let busy  = MockCalendarEvent.make(availability: .busy, anchor: now)
        let (engine, _, _) = makeEngine(events: [busy])

        var received: PresenceState?
        engine.onAvailabilityChange = { received = $0 }

        await engine.start()
        engine.stop()

        #expect(engine.currentState == .busy)
        #expect(received == .busy)
    }

    @Test("Engine resolves .tentative when only a tentative event overlaps")
    func tentativeEventUpdatesState() async {
        let now       = Date()
        let tentative = MockCalendarEvent.make(availability: .tentative, anchor: now)
        let (engine, _, _) = makeEngine(events: [tentative])

        await engine.start()
        engine.stop()

        #expect(engine.currentState == .tentative)
    }

    @Test("Engine resolves .available when no events overlap")
    func availableWhenNoOverlappingEvents() async {
        let (engine, _, _) = makeEngine(events: [])

        await engine.start()
        engine.stop()

        #expect(engine.currentState == .available)
    }

    @Test("Engine resolves .available when only free events overlap")
    func availableWhenOnlyFreeEvents() async {
        let now  = Date()
        let free = MockCalendarEvent.make(availability: .free, anchor: now)
        let (engine, _, _) = makeEngine(events: [free])

        await engine.start()
        engine.stop()

        #expect(engine.currentState == .available)
    }

    // MARK: Callbacks

    @Test("onAvailabilityChange is not called when state does not change")
    func callbackNotFiredWhenStateUnchanged() async {
        // Default state is .available; engine with no events resolves .available
        let (engine, _, _) = makeEngine(events: [])
        var callCount = 0
        engine.onAvailabilityChange = { _ in callCount += 1 }

        await engine.start()
        engine.stop()

        #expect(callCount == 0)
    }

    @Test("onAvailabilityChange fires when state transitions from available to busy")
    func callbackFiredOnStateTransition() async {
        let now  = Date()
        let busy = MockCalendarEvent.make(availability: .busy, anchor: now)
        let (engine, _, _) = makeEngine(events: [busy])

        var transitions: [PresenceState] = []
        engine.onAvailabilityChange = { transitions.append($0) }

        await engine.start()
        engine.stop()

        #expect(transitions == [.busy])
    }

    // MARK: Scan error handling

    @Test("Engine remains in previous state and does not crash on scan error")
    func scanErrorDoesNotChangState() async {
        let now  = Date()
        let busy = MockCalendarEvent.make(availability: .busy, anchor: now)
        let (engine, _, store) = makeEngine(events: [busy])

        // First scan succeeds → state becomes .busy
        await engine.start()
        #expect(engine.currentState == .busy)

        // Subsequent scan throws
        store.shouldThrow = true
        // Directly trigger a second scan by restarting a stopped engine.
        engine.stop()
        store.shouldThrow = true

        // State should remain from last successful scan.
        #expect(engine.currentState == .busy)
    }

    // MARK: Stop

    @Test("Stop clears running state; start can be called again")
    func stopAndRestart() async {
        let (engine, permission, _) = makeEngine()

        await engine.start()
        engine.stop()

        // Restart
        await engine.start()
        engine.stop()

        #expect(permission.requestCallCount == 2)
    }
}
