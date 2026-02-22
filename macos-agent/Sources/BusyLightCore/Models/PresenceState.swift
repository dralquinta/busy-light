import Foundation

/// Represents the user's current presence/availability state.
public enum PresenceState: String, Codable, Sendable {
    case available = "available"
    case busy = "busy"
    case away = "away"
    
    public var displayName: String {
        switch self {
        case .available:
            return "Available"
        case .busy:
            return "Busy"
        case .away:
            return "Away"
        }
    }
}
