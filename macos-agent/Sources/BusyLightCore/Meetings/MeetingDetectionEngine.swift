import Foundation

/// Orchestrates multiple `MeetingDetectorProtocol` implementations, polls them
/// on a configurable interval, applies a confidence threshold, and fires a
/// callback whenever the aggregate meeting status changes.
///
/// **Thread Safety:** `@MainActor` isolated — all state updates and callbacks
/// run on the main thread, consistent with the rest of the BusyLight agent.
@MainActor
public final class MeetingDetectionEngine {

    // MARK: - Configuration

    /// How often the detectors are polled (seconds). Default: 3 s.
    public var pollIntervalSeconds: Double = 3.0

    /// Minimum confidence required to report a meeting as active.
    /// Results below this threshold are treated as `.none`. Default: `.high`.
    public var confidenceThreshold: MeetingConfidence = .high

    // MARK: - Callback

    /// Called on the main thread whenever the aggregate `MeetingStatus` transitions
    /// between `.none` and `.inMeeting(…)` (or between providers).
    public var onMeetingStatusChanged: (@MainActor (MeetingStatus) -> Void)?

    // MARK: - Internal State

    private var detectors: [any MeetingDetectorProtocol]
    private var pollingTask: Task<Void, Never>?
    private var lastReportedStatus: MeetingStatus = .none
    private var suppressUntil: Date?
    private let logger: Logger

    // MARK: - Init

    public init(
        detectors: [any MeetingDetectorProtocol] = MeetingDetectionEngine.defaultDetectors(),
        logger: Logger = meetingLogger
    ) {
        self.detectors = detectors
        self.logger = logger
    }

    // MARK: - Lifecycle

    /// Starts the background polling loop.
    /// Safe to call multiple times — a second call is ignored while already running.
    public func start() {
        guard pollingTask == nil else { return }

        logger.logEvent("meeting.detection.engine.started", details: [
            "providers": detectors.map { $0.provider.rawValue }.joined(separator: ","),
            "pollIntervalSeconds": String(pollIntervalSeconds),
            "confidenceThreshold": confidenceThreshold.displayName,
        ])

        pollingTask = Task { [weak self, pollIntervalSeconds] in
            while !Task.isCancelled {
                await MainActor.run { [weak self] in self?.poll() }
                try? await Task.sleep(
                    nanoseconds: UInt64(pollIntervalSeconds * 1_000_000_000)
                )
            }
        }
    }

    /// Stops the polling loop and releases the background task.
    public func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        logger.logEvent("meeting.detection.engine.stopped")
    }

    // MARK: - Provider Control

    /// Enables or disables the detector for a specific `MeetingProvider`.
    public func setProvider(_ provider: MeetingProvider, enabled: Bool) {
        for detector in detectors where detector.provider == provider {
            detector.isEnabled = enabled
        }
        logger.logEvent("meeting.provider.enabled.changed", details: [
            "provider": provider.rawValue,
            "enabled": String(enabled),
        ])
    }
    
    /// Clears the current meeting status and suppresses detection for a brief period.
    /// This is useful when resuming calendar control - it prevents stale meeting
    /// detections (like a lingering Google Meet tab) from overriding calendar state.
    public func clearAndSuppressFor(seconds: Double) {
        suppressUntil = Date().addingTimeInterval(seconds)
        lastReportedStatus = .none
        logger.logEvent("meeting.detection.suppressed", details: [
            "duration_seconds": String(seconds)
        ])
        // Notify immediately that we're clearing the meeting status
        onMeetingStatusChanged?(.none)
    }

    // MARK: - Detection Poll

    private func poll() {
        // Check if we're in suppression period
        if let suppressUntil = suppressUntil {
            if Date() < suppressUntil {
                // Still suppressed, skip this poll
                return
            } else {
                // Suppression period ended
                self.suppressUntil = nil
                logger.logEvent("meeting.detection.suppression_ended")
            }
        }
        
        var bestResult: MeetingDetectionResult?

        for detector in detectors where detector.isEnabled {
            let result = detector.detect()
            logger.logEvent("meeting.detector.polled", details: [
                "provider": result.provider.rawValue,
                "confidence": result.status.confidence.displayName,
                "inMeeting": String(result.status.isInMeeting),
            ])

            if result.status.confidence > (bestResult?.status.confidence ?? .none) {
                bestResult = result
            }
        }

        // Apply threshold — anything below counts as "none".
        let aggregated: MeetingStatus
        if let best = bestResult, best.status.confidence >= confidenceThreshold {
            aggregated = best.status
        } else {
            aggregated = .none
        }

        // Debounce: only notify if status actually changed.
        guard !isSameStatus(aggregated, lastReportedStatus) else { return }

        let previous = lastReportedStatus
        lastReportedStatus = aggregated

        logger.logEvent("meeting.status.changed", details: [
            "from": statusDescription(previous),
            "to": statusDescription(aggregated),
            "provider": aggregated.provider?.rawValue ?? "none",
            "confidence": aggregated.confidence.displayName,
        ])

        onMeetingStatusChanged?(aggregated)
    }

    // MARK: - Helpers

    private func isSameStatus(_ a: MeetingStatus, _ b: MeetingStatus) -> Bool {
        switch (a, b) {
        case (.none, .none): return true
        case (.inMeeting(let ca, let pa, _), .inMeeting(let cb, let pb, _)):
            return ca == cb && pa == pb
        default: return false
        }
    }

    private func statusDescription(_ status: MeetingStatus) -> String {
        switch status {
        case .none: return "none"
        case .inMeeting(let c, let p, _):
            return "inMeeting(provider=\(p.rawValue),confidence=\(c.displayName))"
        }
    }

    // MARK: - Default Detectors

    /// Returns the standard set of detectors covering all supported providers.
    public static func defaultDetectors() -> [any MeetingDetectorProtocol] {
        [
            ZoomDetector(),
            TeamsDetector(),
            BrowserMeetingDetector(provider: .meet),
            BrowserMeetingDetector(provider: .teams),
            BrowserMeetingDetector(provider: .zoom),
        ]
    }
}
