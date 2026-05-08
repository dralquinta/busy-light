import XCTest
import Network
@testable import BusyLightCore

final class HTTPAdapterTests: XCTestCase {
    func testWledSessionConfigurationBypassesProxyAndCache() {
        let configuration = HTTPAdapter.makeWLEDSessionConfiguration(timeoutMilliseconds: 2_500)

        XCTAssertEqual(configuration.timeoutIntervalForRequest, 2.5)
        XCTAssertEqual(configuration.timeoutIntervalForResource, 2.5)
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertNil(configuration.urlCache)

        let proxySettings = configuration.connectionProxyDictionary as? [String: Bool]
        XCTAssertEqual(proxySettings?[kCFNetworkProxiesHTTPEnable as String], false)
        XCTAssertEqual(proxySettings?[kCFNetworkProxiesHTTPSEnable as String], false)
        XCTAssertEqual(proxySettings?[kCFNetworkProxiesProxyAutoConfigEnable as String], false)
    }

    func testRawHTTPParametersBypassProxyPACResolution() {
        let parameters = HTTPAdapter.makeRawHTTPParameters()

        XCTAssertTrue(parameters.preferNoProxies)
    }

    func testRawHTTPResponseIsCompleteWhenContentLengthBodyHasArrived() throws {
        let response = Data("""
        HTTP/1.1 200 OK\r
        Content-Length: 15\r
        Content-Type: application/json\r
        Connection: keep-alive\r
        \r
        {"ver":"0.15"}
        """.utf8)

        let completeResponse = HTTPAdapter.completeRawHTTPResponseData(from: response)

        XCTAssertEqual(completeResponse, response)
        let parsedResponse = try HTTPAdapter.parseRawHTTPResponse(response)
        XCTAssertEqual(parsedResponse.statusCode, 200)
        XCTAssertEqual(String(data: parsedResponse.body, encoding: .utf8), #"{"ver":"0.15"}"#)
    }

    func testRawHTTPResponseWaitsForFullContentLengthBody() {
        let partialResponse = Data("""
        HTTP/1.1 200 OK\r
        Content-Length: 15\r
        Content-Type: application/json\r
        Connection: keep-alive\r
        \r
        {"ver":
        """.utf8)

        XCTAssertNil(HTTPAdapter.completeRawHTTPResponseData(from: partialResponse))
    }
}
