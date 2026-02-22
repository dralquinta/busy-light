import Foundation

/// Represents the user's current presence/availability state.
public enum PresenceState: String, Codable, Sendable {
    case available = "available"
    case busy = "busy"
    case away = "away"
    /// Tentative: the user has an unconfirmed calendar event at this time.
    case tentative = "tentative"
    /// Unknown: uninitialized state or error condition
    case unknown = "unknown"
    
    public var displayName: String {
        switch self {
        case .available:
            return "Available"
        case .busy:
            return "Busy"
        case .away:
            return "Away"
        case .tentative:
            return "Tentative"
        case .unknown:
            return "Unknown"
        }
    }
}
