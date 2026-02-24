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
    ///
    /// - Parameter enabledCalendarTitles: If not empty, only include events from calendars
    ///   whose titles match these strings. If empty, include all calendars.
    func fetchEventsOverlapping(_ date: Date,
                                toleranceSeconds: TimeInterval,
                                enabledCalendarTitles: [String]) throws -> [any CalendarEventRepresentable]

    /// Flush the store's in-memory cache so the next fetch reads fresh data.
    /// Must be called after receiving `EKEventStoreChanged`.
    func reset()

    /// Returns a list of all calendars visible to EventKit as (title, source) pairs.
    /// Used for diagnostics only — e.g. to confirm Google/Outlook accounts are synced.
    func availableCalendarNames() -> [(title: String, source: String)]
}

// Default implementation so existing mocks don't need to conform.
extension CalendarEventStoreProtocol {
    func availableCalendarNames() -> [(title: String, source: String)] { [] }
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
                                toleranceSeconds: TimeInterval,
                                enabledCalendarTitles: [String]) throws -> [any CalendarEventRepresentable] {
        let windowStart = date.addingTimeInterval(-toleranceSeconds)
        let windowEnd   = date.addingTimeInterval(toleranceSeconds)

        // Filter calendars if enabledCalendarTitles is not empty
        let calendarsToQuery: [EKCalendar]?
        if !enabledCalendarTitles.isEmpty {
            let allCalendars = store.calendars(for: .event)
            calendarsToQuery = allCalendars.filter { enabledCalendarTitles.contains($0.title) }
        } else {
            calendarsToQuery = nil  // nil means all calendars
        }

        let predicate = store.predicateForEvents(
            withStart: windowStart,
            end: windowEnd,
            calendars: calendarsToQuery
        )

        return store.events(matching: predicate)
            .map { EKEventWrapper($0) }
            .filter { $0.occursAt(date) }
    }

    func reset() {
        store.reset()
    }

    func availableCalendarNames() -> [(title: String, source: String)] {
        store.calendars(for: .event).map { ($0.title, $0.source.title) }
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
    
    /// List of calendar titles to include. If empty, all calendars are included.
    public var enabledCalendarTitles: [String] = []

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

        let events = try eventStore.fetchEventsOverlapping(date, 
                                                           toleranceSeconds: queryToleranceSeconds,
                                                           enabledCalendarTitles: enabledCalendarTitles)

        let durationMs = Int(Date().timeIntervalSince(start) * 1000)
        logger.logEvent("calendar.scan.result", details: [
            "event_count": String(events.count),
            "duration_ms": String(durationMs)
        ])

        // Log each overlapping event's availability so misconfigured external
        // calendars (Google CalDAV, Outlook Exchange) can be diagnosed.
        for event in events {
            logger.logEvent("calendar.event.found", details: [
                "title":        event.title ?? "(untitled)",
                "availability": availabilityLabel(event.availability),
                "start":        ISO8601DateFormatter().string(from: event.startDate),
                "end":          ISO8601DateFormatter().string(from: event.endDate)
            ])
        }

        // When nothing is found, log every visible calendar so sync issues are
        // immediately diagnosable ("is my Google account even registered?").
        if events.isEmpty {
            let calendars = eventStore.availableCalendarNames()
            if calendars.isEmpty {
                logger.logEvent("calendar.diagnostic.no_calendars",
                                details: ["hint": "No EK calendars found — check System Settings → Internet Accounts"])
            } else {
                for (title, source) in calendars {
                    logger.logEvent("calendar.diagnostic.visible_calendar",
                                    details: ["calendar": title, "account": source])
                }
            }
        }

        return events
    }

    /// Returns all available calendars as (title, source) pairs for UI display
    public func getAvailableCalendars() -> [(title: String, source: String)] {
        return eventStore.availableCalendarNames()
    }

    // MARK: - Helpers

    private func availabilityLabel(_ av: EKEventAvailability) -> String {
        switch av {
        case .busy:         return "busy"
        case .free:         return "free"
        case .tentative:    return "tentative"
        case .unavailable:  return "unavailable"
        case .notSupported: return "notSupported"
        @unknown default:   return "unknown(\(av.rawValue))"
        }
    }
}
