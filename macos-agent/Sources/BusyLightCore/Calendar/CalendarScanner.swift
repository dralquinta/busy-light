import Foundation
import EventKit

// MARK: - Abstraction for testability

/// Protocol wrapping the subset of `EKEventStore` used by `CalendarScanner`.
/// Conforming types must be `@MainActor`-isolated because EventKit requires
/// consistent thread access.
@MainActor
public protocol CalendarEventStoreProtocol: AnyObject {
    /// Fetch all events whose [start, end) window overlaps `date`.
    ///
    /// The implementation should query a window of at least
    /// `toleranceSeconds` on each side of `date` and then return only
    /// events that actually contain `date` within their interval.
    func fetchEventsOverlapping(_ date: Date,
                                toleranceSeconds: TimeInterval) throws -> [any CalendarEventRepresentable]

    /// Flush the store's in-memory cache so the next fetch reads fresh data.
    /// Must be called after receiving `EKEventStoreChanged`.
    func reset()
}

// MARK: - Production store wrapper

/// `EKEventStore`-backed implementation of `CalendarEventStoreProtocol`.
@MainActor
final class LiveCalendarEventStore: CalendarEventStoreProtocol {

    private let store: EKEventStore

    init(store: EKEventStore = EKEventStore()) {
        self.store = store
    }

    func fetchEventsOverlapping(_ date: Date,
                                toleranceSeconds: TimeInterval) throws -> [any CalendarEventRepresentable] {
        let windowStart = date.addingTimeInterval(-toleranceSeconds)
        let windowEnd   = date.addingTimeInterval(toleranceSeconds)

        let predicate = store.predicateForEvents(
            withStart: windowStart,
            end: windowEnd,
            calendars: nil          // all calendars; scoped filtering can be added later
        )

        return store.events(matching: predicate)
            .map { EKEventWrapper($0) }
            .filter { $0.occursAt(date) }
    }

    func reset() {
        store.reset()
    }
}

// MARK: - Scanner

/// Fetches calendar events that overlap the current moment.
///
/// Isolated to `@MainActor` to keep all EventKit calls on the main actor,
/// consistent with the rest of this project's architecture.
@MainActor
public final class CalendarScanner {

    // MARK: - Configuration

    /// Width of the half-window used when querying events.
    /// Events must still intersect `now` exactly to be returned, but EventKit
    /// requires a date range for its predicate, not a point query.
    /// Default is 12 hours so that all-day and multi-day events are captured.
    public var queryToleranceSeconds: TimeInterval = 12 * 3600

    // MARK: - Properties

    private let eventStore: any CalendarEventStoreProtocol
    private let logger: Logger

    // MARK: - Init

    public init(
        eventStore: any CalendarEventStoreProtocol,
        logger: Logger = calendarLogger
    ) {
        self.eventStore = eventStore
        self.logger = logger
    }

    /// Convenience init that creates a `LiveCalendarEventStore` backed by a
    /// real `EKEventStore`.  Prefer the injectable init in tests.
    public convenience init(store: EKEventStore = EKEventStore(),
                            logger: Logger = calendarLogger) {
        self.init(eventStore: LiveCalendarEventStore(store: store), logger: logger)
    }

    // MARK: - Public API

    /// Resets the underlying event store cache.  Call this after `EKEventStoreChanged`
    /// so the next `fetchCurrentEvents()` reads fresh data from disk.
    public func resetStore() {
        eventStore.reset()
    }

    /// Returns all events that overlap `date` (defaults to `Date()` = now).
    ///
    /// - Parameter date: The point-in-time to test.  Defaults to the current date.
    /// - Returns: Events whose `[startDate, endDate)` interval contains `date`.
    /// - Throws: Any error thrown by the underlying event store.
    public func fetchCurrentEvents(at date: Date = Date()) throws -> [any CalendarEventRepresentable] {
        let start = Date()
        logger.logEvent("calendar.scan.execute", details: ["query_date": ISO8601DateFormatter().string(from: date)])

        let events = try eventStore.fetchEventsOverlapping(date, toleranceSeconds: queryToleranceSeconds)

        let durationMs = Int(Date().timeIntervalSince(start) * 1000)
        logger.logEvent("calendar.scan.result", details: [
            "event_count": String(events.count),
            "duration_ms": String(durationMs)
        ])

        return events
    }
}
