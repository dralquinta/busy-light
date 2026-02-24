import Foundation
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
    private let logger: Logger = meetingLogger

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
        "meet:",            // "Meet: abc-def-ghi" - Active meeting with code (most reliable)
        // Note: Removed "meet – " and "meet - " as they match landing page "Meet - Google Meet"
        // Note: Removed "google meet" and "meet.google.com" - too broad, match landing page
    ]

    private static let teamsTitlePatterns: [String] = [
        "microsoft teams",
        "teams meeting",
        "calling | microsoft teams",
        "meeting | microsoft teams",
    ]

    private static let zoomTitlePatterns: [String] = [
        "zoom meeting",
        "zoom – ",          // en dash variant
        "zoom - ",          // ASCII hyphen variant
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
            logger.logEvent("meeting.browser.detector_disabled", details: [
                "provider": provider.rawValue,
            ])
            return MeetingDetectionResult(provider: provider, status: .none)
        }

        guard AXIsProcessTrusted() else {
            // Cannot inspect window titles without Accessibility permission.
            logger.logEvent("meeting.browser.no_accessibility", details: [
                "provider": provider.rawValue,
            ])
            return MeetingDetectionResult(provider: provider, status: .none)
        }

        let patterns = titlePatterns(for: provider)

        for app in NSWorkspace.shared.runningApplications {
            guard let name = app.localizedName,
                  Self.browserProcessNames.contains(name) else { continue }

            let titles = MeetingProcessInspector.windowTitles(for: app)
            
            // Log all window titles for debugging
            if !titles.isEmpty {
                logger.logEvent("meeting.browser.window_titles", details: [
                    "browser": name,
                    "provider": provider.rawValue,
                    "title_count": String(titles.count),
                    "patterns": patterns.joined(separator: " | "),
                ])
                // Debug: log each title individually
                for (idx, title) in titles.enumerated() {
                    logger.logEvent("meeting.browser.window_title", details: [
                        "browser": name,
                        "provider": provider.rawValue,
                        "index": String(idx),
                        "title": title,
                    ])
                }
            }
            
            // For Google Meet, require additional active meeting indicators
            // to prevent false positives from tabs left open after meeting ends
            if provider == .meet && MeetingProcessInspector.anyTitle(titles, containsAny: patterns) {
                let hasMeetTitle = titles.contains { title in
                    let lower = title.lowercased()
                    return lower.contains("meet:")
                }
                
                if hasMeetTitle {
                    // Check for active meeting indicators (camera/mic usage, recording, etc.)
                    let hasActiveIndicator = titles.contains { title in
                        let lower = title.lowercased()
                        return lower.contains("camera") || 
                               lower.contains("microphone") ||
                               lower.contains("recording") ||
                               lower.contains("screen shar")  // "screen sharing"
                    }
                    
                    if !hasActiveIndicator {
                        logger.logEvent("meeting.browser.meet_tab_inactive", details: [
                            "browser": name,
                            "reason": "no active indicators (camera/microphone/recording)",
                        ])
                        continue  // Skip this browser, check next one
                    }
                }
            }
            
            if MeetingProcessInspector.anyTitle(titles, containsAny: patterns) {
                logger.logEvent("meeting.browser.match_found", details: [
                    "browser": name,
                    "provider": provider.rawValue,
                    "matched": "true",
                ])
                return MeetingDetectionResult(
                    provider: provider,
                    status: .inMeeting(
                        confidence: .high,
                        provider: provider,
                        signal: .windowTitle
                    )
                )
            } else {
                // No match - log for debugging
                logger.logEvent("meeting.browser.no_match", details: [
                    "browser": name,
                    "provider": provider.rawValue,
                ])
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
