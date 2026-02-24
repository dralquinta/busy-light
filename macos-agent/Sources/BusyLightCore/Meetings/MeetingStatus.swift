import Foundation

// MARK: - MeetingConfidence

/// Confidence level for meeting detection.
/// Higher confidence means more independent signals corroborate the detection.
public enum MeetingConfidence: Int, Comparable, Sendable, CaseIterable {
    case none = 0
    case low = 1
    case medium = 2
    case high = 3

    public static func < (lhs: MeetingConfidence, rhs: MeetingConfidence) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var displayName: String {
        switch self {
        case .none:   return "none"
        case .low:    return "low"
        case .medium: return "medium"
        case .high:   return "high"
        }
    }
}

// MARK: - MeetingProvider

/// The meeting platform/provider associated with a detected meeting.
public enum MeetingProvider: String, Sendable, CaseIterable, Codable {
    case zoom  = "zoom"
    case teams = "teams"
    case meet  = "meet"

    public var displayName: String {
        switch self {
        case .zoom:  return "Zoom"
        case .teams: return "Microsoft Teams"
        case .meet:  return "Google Meet"
        }
    }
}

// MARK: - MeetingSignalType

/// The type of signal used to infer that a meeting is in progress.
public enum MeetingSignalType: String, Sendable {
    case process     = "process"
    case windowTitle = "window-title"
    case combined    = "combined"
}

// MARK: - MeetingStatus

/// The user's current meeting status as determined by local detection signals.
public enum MeetingStatus: Sendable {
    case none
    case inMeeting(confidence: MeetingConfidence, provider: MeetingProvider, signal: MeetingSignalType)

    /// Returns `true` when the user is believed to be in a meeting.
    public var isInMeeting: Bool {
        if case .inMeeting = self { return true }
        return false
    }

    /// The confidence of the current detection (`.none` when not in a meeting).
    public var confidence: MeetingConfidence {
        if case .inMeeting(let c, _, _) = self { return c }
        return .none
    }

    /// The detected provider, or `nil` when not in a meeting.
    public var provider: MeetingProvider? {
        if case .inMeeting(_, let p, _) = self { return p }
        return nil
    }
}

// MARK: - BusyReason

/// Reason the system is currently showing the user as busy.
/// Used for structured logging, UI tooltips, and post-mortem analysis.
public enum BusyReason: String, Sendable {
    case calendar = "calendar"
    case zoom     = "zoom"
    case teams    = "teams"
    case meet     = "meet"
    case manual   = "manual"
    case unknown  = "unknown"
}
