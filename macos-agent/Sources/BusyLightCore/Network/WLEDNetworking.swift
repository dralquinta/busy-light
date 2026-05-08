import Foundation

public protocol WLEDHTTPClient: Sendable {
    func postState(
        to address: String,
        port: Int,
        request: WLEDStateRequest
    ) async throws -> WLEDStateResponse

    func getInfo(
        from address: String,
        port: Int
    ) async throws -> WLEDInfoResponse

    func cancelAllRequests() async
}

@MainActor
public protocol WLEDDeviceDiscovering: AnyObject {
    func discoverDevices(timeout: TimeInterval) async -> [WLEDDevice]
}

public protocol WLEDDeviceScanning: Sendable {
    func scanForDevices(
        port: Int,
        timeout: TimeInterval,
        priorityAddresses: [String]
    ) async -> [WLEDDevice]
}

public extension WLEDDeviceScanning {
    func scanForDevices(port: Int, timeout: TimeInterval) async -> [WLEDDevice] {
        await scanForDevices(port: port, timeout: timeout, priorityAddresses: [])
    }
}
