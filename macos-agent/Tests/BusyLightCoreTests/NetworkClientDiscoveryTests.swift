import XCTest
@testable import BusyLightCore

@MainActor
final class NetworkClientDiscoveryTests: XCTestCase {
    func testConnectScansLocalNetworkWhenBonjourFindsNoDevices() async {
        let (config, userDefaults, suiteName) = makeConfiguration()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        config.setWledEnableDiscovery(true)

        let scannedDevice = WLEDDevice(
            id: "aabbccddeeff",
            address: "192.168.1.42",
            port: 80,
            name: "BusyLight",
            isOnline: true
        )
        let networkScanner = StubNetworkScanner(devices: [scannedDevice])
        let client = NetworkClient(
            config: config,
            httpClient: RecordingHTTPClient(),
            discovery: StubDeviceDiscovery(devices: []),
            networkScanner: networkScanner
        )

        await client.connect()

        XCTAssertEqual(await networkScanner.scanCallCount, 1)
        XCTAssertEqual(client.devices.map(\.address), ["192.168.1.42"])
        XCTAssertEqual(config.getDeviceNetworkAddresses(), ["192.168.1.42"])
        XCTAssertEqual(config.getDeviceNetworkAddress(), "192.168.1.42")
    }

    func testSendStatePostsToSubnetDiscoveredDevice() async {
        let (config, userDefaults, suiteName) = makeConfiguration()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        config.setWledEnableDiscovery(true)

        let scannedDevice = WLEDDevice(
            id: "aabbccddeeff",
            address: "192.168.1.42",
            port: 80,
            name: "BusyLight",
            isOnline: true
        )
        let httpClient = RecordingHTTPClient()
        let client = NetworkClient(
            config: config,
            httpClient: httpClient,
            discovery: StubDeviceDiscovery(devices: []),
            networkScanner: StubNetworkScanner(devices: [scannedDevice])
        )

        await client.connect()
        await client.sendState(.busy)

        let posts = await httpClient.recordedPosts()
        XCTAssertEqual(posts.map(\.address), ["192.168.1.42"])
        XCTAssertEqual(posts.map(\.port), [80])
        XCTAssertEqual(posts.map(\.presetId), [3])
    }

    func testSubnetScanReplacesStaleConfiguredAddress() async {
        let (config, userDefaults, suiteName) = makeConfiguration()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        config.setWledEnableDiscovery(true)
        config.setDeviceNetworkAddress("192.168.86.247")
        config.setDeviceNetworkAddresses(["192.168.86.247"])

        let actualDevice = WLEDDevice(
            id: "aabbccddeeff",
            address: "192.168.86.33",
            port: 80,
            name: "BusyLight",
            isOnline: true
        )
        let httpClient = RecordingHTTPClient(offlineInfoAddresses: ["192.168.86.247"])
        let client = NetworkClient(
            config: config,
            httpClient: httpClient,
            discovery: StubDeviceDiscovery(devices: []),
            networkScanner: StubNetworkScanner(devices: [actualDevice])
        )

        await client.connect()
        await client.sendState(.available)

        let posts = await httpClient.recordedPosts()
        XCTAssertEqual(client.devices.map(\.address), ["192.168.86.33"])
        XCTAssertEqual(config.getDeviceNetworkAddresses(), ["192.168.86.33"])
        XCTAssertEqual(config.getDeviceNetworkAddress(), "192.168.86.33")
        XCTAssertEqual(posts.map(\.address), ["192.168.86.33"])
    }

    func testConnectDoesNotExposeOfflineConfiguredAddressWhenDiscoveryFindsNothing() async {
        let (config, userDefaults, suiteName) = makeConfiguration()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        config.setWledEnableDiscovery(true)
        config.setDeviceNetworkAddress("192.168.86.247")
        config.setDeviceNetworkAddresses(["192.168.86.247"])

        let client = NetworkClient(
            config: config,
            httpClient: RecordingHTTPClient(offlineInfoAddresses: ["192.168.86.247"]),
            discovery: StubDeviceDiscovery(devices: []),
            networkScanner: StubNetworkScanner(devices: [])
        )
        var callbackDevices: [[WLEDDevice]] = []
        client.onDeviceStatusChanged = { devices in
            callbackDevices.append(devices)
        }

        await client.connect()

        XCTAssertTrue(client.devices.isEmpty)
        XCTAssertEqual(callbackDevices, [[]])
    }

