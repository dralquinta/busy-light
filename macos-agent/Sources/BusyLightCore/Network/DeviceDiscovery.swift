import Foundation

/// Discovers WLED devices on the local network using Bonjour/mDNS.
/// Uses standard HTTP service discovery (_http._tcp) and filters for WLED devices.
@MainActor
public final class DeviceDiscovery: NSObject, @preconcurrency NetServiceBrowserDelegate, @preconcurrency NetServiceDelegate {
    private var browser: NetServiceBrowser?
    private var pendingServices: [NetService] = []
    private var discoveredDevices: [WLEDDevice] = []
    private var httpAdapter: HTTPAdapter?
    
    private var discoveryContinuation: CheckedContinuation<[WLEDDevice], Never>?
    private var discoveryTask: Task<Void, Never>?
    
    public override init() {
        super.init()
    }
    
    /// Discovers WLED devices on the local network.
    /// - Parameter timeout: Discovery timeout in seconds (default: 5)
    /// - Returns: Array of discovered WLED devices
    public func discoverDevices(timeout: TimeInterval = 5.0) async -> [WLEDDevice] {
        networkLogger.logEvent("discovery.started", details: ["timeout": String(timeout)])
        
        discoveredDevices.removeAll()
        pendingServices.removeAll()
        httpAdapter = HTTPAdapter(timeoutMilliseconds: 500)
        
        return await withCheckedContinuation { continuation in
            self.discoveryContinuation = continuation
            
            // Start service browser
            browser = NetServiceBrowser()
            browser?.delegate = self
            browser?.searchForServices(ofType: "_http._tcp.", inDomain: "local.")
            
            // Set timeout
            discoveryTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                self?.stopDiscovery()
            }
        }
    }
    
    /// Stops discovery and returns found devices.
    private func stopDiscovery() {
        browser?.stop()
        browser = nil
        discoveryTask?.cancel()
        discoveryTask = nil
        
        networkLogger.logEvent("discovery.completed", details: [
            "devices_found": String(discoveredDevices.count)
        ])
        
        discoveryContinuation?.resume(returning: discoveredDevices)
        discoveryContinuation = nil
    }
    
    // MARK: - NetServiceBrowserDelegate
    
    public func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didFind service: NetService,
        moreComing: Bool
    ) {
        networkLogger.logEvent("discovery.service.found", details: [
            "name": service.name,
            "type": service.type,
            "domain": service.domain
        ])
        
        pendingServices.append(service)
        service.delegate = self
        service.resolve(withTimeout: 3.0)
        
        // If no more services coming, wait a bit for resolutions to complete
        if !moreComing {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.0))
                self?.stopDiscovery()
            }
        }
    }
    
    public func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didRemove service: NetService,
        moreComing: Bool
    ) {
        networkLogger.logEvent("discovery.service.removed", details: [
            "name": service.name
        ])
    }
    
    public func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didNotSearch errorDict: [String: NSNumber]
    ) {
        networkLogger.logEvent("discovery.error", details: [
            "error": errorDict.description
        ])
    }
    
    // MARK: - NetServiceDelegate
    
    public func netServiceDidResolveAddress(_ service: NetService) {
        networkLogger.logEvent("discovery.service.resolved", details: [
            "name": service.name,
            "hostname": service.hostName ?? "unknown",
            "port": String(service.port)
        ])
        
        Task { [weak self] in
            self?.verifyWLEDDevice(service: service)
        }
    }
    
    public func netService(_ service: NetService, didNotResolve errorDict: [String: NSNumber]) {
        networkLogger.logEvent("discovery.service.resolve_failed", details: [
            "name": service.name,
            "error": errorDict.description
        ])
    }
    
    // MARK: - WLED Verification
    
    /// Verifies if a discovered service is a WLED device by fetching /json/info.
    private func verifyWLEDDevice(service: NetService) {
        guard let hostName = service.hostName else {
            return
        }
        
        // Remove trailing dot from hostname if present
        let cleanHost = hostName.hasSuffix(".") ? String(hostName.dropLast()) : hostName
        let port = service.port
        
        Task {
            guard let adapter = httpAdapter else { return }
            
            do {
                let info = try await adapter.getInfo(from: cleanHost, port: port)
            
            // Verify this is a WLED device by checking version string
            if info.ver.contains("0.") || info.ver.lowercased().contains("wled") {
                let resolvedAddress: String
                if let infoIp = info.ip,
                   let normalizedIp = NetworkAddressValidator.normalizeIPv4Address(infoIp) {
                    resolvedAddress = normalizedIp
                } else {
                    resolvedAddress = cleanHost
                }

                let device = WLEDDevice(
                    id: info.mac,
                    address: resolvedAddress,
                    port: port,
                    name: info.name,
                    isOnline: true,
                    lastSeen: Date()
                )
                
                // Avoid duplicates
                if !discoveredDevices.contains(where: { $0.id == device.id }) {
                    discoveredDevices.append(device)
                    
                    networkLogger.logEvent("discovery.wled.verified", details: [
                        "name": info.name,
                        "address": resolvedAddress,
                        "port": String(port),
                        "version": info.ver,
                        "mac": info.mac
                    ])
                }
            } else {
                networkLogger.logEvent("discovery.not_wled", details: [
                    "host": cleanHost,
                    "version": info.ver
                ])
            }
            } catch {
                // Not a WLED device or unreachable - silently ignore
                networkLogger.logEvent("discovery.verification_failed", details: [
                    "host": cleanHost,
                    "port": String(port),
                    "error": error.localizedDescription
                ])
            }
        }
    }
}
