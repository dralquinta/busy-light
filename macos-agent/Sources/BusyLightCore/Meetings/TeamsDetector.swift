import AppKit
import ApplicationServices

/// Detects an active Microsoft Teams meeting running in the native Teams application.
///
/// **Detection strategy (multi-signal, privacy-safe):**
/// 1. Process detection — checks whether Microsoft Teams (`Microsoft Teams`,
///    `MSTeams`, or `Teams`) is in the running application list. No permission required.
/// 2. Window-title inspection — uses the Accessibility API to read the titles of
///    Teams' open windows and matches them against known in-call patterns.
///    Requires the macOS Accessibility permission (already requested by BusyLight).
///
/// **Confidence mapping:**
/// - Process running **and** call/meeting window detected → `.high` (signal: `.combined`)
/// - Process running, no call window found → `.low` (signal: `.process`)
/// - Process not running → `.none`
public final class TeamsDetector: MeetingDetectorProtocol, @unchecked Sendable {

    public let provider: MeetingProvider = .teams
    public var isEnabled: Bool

    // MARK: - Patterns

    private static let processNames: Set<String> = [
        "Microsoft Teams",
        "MSTeams",
        "Teams",
    ]

    private static let bundleIdentifiers: Set<String> = [
        "com.microsoft.teams",
        "com.microsoft.teams2",
    ]

    /// Window-title substrings that indicate a Teams call or meeting is active.
    private static let meetingTitlePatterns: [String] = [
        "meeting",
        "call",
        "calling",
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

        // Teams is running — try window-title inspection for higher confidence.
        let titles = MeetingProcessInspector.windowTitles(for: app)
        if !titles.isEmpty,
           MeetingProcessInspector.anyTitle(titles, containsAny: Self.meetingTitlePatterns) {
            return MeetingDetectionResult(
                provider: provider,
                status: .inMeeting(confidence: .high, provider: provider, signal: .combined)
            )
        }

        // Accessibility permission not granted or no call window visible.
        return MeetingDetectionResult(
            provider: provider,
            status: .inMeeting(confidence: .low, provider: provider, signal: .process)
        )
    }
}
