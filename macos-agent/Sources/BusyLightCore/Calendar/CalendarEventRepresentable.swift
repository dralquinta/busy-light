import Foundation
import EventKit

/// An abstraction over `EKEvent` that exposes only the fields required by the
/// calendar availability engine. This protocol enables full unit-test coverage
/// without instantiating real `EKEventStore` / `EKEvent` objects.
public protocol CalendarEventRepresentable {
    /// Stable identifier for the underlying event.
    /// `nil` for events that have not yet been saved to the store.
    var eventIdentifier: String? { get }
    /// Human-readable event title (may be nil for untitled events).
    var title: String? { get }
    /// Inclusive start time of the event.
    var startDate: Date! { get }
    /// Exclusive end time of the event. For all-day events this is midnight on
    /// the following calendar day.
    var endDate: Date! { get }
    /// Whether this is an all-day event.
    var isAllDay: Bool { get }
    /// The user's declared availability for this event slot.
    var availability: EKEventAvailability { get }
}

public extension CalendarEventRepresentable {
    /// Returns `true` when the event's [startDate, endDate) window contains `date`.
    func occursAt(_ date: Date) -> Bool {
        guard let start = startDate, let end = endDate else { return false }
        return start <= date && date < end
    }
}

// MARK: - EKEvent wrapper (production use)

/// Value-type wrapper that bridges `EKEvent` to `CalendarEventRepresentable`.
/// Using a wrapper avoids `null_unspecified` (IUO) vs `Optional` type-system
/// mismatches that prevent a direct `EKEvent: CalendarEventRepresentable`
/// conformance under Swift 6 strict concurrency.
public struct EKEventWrapper: CalendarEventRepresentable, Sendable {
    public let eventIdentifier: String?
    public let title: String?
    public let startDate: Date!
    public let endDate: Date!
    public let isAllDay: Bool
    public let availability: EKEventAvailability

    public init(_ event: EKEvent) {
        self.eventIdentifier = event.eventIdentifier
        self.title           = event.title
        self.startDate       = event.startDate
        self.endDate         = event.endDate
        self.isAllDay        = event.isAllDay
        self.availability    = event.availability
    }
}
