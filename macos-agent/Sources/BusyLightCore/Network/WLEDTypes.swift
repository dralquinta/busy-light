import Foundation

// MARK: - WLED API Request/Response Types

/// Request body for WLED `/json/state` endpoint to activate a preset.
public struct WLEDStateRequest: Codable, Sendable {
    /// Preset ID to activate (1-250)
    public let ps: Int
    /// Request full state response if true
    public let v: Bool
    
    public init(presetId: Int, includeResponse: Bool = true) {
        self.ps = presetId
        self.v = includeResponse
    }
}

/// Response from WLED `/json/state` endpoint.
public struct WLEDStateResponse: Codable, Sendable {
    /// Light on/off state
    public let on: Bool
    /// Brightness (0-255)
    public let bri: Int
    /// Currently active preset ID (-1 if none)
    public let ps: Int
    
    enum CodingKeys: String, CodingKey {
        case on
        case bri
        case ps
    }
}

/// Response from WLED `/json/info` endpoint.
public struct WLEDInfoResponse: Codable, Sendable {
    /// WLED firmware version
    public let ver: String
    /// Device friendly name
    public let name: String
    /// Uptime in seconds
    public let uptime: Int
    /// Device IP address
    public let ip: String?
    /// Device MAC address
    public let mac: String
    
    enum CodingKeys: String, CodingKey {
        case ver
        case name
        case uptime
        case ip
        case mac
    }
}

// MARK: - Network Error Types

/// Errors that can occur during WLED network operations.
public enum NetworkError: Error, LocalizedError, Sendable {
    case timeout
    case deviceUnavailable
    case invalidResponse(String)
    case httpError(statusCode: Int, message: String)
    case jsonParsingFailed(Error)
    case invalidURL
    case noData
    
    public var errorDescription: String? {
        switch self {
        case .timeout:
            return "Request timed out"
        case .deviceUnavailable:
            return "Device is unreachable"
        case .invalidResponse(let details):
            return "Invalid response: \(details)"
        case .httpError(let statusCode, let message):
            return "HTTP error \(statusCode): \(message)"
        case .jsonParsingFailed(let error):
            return "JSON parsing failed: \(error.localizedDescription)"
        case .invalidURL:
            return "Invalid URL"
        case .noData:
            return "No data received"
        }
    }
}

// MARK: - Device Model

/// Represents a WLED device on the network.
public struct WLEDDevice: Sendable, Identifiable, Equatable {
    /// Unique identifier (MAC address)
    public let id: String
    /// IP address or hostname
    public var address: String
    /// HTTP port (typically 80)
    public var port: Int
    /// Device friendly name (from WLED)
    public var name: String?
    /// Device is currently reachable
    public var isOnline: Bool
    /// Last successful communication timestamp
    public var lastSeen: Date
    /// Last preset ID sent to this device (for deduplication)
    public var lastPresetSent: Int?
    
    public init(
        id: String,
        address: String,
        port: Int = 80,
        name: String? = nil,
        isOnline: Bool = false,
        lastSeen: Date = Date(),
        lastPresetSent: Int? = nil
    ) {
        self.id = id
        self.address = address
        self.port = port
        self.name = name
        self.isOnline = isOnline
        self.lastSeen = lastSeen
        self.lastPresetSent = lastPresetSent
    }
    
    /// Creates a device from manually configured IP address (no discovery)
    public static func manualDevice(address: String, port: Int = 80) -> WLEDDevice {
        return WLEDDevice(
            id: "manual-\(address)",
            address: address,
            port: port,
            name: nil,
            isOnline: false,
            lastSeen: Date.distantPast
        )
    }
    
    public static func == (lhs: WLEDDevice, rhs: WLEDDevice) -> Bool {
        return lhs.id == rhs.id
    }
}
