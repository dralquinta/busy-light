import Foundation

/// Main network client for communicating with WLED devices.
/// Handles device discovery, preset broadcasting, and health monitoring.
@MainActor
public final class NetworkClient {
    // MARK: - Properties
    
    private(set) public var devices: [WLEDDevice] = []
    private let httpClient: any WLEDHTTPClient
    private let probeHTTPClient: any WLEDHTTPClient
    private let discovery: any WLEDDeviceDiscovering
    private let networkScanner: any WLEDDeviceScanning
    private let config: ConfigurationManager
    
    private var healthCheckTask: Task<Void, Never>?
    private var connectTask: Task<Void, Never>?
    private var isHealthCheckRunning = false
    private var lastReconnectAttempt: Date = .distantPast

    /// Minimum seconds between background re-discovery attempts when no online devices are known.
    private let reconnectIntervalSeconds: TimeInterval = 5.0

    /// Callback invoked when device status changes.
    public var onDeviceStatusChanged: (@MainActor ([WLEDDevice]) -> Void)?

    /// Callback invoked when one or more devices transition from offline to online.
    /// The app should use this to re-send the current presence state to the light.
    public var onDeviceReconnected: (@MainActor () -> Void)?
    
    // MARK: - Initialization
    
    public init(
        config: ConfigurationManager = .shared,
        httpClient: (any WLEDHTTPClient)? = nil,
        probeHTTPClient: (any WLEDHTTPClient)? = nil,
        discovery: (any WLEDDeviceDiscovering)? = nil,
        networkScanner: (any WLEDDeviceScanning)? = nil
    ) {
        self.config = config
        let defaultHTTPClient = httpClient ?? HTTPAdapter(timeoutMilliseconds: config.getWledHttpTimeout())
        self.httpClient = defaultHTTPClient
        self.probeHTTPClient = probeHTTPClient
            ?? httpClient
            ?? HTTPAdapter(timeoutMilliseconds: config.getWledHttpTimeout(), maxRetries: 1)
        self.discovery = discovery ?? DeviceDiscovery()
        self.networkScanner = networkScanner ?? LocalNetworkScanner()
        
        networkLogger.logEvent("network_client.initialized")
    }
    
    // MARK: - Connection Management
    
    /// Discovers online devices via mDNS/subnet scan and verifies manually configured IPs as a fallback.
    public func connect() async {
        if let connectTask {
            networkLogger.logEvent("network_client.connect.joined")
            await connectTask.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performConnect()
        }
        connectTask = task
        await task.value
        connectTask = nil
    }

    private func performConnect() async {
        networkLogger.logEvent("network_client.connect.started")
        
        var allDevices: [WLEDDevice] = []
        let port = config.getDeviceNetworkPort()
        
        let configuredAddresses = configuredDeviceAddresses()
        if !configuredAddresses.isEmpty {
            let verifiedManualDevices = await verifyConfiguredDevices(configuredAddresses, port: port)
            appendUniqueDevices(verifiedManualDevices, to: &allDevices)

            networkLogger.logEvent("network_client.connect.discovered", details: [
                "source": "configured",
                "count": String(verifiedManualDevices.count)
            ])
        }

        if allDevices.isEmpty && config.getWledEnableDiscovery() {
            // Bonjour is fast when available; subnet scan recovers WLED devices
            // that do not advertise or have moved to a new DHCP IP.
            let bonjourDevices = await discovery.discoverDevices(timeout: 5.0)
            appendUniqueDevices(bonjourDevices, to: &allDevices)
            
            networkLogger.logEvent("network_client.connect.discovered", details: [
                "source": "bonjour",
                "count": String(bonjourDevices.count)
            ])
        }

        if allDevices.isEmpty && config.getWledEnableDiscovery() {
            let scannedDevices = await networkScanner.scanForDevices(
                port: port,
                timeout: 5.0,
                priorityAddresses: configuredAddresses
            )
            appendUniqueDevices(scannedDevices, to: &allDevices)

            networkLogger.logEvent("network_client.connect.discovered", details: [
                "source": "subnet_scan",
                "count": String(scannedDevices.count)
            ])
        }

        if !allDevices.isEmpty {
            persistDiscoveredDeviceAddresses(allDevices)
        }
        
        devices = allDevices.filter(\.isOnline)
        
        networkLogger.logEvent("network_client.connect.completed", details: [
            "total_devices": String(devices.count)
        ])
        
        // Notify observers
        onDeviceStatusChanged?(devices)
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
        await httpClient.cancelAllRequests()
        devices.removeAll()

        await connect()
        startHealthMonitoring()
    }
    
    // MARK: - State Broadcasting
    
    /// Sends presence state to all configured devices by activating corresponding preset.
    /// Broadcasts to all devices in parallel using TaskGroup.
    /// - Parameter state: Presence state to broadcast
    public func sendState(_ state: PresenceState) async {
        await sendState(state, allowRecovery: true)
    }

