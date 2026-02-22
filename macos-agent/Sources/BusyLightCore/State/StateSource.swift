import Foundation

/// Represents the source/origin of a presence state transition.
/// Used for audit trails, logging, and precedence enforcement.
@MainActor
public enum StateSource: String, Sendable, Codable {
    /// State derived from calendar events (lowest precedence)
    case calendar
    
    /// State set manually by the user via UI override
    case manual
    
    /// State forced by system events (screen lock, sleep) - highest precedence
    case system
    
    /// Initial state at application startup
    case startup
    
    /// Priority level for precedence rules: system > manual > calendar
    public var priority: Int {
        switch self {
        case .system: return 3
        case .manual: return 2
        case .calendar: return 1
        case .startup: return 0
        }
    }
}
