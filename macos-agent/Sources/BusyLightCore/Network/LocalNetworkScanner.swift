import Darwin
import Foundation

/// Finds WLED devices that do not advertise over Bonjour by probing local IPv4 /24 subnets.
public final class LocalNetworkScanner: WLEDDeviceScanning {
    private let httpClient: any WLEDHTTPClient
    private let localAddressProvider: @Sendable () -> [String]
    private let scanConcurrency: Int

    public init(
        httpClient: any WLEDHTTPClient = HTTPAdapter(timeoutMilliseconds: 1_000, maxRetries: 1),
        localAddressProvider: @escaping @Sendable () -> [String] = LocalNetworkScanner.localIPv4Addresses,
        scanConcurrency: Int = 64
    ) {
        self.httpClient = httpClient
        self.localAddressProvider = localAddressProvider
        self.scanConcurrency = max(1, scanConcurrency)
    }

    public func scanForDevices(
        port: Int,
        timeout: TimeInterval = 5.0,
        priorityAddresses: [String] = []
    ) async -> [WLEDDevice] {
        let startedAt = Date()
        let localAddresses = localAddressProvider()
        let candidates = Self.candidateIPv4Addresses(
            from: localAddresses,
            priorityAddresses: priorityAddresses
        )

        networkLogger.logEvent("discovery.scan.started", details: [
            "local_addresses": localAddresses.joined(separator: ","),
            "priority_addresses": priorityAddresses.joined(separator: ","),
            "candidate_count": String(candidates.count),
            "port": String(port)
        ])

        guard !candidates.isEmpty else {
            networkLogger.logEvent("discovery.scan.completed", details: [
                "devices_found": "0",
                "duration_ms": "0"
            ])
            return []
        }

        var devices: [WLEDDevice] = []

        for batchStart in stride(from: 0, to: candidates.count, by: scanConcurrency) {
            if Date().timeIntervalSince(startedAt) >= timeout {
                break
            }

            let batchEnd = min(batchStart + scanConcurrency, candidates.count)
            let batch = Array(candidates[batchStart..<batchEnd])

            await withTaskGroup(of: WLEDDevice?.self) { group in
                for address in batch {
                    let httpClient = self.httpClient
                    group.addTask {
                        return await Self.verifyWLEDDevice(
                            address: address,
                            port: port,
                            httpClient: httpClient
                        )
                    }
                }

                for await device in group {
                    guard let device else { continue }
                    if !devices.contains(where: { $0.id == device.id || $0.address == device.address }) {
                        devices.append(device)
                    }
                }
            }
        }

        let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        networkLogger.logEvent("discovery.scan.completed", details: [
            "devices_found": String(devices.count),
            "duration_ms": String(durationMs)
        ])

        return devices
    }

    private static func verifyWLEDDevice(
        address: String,
        port: Int,
        httpClient: any WLEDHTTPClient
    ) async -> WLEDDevice? {
        do {
            let info = try await httpClient.getInfo(from: address, port: port)
            guard isWLEDInfo(info) else {
                return nil
            }

            let resolvedAddress = info.ip.flatMap(NetworkAddressValidator.normalizeIPv4Address) ?? address
            let device = WLEDDevice(
                id: info.mac.isEmpty ? "scan-\(resolvedAddress)" : info.mac,
                address: resolvedAddress,
                port: port,
                name: info.name,
                isOnline: true,
                lastSeen: Date()
            )

            networkLogger.logEvent("discovery.scan.wled.verified", details: [
                "name": info.name,
                "address": resolvedAddress,
                "port": String(port),
                "version": info.ver,
                "mac": info.mac
            ])

            return device
        } catch {
            return nil
        }
    }

    private static func isWLEDInfo(_ info: WLEDInfoResponse) -> Bool {
        return info.ver.contains("0.") || info.ver.lowercased().contains("wled")
    }

    static func candidateIPv4Addresses(
        from localAddresses: [String],
        priorityAddresses: [String] = []
    ) -> [String] {
        let normalizedLocalAddresses = Set(localAddresses.compactMap(NetworkAddressValidator.normalizeIPv4Address))
        var seen = Set<String>()
        var candidates: [String] = []

        for address in priorityAddresses {
            guard let normalizedAddress = NetworkAddressValidator.normalizeIPv4Address(address),
                  isPrivateIPv4Address(normalizedAddress),
                  seen.insert(normalizedAddress).inserted else {
                continue
            }

            candidates.append(normalizedAddress)
        }

        for address in priorityAddresses + localAddresses {
            guard isPrivateIPv4Address(address),
                  let octets = ipv4Octets(address) else {
                continue
            }

            let prefix = "\(octets[0]).\(octets[1]).\(octets[2])"
            for host in 1...254 {
                let candidate = "\(prefix).\(host)"
                guard !normalizedLocalAddresses.contains(candidate) else { continue }
                if seen.insert(candidate).inserted {
                    candidates.append(candidate)
                }
            }
        }

        return candidates
    }

    private static func isPrivateIPv4Address(_ address: String) -> Bool {
        guard let octets = ipv4Octets(address) else { return false }

        if octets[0] == 10 {
            return true
        }

        if octets[0] == 172 && (16...31).contains(octets[1]) {
            return true
        }

        return octets[0] == 192 && octets[1] == 168
    }

    private static func ipv4Octets(_ address: String) -> [Int]? {
        guard let normalized = NetworkAddressValidator.normalizeIPv4Address(address) else {
            return nil
        }

        let octets = normalized.split(separator: ".").compactMap { Int($0) }
        return octets.count == 4 ? octets : nil
    }

    public static func localIPv4Addresses() -> [String] {
        var interfaceAddresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaceAddresses) == 0, let firstAddress = interfaceAddresses else {
            return []
        }
        defer { freeifaddrs(interfaceAddresses) }

        var addresses: [String] = []
        var pointer: UnsafeMutablePointer<ifaddrs>? = firstAddress

        while let currentPointer = pointer {
            defer { pointer = currentPointer.pointee.ifa_next }

            let interface = currentPointer.pointee
            let flags = Int32(interface.ifa_flags)
            guard flags & IFF_UP != 0,
                  flags & IFF_LOOPBACK == 0,
                  let socketAddress = interface.ifa_addr,
                  socketAddress.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }

            var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                socketAddress,
                socklen_t(socketAddress.pointee.sa_len),
                &hostBuffer,
                socklen_t(hostBuffer.count),
                nil,
                0,
                NI_NUMERICHOST
            )

            if result == 0 {
                let bytes = hostBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
                addresses.append(String(decoding: bytes, as: UTF8.self))
            }
        }

        return addresses
    }
}
