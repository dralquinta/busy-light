import Foundation

/// Main network client for communicating with WLED devices.
/// Handles device discovery, preset broadcasting, and health monitoring.
@MainActor
public final class NetworkClient {
    // MARK: - Properties
    
    private(set) public var devices: [WLEDDevice] = []
    private let httpAdapter: HTTPAdapter
    private let discovery: DeviceDiscovery
    private let config: ConfigurationManager
    
    private var healthCheckTask: Task<Void, Never>?
    private var isHealthCheckRunning = false
    
    /// Callback invoked when device status changes.
    public var onDeviceStatusChanged: (@MainActor ([WLEDDevice]) -> Void)?
    
    // MARK: - Initialization
    
    public init(config: ConfigurationManager = .shared) {
        self.config = config
        self.httpAdapter = HTTPAdapter(timeoutMilliseconds: config.getWledHttpTimeout())
        self.discovery = DeviceDiscovery()
        
        networkLogger.logEvent("network_client.initialized")
    }
    
    // MARK: - Connection Management
    
    /// Discovers devices via mDNS and merges with manually configured IPs.
    public func connect() async {
        networkLogger.logEvent("network_client.connect.started")
        
        var allDevices: [WLEDDevice] = []
        
        // Discover devices if enabled
        if config.getWledEnableDiscovery() {
            let discoveredDevices = await discovery.discoverDevices(timeout: 5.0)
            allDevices.append(contentsOf: discoveredDevices)
            
            networkLogger.logEvent("network_client.connect.discovered", details: [
                "count": String(discoveredDevices.count)
            ])
        }

        // Auto-configure the first discovered device if no address is set
        if config.getDeviceNetworkAddresses().isEmpty, let firstDevice = allDevices.first {
            config.setDeviceNetworkAddress(firstDevice.address)
            config.setDeviceNetworkAddresses([firstDevice.address])

            networkLogger.logEvent("network_client.device_auto_configured", details: [
                "address": firstDevice.address,
                "port": String(firstDevice.port)
            ])
        }
        
        // Add manually configured devices
        let configuredAddresses = config.getDeviceNetworkAddresses()
        let port = config.getDeviceNetworkPort()
        
        for address in configuredAddresses {
            // Skip if already discovered
            if !allDevices.contains(where: { $0.address == address }) {
                let manualDevice = WLEDDevice.manualDevice(address: address, port: port)
                allDevices.append(manualDevice)
                
                networkLogger.logEvent("network_client.connect.manual", details: [
                    "address": address,
                    "port": String(port)
                ])
            }
        }
        
        devices = allDevices
        
        networkLogger.logEvent("network_client.connect.completed", details: [
            "total_devices": String(devices.count)
        ])
        
        // Notify observers
        onDeviceStatusChanged?(devices)
        
        // Verify connectivity for all devices
        await verifyAllDevices()
    }
    
    /// Refreshes device list by re-running discovery.
    public func refreshDevices() async {
        networkLogger.logEvent("network_client.refresh")
        await connect()
    }
    
    /// Disconnects and cleans up resources.
    public func disconnect() {
        networkLogger.logEvent("network_client.disconnect")
        stopHealthMonitoring()
        devices.removeAll()
    }

    /// Applies a manual device address override and reconnects immediately.
    public func applyDeviceHostOverride(_ address: String) async {
        let previous = config.getDeviceNetworkAddresses().joined(separator: ",")

        networkLogger.logEvent("network_client.device_override.requested", details: [
            "previous": previous.isEmpty ? "(none)" : previous,
            "new": address
        ])

        stopHealthMonitoring()
        await httpAdapter.cancelAllRequests()
        devices.removeAll()

        await connect()
        startHealthMonitoring()
    }
    
    // MARK: - State Broadcasting
    
    /// Sends presence state to all configured devices by activating corresponding preset.
    /// Broadcasts to all devices in parallel using TaskGroup.
    /// - Parameter state: Presence state to broadcast
    public func sendState(_ state: PresenceState) async {
        let presetId = config.getWledPreset(for: state)
        
        networkLogger.logEvent("network_client.send_state", details: [
            "state": state.rawValue,
            "preset": String(presetId),
            "device_count": String(devices.count)
        ])
        
        guard !devices.isEmpty else {
            networkLogger.logEvent("network_client.send_state.no_devices")
            return
        }
        
        // Broadcast to all devices in parallel
        await withTaskGroup(of: (Int, Bool, WLEDDevice).self) { group in
            for (index, device) in devices.enumerated() {
                group.addTask {
                    let success = await self.sendPresetToDevice(
                        device: device,
                        presetId: presetId,
                        state: state
                    )
                    return (index, success, device)
                }
            }
            
            // Collect results and update device states
            var updatedDevices = devices
            for await (index, success, _) in group {
                if index < updatedDevices.count {
                    updatedDevices[index].isOnline = success
                    if success {
                        updatedDevices[index].lastSeen = Date()
                        updatedDevices[index].lastPresetSent = presetId
                    }
                }
            }
            
            devices = updatedDevices
        }
        
        // Notify observers of status changes
        onDeviceStatusChanged?(devices)
    }
    
