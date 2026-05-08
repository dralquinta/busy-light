import XCTest

final class InfoPlistNetworkPermissionTests: XCTestCase {
    func testAppInfoPlistDeclaresLocalNetworkAccessForWLED() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let packageRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let plistURL = packageRoot.appendingPathComponent("Sources/BusyLight/Resources/Info.plist")
        let plistData = try Data(contentsOf: plistURL)

        guard let plist = try PropertyListSerialization.propertyList(
            from: plistData,
            options: [],
            format: nil
        ) as? [String: Any] else {
            XCTFail("Info.plist should be a dictionary")
            return
        }

        let usageDescription = plist["NSLocalNetworkUsageDescription"] as? String
        XCTAssertEqual(
            usageDescription,
            "BusyLight scans your local network and connects to your WLED presence light."
        )

        let bonjourServices = plist["NSBonjourServices"] as? [String]
        XCTAssertEqual(bonjourServices, ["_http._tcp."])
    }

    func testAppInfoPlistAllowsLocalHttpForWLED() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let packageRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let plistURL = packageRoot.appendingPathComponent("Sources/BusyLight/Resources/Info.plist")
        let plistData = try Data(contentsOf: plistURL)

        guard let plist = try PropertyListSerialization.propertyList(
            from: plistData,
            options: [],
            format: nil
        ) as? [String: Any] else {
            XCTFail("Info.plist should be a dictionary")
            return
        }

        let ats = plist["NSAppTransportSecurity"] as? [String: Any]
        XCTAssertEqual(ats?["NSAllowsLocalNetworking"] as? Bool, true)
    }
}
