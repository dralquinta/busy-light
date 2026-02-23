import Foundation

public enum DeviceConnectionStatus: String, Sendable {
    case online
    case offline
    case unknown

    public var displayText: String {
        switch self {
        case .online:
            return "Online"
        case .offline:
            return "Offline"
        case .unknown:
            return "Unknown"
        }
    }
}