    /// Sends preset to a single device with deduplication.
    private func sendPresetToDevice(
        device: WLEDDevice,
        presetId: Int,
        state: PresenceState
    ) async -> Bool {
        // Skip if same preset already sent (deduplication)
        if device.lastPresetSent == presetId {
            networkLogger.logEvent("network_client.send.skipped.duplicate", details: [
                "device": device.name ?? device.address,
                "preset": String(presetId),
                "state": state.rawValue
            ])
            return device.isOnline // Return previous online status
        }
        
        let request = WLEDStateRequest(presetId: presetId, includeResponse: true)
        
        do {
            let response = try await httpAdapter.postState(
                to: device.address,
                port: device.port,
                request: request
            )
            
            networkLogger.logEvent("network_client.send.success", details: [
                "device": device.name ?? device.address,
                "preset": String(presetId),
                "state": state.rawValue,
                "response_preset": String(response.ps),
                "device_on": String(response.on)
            ])
            
            return true
        } catch {
            networkLogger.logEvent("network_client.send.failed", details: [
                "device": device.name ?? device.address,
                "preset": String(presetId),
                "state": state.rawValue,
                "error": error.localizedDescription
            ])
            
            return false
        }
    }
    
    // MARK: - Health Monitoring
    
    /// Starts periodic health check polling.
    public func startHealthMonitoring() {
        guard !isHealthCheckRunning else {
            networkLogger.logEvent("network_client.health.already_running")
            return
        }
        
        isHealthCheckRunning = true
        let interval = config.getWledHealthCheckInterval()
        
        networkLogger.logEvent("network_client.health.started", details: [
            "interval_seconds": String(interval)
        ])
        
        healthCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                
                guard !Task.isCancelled else { break }
                await self?.performHealthCheck()
            }
        }
    }
    
    /// Stops health check polling.
    public func stopHealthMonitoring() {
        guard isHealthCheckRunning else { return }
        
        networkLogger.logEvent("network_client.health.stopped")
        
        isHealthCheckRunning = false
        healthCheckTask?.cancel()
        healthCheckTask = nil
    }
    
    /// Performs health check on all devices.
    private func performHealthCheck() async {
        networkLogger.logEvent("network_client.health.check", details: [
            "device_count": String(devices.count)
        ])
        
        var updatedDevices = devices
        var statusChanged = false
        
        await withTaskGroup(of: (Int, Bool, WLEDDevice).self) { group in
            for (index, device) in devices.enumerated() {
                group.addTask {
                    let isOnline = await self.checkDeviceHealth(device: device)
                    return (index, isOnline, device)
                }
            }
            
            for await (index, isOnline, device) in group {
                if index < updatedDevices.count {
                    let wasOnline = updatedDevices[index].isOnline
                    updatedDevices[index].isOnline = isOnline
                    
                    if isOnline {
                        updatedDevices[index].lastSeen = Date()
                    }
                    
                    // Detect status transitions
                    if wasOnline != isOnline {
                        statusChanged = true
                        let transition = isOnline ? "offline→online" : "online→offline"
                        networkLogger.logEvent("network_client.health.transition", details: [
                            "device": device.name ?? device.address,
                            "transition": transition
                        ])
                    }
                }
            }
        }
        
        devices = updatedDevices
        
        // Notify observers if status changed
        if statusChanged {
            onDeviceStatusChanged?(devices)
        }
    }
    
    /// Checks health of a single device.
    private func checkDeviceHealth(device: WLEDDevice) async -> Bool {
        networkLogger.logEvent("network_client.health.ping", details: [
            "device": device.name ?? device.address,
            "address": device.address,
            "port": String(device.port)
        ])
        do {
            _ = try await httpAdapter.getInfo(from: device.address, port: device.port)
            return true
        } catch {
            return false
        }
    }
    
    /// Verifies connectivity for all devices.
    private func verifyAllDevices() async {
        await performHealthCheck()
    }
}
