import Foundation
import AppKit

/// Monitors macOS system events that signal the user is away from the keyboard
/// and calls back when presence should switch to `.away` or resume.
///
/// **Triggers for `.away`:**
/// - Screen lock (`NSWorkspace.screensDidLockNotification`)
/// - System sleep / display sleep (`NSWorkspace.willSleepNotification`)
///
/// **Triggers to resume:**
/// - Screen unlock (`NSWorkspace.screensDidUnlockNotification`)
/// - System wake (`NSWorkspace.didWakeNotification`)
///
/// Isolated to `@MainActor` — all `NSWorkspace` notification callbacks and
/// the public API are consumed on the main thread.
@MainActor
public final class SystemPresenceMonitor {

    // MARK: - Callbacks

    /// Called when the user goes away (screen locked / system sleeping).
    public var onUserAway: (@MainActor () -> Void)?

    /// Called when the user returns (screen unlocked / system woke).
    public var onUserReturned: (@MainActor () -> Void)?

    // MARK: - Internals

    private var observers: [NSObjectProtocol] = []
    private let logger: Logger
    private var isAwake = true

    // MARK: - Init

    public init(logger: Logger = lifecycleLogger) {
        self.logger = logger
    }

    // MARK: - Lifecycle

    /// Begins observing system events.  Safe to call multiple times — the
    /// existing observers are removed before new ones are registered.
    public func start() {
        stop()

        let ws  = NSWorkspace.shared.notificationCenter
        let dnc = DistributedNotificationCenter.default()

        // Screen lock / unlock are posted to DistributedNotificationCenter.
        let lockName   = NSNotification.Name("com.apple.screenIsLocked")
        let unlockName = NSNotification.Name("com.apple.screenIsUnlocked")

        // System sleep / wake come through the workspace notification center.
        observers.append(
            ws.addObserver(forName: NSWorkspace.willSleepNotification,
                           object: nil, queue: .main) { [weak self] note in
                let trigger = note.name.rawValue
                Task { @MainActor [weak self] in self?.handleAway(trigger: trigger) }
            }
        )
        observers.append(
            ws.addObserver(forName: NSWorkspace.didWakeNotification,
                           object: nil, queue: .main) { [weak self] note in
                let trigger = note.name.rawValue
                Task { @MainActor [weak self] in self?.handleReturn(trigger: trigger) }
            }
        )
        observers.append(
            dnc.addObserver(forName: lockName, object: nil, queue: .main) { [weak self] note in
                let trigger = note.name.rawValue
                Task { @MainActor [weak self] in self?.handleAway(trigger: trigger) }
            }
        )
        observers.append(
            dnc.addObserver(forName: unlockName, object: nil, queue: .main) { [weak self] note in
                let trigger = note.name.rawValue
                Task { @MainActor [weak self] in self?.handleReturn(trigger: trigger) }
            }
        )

        logger.logEvent("system.presence.monitor.started")
    }

    /// Stops observing and removes all registered observers.
    public func stop() {
        let ws  = NSWorkspace.shared.notificationCenter
        let dnc = DistributedNotificationCenter.default()

        for obs in observers {
            // Try both notification centers — removeObserver is safe to call on
            // the wrong center (it simply does nothing).
            ws.removeObserver(obs)
            dnc.removeObserver(obs)
        }
        observers.removeAll()
        logger.logEvent("system.presence.monitor.stopped")
    }

    // MARK: - Handlers

    private func handleAway(trigger: String) {
        guard isAwake else { return }   // de-duplicate sleep → lock sequences
        isAwake = false
        logger.logEvent("system.presence.away", details: ["trigger": trigger])
        onUserAway?()
    }

    private func handleReturn(trigger: String) {
        guard !isAwake else { return }  // de-duplicate wake → unlock sequences
        isAwake = true
        logger.logEvent("system.presence.returned", details: ["trigger": trigger])
        onUserReturned?()
    }
}
