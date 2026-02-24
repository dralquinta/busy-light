import AppKit
import ApplicationServices

/// Detects a browser-hosted meeting session (Google Meet, Microsoft Teams web,
/// or Zoom web) by inspecting browser window titles via the Accessibility API.
///
/// **Detection strategy (Strategy A — window title inspection):**
/// Reads open window titles of common browsers using the Accessibility API and
/// matches them against known meeting-URL / page-title patterns. This is
/// privacy-safe: no tab URLs, page content, cookies, or user data are read.
///
/// **Requires:** macOS Accessibility permission (already requested by BusyLight).
/// Without the permission, this detector returns `.none` (no false positives).
///
/// **Supported browsers:**
/// Google Chrome, Safari, Microsoft Edge, Brave Browser, Chromium, Firefox.
///
/// **Supported providers:**
/// One `BrowserMeetingDetector` instance is created per `MeetingProvider`.
/// Instantiate with `.meet`, `.teams`, or `.zoom` as appropriate.
public final class BrowserMeetingDetector: MeetingDetectorProtocol, @unchecked Sendable {

    public let provider: MeetingProvider
    public var isEnabled: Bool

    // MARK: - Browser Process Names

    private static let browserProcessNames: Set<String> = [
        "Google Chrome",
        "Safari",
        "Microsoft Edge",
        "Brave Browser",
        "Chromium",
        "Firefox",
    ]

    // MARK: - Per-Provider Title Patterns

    private static let meetTitlePatterns: [String] = [
        "meet – ",          // "Meet – John Doe - Google Meet"
        "google meet",
        "meet.google.com",
    ]

    private static let teamsTitlePatterns: [String] = [
        "microsoft teams",
        "teams meeting",
        "calling | microsoft teams",
        "meeting | microsoft teams",
    ]

    private static let zoomTitlePatterns: [String] = [
        "zoom meeting",
        "zoom – ",
        "zoom.us",
    ]

    // MARK: - Init

    public init(provider: MeetingProvider, isEnabled: Bool = true) {
        self.provider = provider
        self.isEnabled = isEnabled
    }

    // MARK: - MeetingDetectorProtocol

    public func detect() -> MeetingDetectionResult {
        guard isEnabled else {
            return MeetingDetectionResult(provider: provider, status: .none)
        }

        guard AXIsProcessTrusted() else {
            // Cannot inspect window titles without Accessibility permission.
            return MeetingDetectionResult(provider: provider, status: .none)
        }

        let patterns = titlePatterns(for: provider)

        for app in NSWorkspace.shared.runningApplications {
            guard let name = app.localizedName,
                  Self.browserProcessNames.contains(name) else { continue }

            let titles = MeetingProcessInspector.windowTitles(for: app)
            if MeetingProcessInspector.anyTitle(titles, containsAny: patterns) {
                return MeetingDetectionResult(
                    provider: provider,
                    status: .inMeeting(
                        confidence: .high,
                        provider: provider,
                        signal: .windowTitle
                    )
                )
            }
        }

        return MeetingDetectionResult(provider: provider, status: .none)
    }

    // MARK: - Private

    private func titlePatterns(for provider: MeetingProvider) -> [String] {
        switch provider {
        case .meet:  return Self.meetTitlePatterns
        case .teams: return Self.teamsTitlePatterns
        case .zoom:  return Self.zoomTitlePatterns
        }
    }
}
