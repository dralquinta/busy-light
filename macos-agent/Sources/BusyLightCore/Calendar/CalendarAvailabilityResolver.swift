import Foundation
import EventKit

/// Pure-logic resolver: maps a collection of calendar events that overlap
/// the current moment into a `PresenceState`.
///
/// Priority (highest → lowest):
/// 1. **busy** — at least one event with `.busy` or `.unavailable` availability
/// 2. **tentative** — at least one event with `.tentative` availability; no busy events
/// 3. **available** — no overlapping events, or all overlapping events are `.free`
///
/// The resolver contains no side-effects and can be tested in isolation.
public struct CalendarAvailabilityResolver {

    public init() {}

    // MARK: - Public API

    /// Resolve the availability state from a pre-filtered list of events.
    ///
    /// - Parameters:
    ///   - events: Events that **already** overlap the evaluation `date`.
    ///             (The caller—`CalendarScanner`—is responsible for
    ///             filtering events to the current moment.)
    ///   - date:   Reference timestamp used for `occursAt` final check as a
    ///             safety guard.  Pass `Date()` for real-time resolution.
    /// - Returns: The resolved `PresenceState`.
    public func resolve(events: [any CalendarEventRepresentable],
                        at date: Date = Date()) -> PresenceState {
        // Safety guard: ensure we only consider events that genuinely overlap `date`.
        let overlapping = events.filter { $0.occursAt(date) }

        guard !overlapping.isEmpty else {
            return .available
        }

        var hasBusy       = false
        var hasTentative  = false

        for event in overlapping {
            switch event.availability {
            case .busy, .unavailable:
                hasBusy = true
            case .tentative:
                hasTentative = true
            case .free, .notSupported:
                break   // does not affect availability
            @unknown default:
                break
            }
        }

        if hasBusy       { return .busy }
        if hasTentative  { return .tentative }
        return .available
    }

    /// Convenience overload that evaluates against `Date()`.
    public func resolveNow(events: [any CalendarEventRepresentable]) -> PresenceState {
        resolve(events: events, at: Date())
    }
}
