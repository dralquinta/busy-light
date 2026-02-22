import Testing
import Foundation
import EventKit
@testable import BusyLightCore

// MARK: - Mock calendar event

/// A value-type mock that implements `CalendarEventRepresentable`.
/// Use `MockCalendarEvent.make(…)` factory helpers to keep tests concise.
struct MockCalendarEvent: CalendarEventRepresentable {
    var eventIdentifier: String?
    var title: String?
    var startDate: Date!
    var endDate: Date!
    var isAllDay: Bool
    var availability: EKEventAvailability

    /// Creates an event that spans from `minutesBeforeNow` to `minutesAfterNow`
    /// relative to `anchor` (default: `Date()`).
    static func make(
        id: String = UUID().uuidString,
        title: String? = nil,
        minutesBeforeNow: Double = 15,
        minutesAfterNow: Double = 15,
        availability: EKEventAvailability = .busy,
        anchor: Date = Date(),
        isAllDay: Bool = false
    ) -> MockCalendarEvent {
        MockCalendarEvent(
            eventIdentifier: id,
            title: title,
            startDate: anchor.addingTimeInterval(-minutesBeforeNow * 60),
            endDate: anchor.addingTimeInterval(minutesAfterNow * 60),
            isAllDay: isAllDay,
            availability: availability
        )
    }

    /// Creates an event that does NOT overlap `anchor`.
    static func makeNonOverlapping(
        availability: EKEventAvailability = .busy,
        anchor: Date = Date()
    ) -> MockCalendarEvent {
        let pastEnd = anchor.addingTimeInterval(-60)   // ended 1 minute ago
        return MockCalendarEvent(
            eventIdentifier: UUID().uuidString,
            title: "Past event",
            startDate: pastEnd.addingTimeInterval(-3600),
            endDate: pastEnd,
            isAllDay: false,
            availability: availability
        )
    }
}

// MARK: - CalendarAvailabilityResolver tests

@Suite("CalendarAvailabilityResolver")
struct CalendarAvailabilityResolverTests {

    private let resolver = CalendarAvailabilityResolver()
    private let now = Date()

    // MARK: Basic state detection

    @Test("Returns .available when no events overlap the evaluation date")
    func availableWhenNoEvents() {
        let state = resolver.resolve(events: [], at: now)
        #expect(state == .available)
    }

    @Test("Returns .available when only free events overlap")
    func availableWhenOnlyFreeEvents() {
        let free = MockCalendarEvent.make(availability: .free, anchor: now)
        let state = resolver.resolve(events: [free], at: now)
        #expect(state == .available)
    }

    @Test("Returns .busy when a busy event overlaps")
    func busyWhenBusyEventOverlaps() {
        let busy = MockCalendarEvent.make(availability: .busy, anchor: now)
        let state = resolver.resolve(events: [busy], at: now)
        #expect(state == .busy)
    }

    @Test("Returns .busy when an unavailable event overlaps")
    func busyWhenUnavailableEventOverlaps() {
        let unavailable = MockCalendarEvent.make(availability: .unavailable, anchor: now)
        let state = resolver.resolve(events: [unavailable], at: now)
        #expect(state == .busy)
    }

    @Test("Returns .tentative when only a tentative event overlaps")
    func tentativeWhenTentativeEventOverlaps() {
        let tentative = MockCalendarEvent.make(availability: .tentative, anchor: now)
        let state = resolver.resolve(events: [tentative], at: now)
        #expect(state == .tentative)
    }

    // MARK: Priority resolution

    @Test("busy takes priority over tentative")
    func busyTakesPriorityOverTentative() {
        let busy      = MockCalendarEvent.make(availability: .busy,      anchor: now)
        let tentative = MockCalendarEvent.make(availability: .tentative, anchor: now)
        let state = resolver.resolve(events: [tentative, busy], at: now)
        #expect(state == .busy)
    }

    @Test("busy takes priority over free")
    func busyTakesPriorityOverFree() {
        let busy = MockCalendarEvent.make(availability: .busy, anchor: now)
        let free = MockCalendarEvent.make(availability: .free, anchor: now)
        let state = resolver.resolve(events: [free, busy], at: now)
        #expect(state == .busy)
    }

    @Test("tentative takes priority over free")
    func tentativeTakesPriorityOverFree() {
        let tentative = MockCalendarEvent.make(availability: .tentative, anchor: now)
        let free      = MockCalendarEvent.make(availability: .free,      anchor: now)
        let state = resolver.resolve(events: [free, tentative], at: now)
        #expect(state == .tentative)
    }

    @Test("Resolution is deterministic regardless of event ordering")
    func deterministic() {
        let busy      = MockCalendarEvent.make(availability: .busy,      anchor: now)
        let tentative = MockCalendarEvent.make(availability: .tentative, anchor: now)
        let free      = MockCalendarEvent.make(availability: .free,      anchor: now)

        let result1 = resolver.resolve(events: [busy, tentative, free], at: now)
        let result2 = resolver.resolve(events: [free, tentative, busy], at: now)
        let result3 = resolver.resolve(events: [tentative, free, busy], at: now)

        #expect(result1 == result2)
        #expect(result2 == result3)
        #expect(result1 == .busy)
    }

    // MARK: Event filtering

    @Test("Non-overlapping events are ignored")
    func nonOverlappingEventsAreIgnored() {
        let past  = MockCalendarEvent.makeNonOverlapping(availability: .busy,      anchor: now)
        let free  = MockCalendarEvent.make(             availability: .free,      anchor: now)
        let state = resolver.resolve(events: [past, free], at: now)
        #expect(state == .available)
    }

    @Test("Mix of overlapping and non-overlapping events: only overlapping ones count")
    func onlyOverlappingEventsMatter() {
        let nonOverlapping = MockCalendarEvent.makeNonOverlapping(availability: .busy, anchor: now)
        let overlapping    = MockCalendarEvent.make(availability: .tentative,           anchor: now)
        let state = resolver.resolve(events: [nonOverlapping, overlapping], at: now)
        #expect(state == .tentative)
    }

    // MARK: Edge cases

    @Test("Returns .available for an event that ends exactly at the evaluation date")
    func noOverlapWhenEventEndsAtEvalDate() {
        // endDate == now → the half-open interval [start, end) excludes `now`
        let event = MockCalendarEvent(
            eventIdentifier: "edge",
            title: "edge",
            startDate: now.addingTimeInterval(-3600),
            endDate: now,           // ends exactly at now
            isAllDay: false,
            availability: .busy
        )
        let state = resolver.resolve(events: [event], at: now)
        #expect(state == .available)
    }

    @Test("Returns .busy for an event that starts exactly at the evaluation date")
    func busyWhenEventStartsAtEvalDate() {
        let event = MockCalendarEvent(
            eventIdentifier: "start-edge",
            title: "start-edge",
            startDate: now,
            endDate: now.addingTimeInterval(3600),
            isAllDay: false,
            availability: .busy
        )
        let state = resolver.resolve(events: [event], at: now)
        #expect(state == .busy)
    }

    @Test(".notSupported availability (Google CalDAV / Outlook Exchange) resolves to busy")
    func notSupportedAvailabilityIsBusy() {
        let ns = MockCalendarEvent.make(availability: .notSupported, anchor: now)
        let state = resolver.resolve(events: [ns], at: now)
        #expect(state == .busy)
    }
}
