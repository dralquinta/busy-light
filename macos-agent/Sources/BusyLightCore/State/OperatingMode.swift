import Foundation

/// Operating mode controlling whether presence state is automatically resolved
/// from calendar events or manually controlled via user overrides.
@MainActor
public enum OperatingMode: String, Sendable, Codable {
    /// Automatic mode: presence state is continuously resolved from calendar events
    case auto
    
    /// Manual mode: user override is active, calendar updates are ignored
    case manual
}