    func testConnectUsesVerifiedConfiguredAddressBeforeSubnetScan() async {
        let (config, userDefaults, suiteName) = makeConfiguration()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        config.setWledEnableDiscovery(true)
        config.setDeviceNetworkAddress("192.168.86.33")
        config.setDeviceNetworkAddresses(["192.168.86.33"])

        let scannedDevice = WLEDDevice(
            id: "scan-device",
            address: "192.168.86.44",
            port: 80,
            name: "OtherLight",
            isOnline: true
        )
        let scanner = StubNetworkScanner(devices: [scannedDevice])
        let client = NetworkClient(
            config: config,
            httpClient: RecordingHTTPClient(),
            discovery: StubDeviceDiscovery(devices: []),
            networkScanner: scanner
        )

        await client.connect()

        XCTAssertEqual(await scanner.scanCallCount, 0)
        XCTAssertEqual(client.devices.map(\.address), ["192.168.86.33"])
        XCTAssertEqual(config.getDeviceNetworkAddresses(), ["192.168.86.33"])
    }

    func testConnectUsesProbeHTTPClientForConfiguredAddressVerification() async {
        let (config, userDefaults, suiteName) = makeConfiguration()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        config.setWledEnableDiscovery(true)
        config.setDeviceNetworkAddress("192.168.86.33")
        config.setDeviceNetworkAddresses(["192.168.86.33"])

        let scanner = StubNetworkScanner(devices: [])
        let client = NetworkClient(
            config: config,
            httpClient: RecordingHTTPClient(offlineInfoAddresses: ["192.168.86.33"]),
            probeHTTPClient: RecordingHTTPClient(),
            discovery: StubDeviceDiscovery(devices: []),
            networkScanner: scanner
        )

        await client.connect()

        XCTAssertEqual(await scanner.scanCallCount, 0)
        XCTAssertEqual(client.devices.map(\.address), ["192.168.86.33"])
    }

    func testSubnetScanPrioritizesConfiguredSubnetWhenConfiguredAddressIsOffline() async {
        let (config, userDefaults, suiteName) = makeConfiguration()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        config.setWledEnableDiscovery(true)
        config.setDeviceNetworkAddress("192.168.86.247")
        config.setDeviceNetworkAddresses(["192.168.86.247"])

        let actualDevice = WLEDDevice(
            id: "actual-device",
            address: "192.168.86.33",
            port: 80,
            name: "BusyLight",
            isOnline: true
        )
        let scanner = StubNetworkScanner(devices: [actualDevice])
        let client = NetworkClient(
            config: config,
            httpClient: RecordingHTTPClient(offlineInfoAddresses: ["192.168.86.247"]),
            discovery: StubDeviceDiscovery(devices: []),
            networkScanner: scanner
        )

        await client.connect()

        XCTAssertEqual(await scanner.scanCallCount, 1)
        XCTAssertEqual(await scanner.priorityAddressesSeen, [["192.168.86.247"]])
        XCTAssertEqual(client.devices.map(\.address), ["192.168.86.33"])
        XCTAssertEqual(config.getDeviceNetworkAddresses(), ["192.168.86.33"])
    }

    func testSubnetScanCandidateListStartsWithPriorityAddress() {
        let candidates = LocalNetworkScanner.candidateIPv4Addresses(
            from: ["192.168.86.10"],
            priorityAddresses: ["192.168.86.33"]
        )

        XCTAssertEqual(candidates.first, "192.168.86.33")
        XCTAssertFalse(candidates.contains("192.168.86.10"))
        XCTAssertEqual(candidates.filter { $0 == "192.168.86.33" }.count, 1)
    }