    private func sendState(_ state: PresenceState, allowRecovery: Bool) async {
        let presetId = config.getWledPreset(for: state)
        
        networkLogger.logEvent("network_client.send_state", details: [
            "state": state.rawValue,
            "preset": String(presetId),
            "device_count": String(devices.count)
        ])

        if devices.isEmpty && allowRecovery {
            _ = await recoverDevices(reason: "send_no_online_devices", force: true)
        }

        guard !devices.isEmpty else {
            networkLogger.logEvent("network_client.send_state.no_online_devices")
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
            
            devices = updatedDevices.filter(\.isOnline)
        }
        
        // Notify observers of status changes
        onDeviceStatusChanged?(devices)

        if devices.isEmpty && allowRecovery {
            let recovered = await recoverDevices(reason: "send_all_devices_failed", force: true)
            if recovered {
                await sendState(state, allowRecovery: false)
            }
        }
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
            let response = try await httpClient.postState(
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
            await self?.performHealthCheck()

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

        // If no online devices are known yet, attempt periodic re-discovery (rate-limited).
        if devices.isEmpty {
            let recovered = await recoverDevices(reason: "health_no_online_devices", force: false)
            if recovered {
                onDeviceReconnected?()
            }
            return
        }

        var updatedDevices = devices
        var statusChanged = false
        var hasReconnectedDevice = false

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

                        if isOnline {
                            // Clear cached preset so the current state is immediately re-sent.
                            updatedDevices[index].lastPresetSent = nil
                            hasReconnectedDevice = true
                        }
                    }
                }
            }
        }
        
        let onlineDevices = updatedDevices.filter(\.isOnline)
        if onlineDevices.count != updatedDevices.count {
            statusChanged = true
        }

        devices = onlineDevices
        
        // Notify observers if status changed
        if statusChanged {
            onDeviceStatusChanged?(devices)
        }

        // Re-send current presence state to devices that just came back online.
        if hasReconnectedDevice {
            networkLogger.logEvent("network_client.health.reconnect_detected")
            onDeviceReconnected?()
        }

        if devices.isEmpty {
            let recovered = await recoverDevices(reason: "health_all_devices_lost", force: false)
            if recovered {
                onDeviceReconnected?()
            }
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
            _ = try await probeHTTPClient.getInfo(from: device.address, port: device.port)
            return true
        } catch {
            return false
        }
    }
    
    private func appendUniqueDevices(_ newDevices: [WLEDDevice], to devices: inout [WLEDDevice]) {
        for device in newDevices {
            let alreadyKnown = devices.contains {
                $0.id == device.id || $0.address == device.address
            }

            if !alreadyKnown {
                devices.append(device)
            }
        }
    }

    private func verifyConfiguredDevices(_ addresses: [String], port: Int) async -> [WLEDDevice] {
        var verifiedDevices: [WLEDDevice] = []

        for address in addresses {
            do {
                let info = try await probeHTTPClient.getInfo(from: address, port: port)
                guard isWLEDInfo(info) else { continue }

                let resolvedAddress = info.ip.flatMap(NetworkAddressValidator.normalizeIPv4Address) ?? address
                let device = WLEDDevice(
                    id: info.mac.isEmpty ? "manual-\(resolvedAddress)" : info.mac,
                    address: resolvedAddress,
                    port: port,
                    name: info.name,
                    isOnline: true,
                    lastSeen: Date()
                )

                verifiedDevices.append(device)
                networkLogger.logEvent("network_client.connect.manual.verified", details: [
                    "address": resolvedAddress,
                    "port": String(port)
                ])
            } catch {
                networkLogger.logEvent("network_client.connect.manual.offline", details: [
                    "address": address,
                    "port": String(port),
                    "error": error.localizedDescription
                ])
            }
        }

        return verifiedDevices
    }

    private func configuredDeviceAddresses() -> [String] {
        let savedAddresses = config.getDeviceNetworkAddresses()
        let legacyAddress = config.getDeviceNetworkAddress()

        var seen = Set<String>()
        var addresses: [String] = []
        for address in savedAddresses + [legacyAddress] {
            let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedAddress.isEmpty,
                  seen.insert(trimmedAddress).inserted else {
                continue
            }

            addresses.append(trimmedAddress)
        }

        return addresses
    }

    private func recoverDevices(reason: String, force: Bool) async -> Bool {
        let elapsed = Date().timeIntervalSince(lastReconnectAttempt)
        guard force || elapsed >= reconnectIntervalSeconds else {
            return false
        }

        lastReconnectAttempt = Date()
        networkLogger.logEvent("network_client.rediscover", details: ["reason": reason])
        await connect()
        return !devices.isEmpty
    }

    private func isWLEDInfo(_ info: WLEDInfoResponse) -> Bool {
        return info.ver.contains("0.") || info.ver.lowercased().contains("wled")
    }

    private func persistDiscoveredDeviceAddresses(_ discoveredDevices: [WLEDDevice]) {
        let addresses = discoveredDevices.map(\.address)
        guard let firstAddress = addresses.first else { return }

        if config.getDeviceNetworkAddress() != firstAddress {
            config.setDeviceNetworkAddress(firstAddress)
        }

        if config.getDeviceNetworkAddresses() != addresses {
            config.setDeviceNetworkAddresses(addresses)
        }

        networkLogger.logEvent("network_client.device_auto_configured", details: [
            "addresses": addresses.joined(separator: ",")
        ])
    }
}
