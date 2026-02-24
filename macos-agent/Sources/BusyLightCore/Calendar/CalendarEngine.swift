import Foundation
import EventKit

/// Orchestrates calendar permission handling, periodic event scanning, and
/// availability resolution.  Consumers receive availability updates through the
/// `onAvailabilityChange` callback.
///
/// Lifecycle:
/// ```
/// let engine = CalendarEngine()
/// engine.onAvailabilityChange = { state in … }
/// await engine.start()
/// // engine fires a scan immediately and then every `scanInterval` seconds.
/// engine.stop()  // call on deinit or scene deactivation
/// ```
///
/// Isolated to `@MainActor` so all EventKit, Timer, and UI-adjacent calls are
/// on the main thread — consistent with `ConfigurationManager` and AppKit.
@MainActor
public final class CalendarEngine {

    // MARK: - Configuration

    /// How often the engine re-scans the calendar (seconds).  Default: 60 s.
    public var scanInterval: TimeInterval = 60

    // MARK: - Outputs

    /// Called on `@MainActor` whenever the resolved `PresenceState` changes.
    public var onAvailabilityChange: (@MainActor (PresenceState) -> Void)?

    /// The most recently resolved presence state.
    public private(set) var currentState: PresenceState = .available

    /// `true` while the engine is running (permission was granted and timer is active).
    public private(set) var isActive: Bool = false

    // MARK: - Dependencies

    private let permissionManager: any CalendarPermissionManaging
    private let scanner: CalendarScanner
    private let resolver: CalendarAvailabilityResolver
    private let logger: Logger

    // MARK: - Internals

    private var scanTimer: Timer?
    private var storeObserver: NSObjectProtocol?
    private var isRunning = false

    // MARK: - Init

    /// Creates an engine wired to the system `EKEventStore`.  Prefer the
    /// dependency-injecting init in tests.
    public convenience init() {
        let store = EKEventStore()
        let scanner = CalendarScanner(store: store)
        // Load enabled calendars from configuration
        scanner.enabledCalendarTitles = ConfigurationManager.shared.getEnabledCalendarTitles()
        self.init(
            permissionManager: CalendarPermissionManager(store: store),
            scanner: scanner,
            resolver: CalendarAvailabilityResolver(),
            logger: calendarLogger
        )
    }

    public init(
        permissionManager: any CalendarPermissionManaging,
        scanner: CalendarScanner,
        resolver: CalendarAvailabilityResolver,
        logger: Logger = calendarLogger
    ) {
        self.permissionManager = permissionManager
        self.scanner = scanner
        self.resolver = resolver
        self.logger = logger
    }

    // MARK: - Lifecycle

    /// Requests calendar permission, executes an immediate scan, then starts
    /// the periodic scan timer.
    ///
    /// Safe to call multiple times — subsequent calls are no-ops while running.
    public func start() async {
        guard !isRunning else { return }

        logger.logEvent("calendar.engine.start",
                        details: ["scan_interval_s": String(Int(scanInterval))])

        do {
            try await permissionManager.requestAccess()
        } catch {
            logger.logError(error, context: "calendar.engine.permission")
            // Remain in current state; let the caller decide whether to retry.
            return
        }

        isRunning = true
        isActive  = true
        
        // Validate calendar filter configuration and log any issues
        scanner.validateCalendarFilter()
        
        await performScan()
        scheduleTimer()
        subscribeToStoreChanges()
    }

    /// Stops the periodic scan timer and removes the store-change observer.
    /// The engine can be restarted with `start()`.
    public func stop() {
        logger.logEvent("calendar.engine.stop")
        scanTimer?.invalidate()
        scanTimer = nil
        if let obs = storeObserver {
            NotificationCenter.default.removeObserver(obs)
            storeObserver = nil
        }
        isRunning = false
        isActive  = false
    }

    /// Immediately re-scans the calendar and fires `onAvailabilityChange` if the
    /// state differs from `currentState`.  Call this after the user returns from
    /// away so the icon snaps back to the current calendar reality.
    ///
    /// Resets `currentState` to `.away` before scanning so that even if the
    /// calendar resolves back to the same state as before (e.g. `.available`),
    /// the callback always fires and the UI is unconditionally updated.
    public func scanNow() async {
        guard isRunning else { return }
        currentState = .away   // force applyState's guard to pass on any resolved state
        scanner.resetStore()
        await performScan()
    }
    
    /// Returns all available calendars as (title, source) pairs for UI display
    public func getAvailableCalendars() -> [(title: String, source: String)] {
        return scanner.getAvailableCalendars()
    }
    
    /// Updates the list of enabled calendar titles and triggers an immediate rescan
    public func setEnabledCalendars(_ titles: [String]) async {
        scanner.enabledCalendarTitles = titles
        ConfigurationManager.shared.setEnabledCalendarTitles(titles)
        logger.logEvent("calendar.filter.updated", details: [
            "enabled_count": String(titles.count),
            "titles": titles.joined(separator: ", ")
        ])
        await scanNow()
    }

    // MARK: - Scanning

    private func performScan() async {
        let scanStart = Date()
        logger.logEvent("calendar.scan.start")
        
        // Force sync with remote calendar servers (Gmail, Outlook, etc.) before scanning
        // This ensures CalDAV/Exchange calendars have the latest events
        scanner.refreshRemoteSources()

        do {
            let events = try scanner.fetchCurrentEvents()
            let resolved = resolver.resolve(events: events, at: Date())

            let durationMs = Int(Date().timeIntervalSince(scanStart) * 1000)
            logger.logEvent("calendar.scan.complete", details: [
                "resolved_state": resolved.rawValue,
                "event_count":    String(events.count),
                "duration_ms":    String(durationMs)
            ])

            applyState(resolved)
        } catch {
            logger.logError(error, context: "calendar.scan")
        }
    }

    private func applyState(_ newState: PresenceState) {
        guard newState != currentState else { return }
        logger.logEvent("calendar.state.changed", details: [
            "from": currentState.rawValue,
            "to":   newState.rawValue
        ])
        currentState = newState
        onAvailabilityChange?(newState)
    }

    private func scheduleTimer() {
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: scanInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                await self?.performScan()
            }
        }
    }

    /// Subscribes to `EKEventStoreChanged` so any calendar edit (add, modify,
    /// delete) triggers an immediate incremental scan without waiting for the
    /// next polling interval.
    private func subscribeToStoreChanges() {
        storeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self, self.isRunning else { return }
                self.logger.logEvent("calendar.store.changed",
                                     details: ["trigger": "EKEventStoreChanged"])
                // Must reset the store cache before fetching so we get fresh data.
                self.scanner.resetStore()
                await self.performScan()
            }
        }
    }
}