    func testSendStateScansImmediatelyWhenNoOnlineDevicesExist() async {
        let (config, userDefaults, suiteName) = makeConfiguration()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        config.setWledEnableDiscovery(true)

        let actualDevice = WLEDDevice(
            id: "aabbccddeeff",
            address: "192.168.86.33",
            port: 80,
            name: "BusyLight",
            isOnline: true
        )
        let httpClient = RecordingHTTPClient()
        let scanner = StubNetworkScanner(devices: [actualDevice])
        let client = NetworkClient(
            config: config,
            httpClient: httpClient,
            discovery: StubDeviceDiscovery(devices: []),
            networkScanner: scanner
        )

        await client.sendState(.busy)

        let posts = await httpClient.recordedPosts()
        XCTAssertEqual(await scanner.scanCallCount, 1)
        XCTAssertEqual(client.devices.map(\.address), ["192.168.86.33"])
        XCTAssertEqual(posts.map(\.address), ["192.168.86.33"])
        XCTAssertEqual(posts.map(\.presetId), [3])
    }

    func testConcurrentConnectCallsShareSingleDiscoveryWork() async {
        let (config, userDefaults, suiteName) = makeConfiguration()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        config.setWledEnableDiscovery(true)

        let actualDevice = WLEDDevice(
            id: "actual-device",
            address: "192.168.86.33",
            port: 80,
            name: "BusyLight",
            isOnline: true
        )
        let scanner = StubNetworkScanner(devices: [actualDevice], delayNanoseconds: 100_000_000)
        let client = NetworkClient(
            config: config,
            httpClient: RecordingHTTPClient(),
            discovery: StubDeviceDiscovery(devices: []),
            networkScanner: scanner
        )

        async let firstConnect: Void = client.connect()
        async let secondConnect: Void = client.connect()
        _ = await (firstConnect, secondConnect)

        XCTAssertEqual(await scanner.scanCallCount, 1)
        XCTAssertEqual(client.devices.map(\.address), ["192.168.86.33"])
    }


    private func makeConfiguration() -> (ConfigurationManager, UserDefaults, String) {
        let suiteName = "BusyLightNetworkClientTests.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create UserDefaults suite")
            return (ConfigurationManager(), .standard, suiteName)
        }

        userDefaults.removePersistentDomain(forName: suiteName)
        return (ConfigurationManager(userDefaults: userDefaults), userDefaults, suiteName)
    }
}

@MainActor
private final class StubDeviceDiscovery: WLEDDeviceDiscovering {
    private let devices: [WLEDDevice]

    init(devices: [WLEDDevice]) {
        self.devices = devices
    }

    func discoverDevices(timeout: TimeInterval) async -> [WLEDDevice] {
        return devices
    }
}

private actor StubNetworkScanner: WLEDDeviceScanning {
    private let devices: [WLEDDevice]
    private let delayNanoseconds: UInt64
    private(set) var scanCallCount = 0
    private(set) var priorityAddressesSeen: [[String]] = []

    init(devices: [WLEDDevice], delayNanoseconds: UInt64 = 0) {
        self.devices = devices
        self.delayNanoseconds = delayNanoseconds
    }

    func scanForDevices(port: Int, timeout: TimeInterval, priorityAddresses: [String]) async -> [WLEDDevice] {
        scanCallCount += 1
        priorityAddressesSeen.append(priorityAddresses)
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return devices
    }
}

private actor RecordingHTTPClient: WLEDHTTPClient {
    struct RecordedPost: Equatable {
        let address: String
        let port: Int
        let presetId: Int
    }

    private var posts: [RecordedPost] = []
    private let offlineInfoAddresses: Set<String>

    init(offlineInfoAddresses: Set<String> = []) {
        self.offlineInfoAddresses = offlineInfoAddresses
    }

    func postState(
        to address: String,
        port: Int,
        request: WLEDStateRequest
    ) async throws -> WLEDStateResponse {
        posts.append(RecordedPost(address: address, port: port, presetId: request.ps))
        return WLEDStateResponse(on: true, bri: 128, ps: request.ps)
    }

    func getInfo(from address: String, port: Int) async throws -> WLEDInfoResponse {
        if offlineInfoAddresses.contains(address) {
            throw NetworkError.deviceUnavailable
        }

        return WLEDInfoResponse(
            ver: "0.15.0",
            name: "BusyLight",
            uptime: 1,
            ip: address,
            mac: "aabbccddeeff"
        )
    }

    func cancelAllRequests() async {}

    func recordedPosts() -> [RecordedPost] {
        return posts
    }
}
