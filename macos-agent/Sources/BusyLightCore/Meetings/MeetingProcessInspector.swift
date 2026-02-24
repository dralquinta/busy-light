import AppKit
import ApplicationServices

/// Privacy-safe helpers used by meeting detectors to inspect running processes
/// and application window titles.
///
/// **Permission requirements:**
/// - Process list (`NSWorkspace`): No special permission required.
/// - Window titles (Accessibility API): Requires the macOS Accessibility permission
///   (`System Settings → Privacy & Security → Accessibility`). BusyLight already
///   requests this permission for global hotkey monitoring. When the permission is
///   not granted, `windowTitles(for:)` returns an empty array and the detector
///   falls back to process-only (low-confidence) detection.
///
/// No screen recording, audio capture, or pixel inspection is performed.
public enum MeetingProcessInspector {

    // MARK: - Process Detection

    /// Returns the first running application whose `localizedName` or
    /// `bundleIdentifier` matches any of the supplied names / bundle IDs.
    public static func findRunningApp(
        processNames: Set<String>,
        bundleIdentifiers: Set<String> = []
    ) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { app in
            if let name = app.localizedName, processNames.contains(name) { return true }
            if let bid  = app.bundleIdentifier, bundleIdentifiers.contains(bid) { return true }
            return false
        }
    }

    // MARK: - Window Title Inspection (Accessibility API)

    /// Returns the titles of all open windows belonging to the given application.
    ///
    /// Uses the Accessibility API (`AXUIElement`) which is granted by the
    /// Accessibility permission. Returns an empty array when:
    /// - The Accessibility permission has not been granted.
    /// - The app has no visible windows.
    /// - The AX API returns an error for the given process.
    public static func windowTitles(for app: NSRunningApplication) -> [String] {
        guard AXIsProcessTrusted() else { return [] }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        var windowsValue: AnyObject?
        let listResult = AXUIElementCopyAttributeValue(
            axApp, kAXWindowsAttribute as CFString, &windowsValue
        )
        guard listResult == .success,
              let windows = windowsValue as? [AXUIElement] else {
            return []
        }

        return windows.compactMap { window in
            var titleValue: AnyObject?
            let titleResult = AXUIElementCopyAttributeValue(
                window, kAXTitleAttribute as CFString, &titleValue
            )
            return titleResult == .success ? titleValue as? String : nil
        }
    }

    // MARK: - Pattern Matching

    /// Returns `true` if any title in `titles` contains at least one of `patterns`
    /// (case-insensitive).
    public static func anyTitle(
        _ titles: [String],
        containsAny patterns: [String]
    ) -> Bool {
        for title in titles {
            let lower = title.lowercased()
            if patterns.contains(where: { lower.contains($0.lowercased()) }) {
                return true
            }
        }
        return false
    }
}
