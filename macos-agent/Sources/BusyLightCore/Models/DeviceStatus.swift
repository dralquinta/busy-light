import Foundation

/// Represents the connection and state of the busy-light physical device.
public struct DeviceStatus: Codable {
    public enum ConnectionState: String, Codable {
        case connected = "connected"
        case disconnected = "disconnected"
        case error = "error"
    }
    
    public let connectionState: ConnectionState
    public let lastUpdate: Date
    public let errorMessage: String?
    
    public init(connectionState: ConnectionState, lastUpdate: Date = Date(), errorMessage: String? = nil) {
        self.connectionState = connectionState
        self.lastUpdate = lastUpdate
        self.errorMessage = errorMessage
    }
    
    public var displayText: String {
        switch connectionState {
        case .connected:
            return "Device Connected"
        case .disconnected:
            return "Device Disconnected"
        case .error:
            return "Device Error"
        }
    }
}
