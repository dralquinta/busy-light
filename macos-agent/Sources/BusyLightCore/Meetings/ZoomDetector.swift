import AppKit
import ApplicationServices

/// Detects an active Zoom meeting running in the native Zoom desktop application.
///
/// **Detection strategy (multi-signal, privacy-safe):**
/// 1. Process detection — checks whether `zoom.us` or `Zoom` is in the running
///    application list. No permission required.
/// 2. Window-title inspection — uses the Accessibility API to read the titles of
///    Zoom's open windows and matches them against known meeting-related patterns.
///    Requires the macOS Accessibility permission (already requested by BusyLight).
///
/// **Confidence mapping:**
/// - Process running **and** meeting window detected → `.high` (signal: `.combined`)
/// - Process running, no meeting window found → `.low` (signal: `.process`)
/// - Process not running → `.none`
public final class ZoomDetector: MeetingDetectorProtocol, @unchecked Sendable {

    public let provider: MeetingProvider = .zoom
    public var isEnabled: Bool

    // MARK: - Patterns

    private static let processNames: Set<String> = ["zoom.us", "Zoom"]

    private static let bundleIdentifiers: Set<String> = ["us.zoom.xos"]

    /// Window-title substrings that indicate a Zoom meeting is active.
    private static let meetingTitlePatterns: [String] = [
        "Zoom Meeting",
        "Zoom Webinar",
        "zoom meeting",
    ]

    // MARK: - Init

    public init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }

    // MARK: - MeetingDetectorProtocol

    public func detect() -> MeetingDetectionResult {
        guard isEnabled else {
            return MeetingDetectionResult(provider: provider, status: .none)
        }

        guard let app = MeetingProcessInspector.findRunningApp(
            processNames: Self.processNames,
            bundleIdentifiers: Self.bundleIdentifiers
        ) else {
            return MeetingDetectionResult(provider: provider, status: .none)
        }

        // Zoom is running — try window-title inspection for higher confidence.
        let titles = MeetingProcessInspector.windowTitles(for: app)
        if !titles.isEmpty,
           MeetingProcessInspector.anyTitle(titles, containsAny: Self.meetingTitlePatterns) {
            return MeetingDetectionResult(
                provider: provider,
                status: .inMeeting(confidence: .high, provider: provider, signal: .combined)
            )
        }

        // Accessibility permission not granted or no meeting window visible —
        // return low confidence (process is running but no meeting confirmed).
        return MeetingDetectionResult(
            provider: provider,
            status: .inMeeting(confidence: .low, provider: provider, signal: .process)
        )
    }
}
