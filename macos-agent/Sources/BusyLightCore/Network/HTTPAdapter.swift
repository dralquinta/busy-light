import Foundation
import Network

/// HTTP adapter for WLED JSON API communication.
/// Handles HTTP requests with timeout, retry logic, and structured logging.
public actor HTTPAdapter {
    private let timeoutMilliseconds: Int
    private let maxRetries: Int
    
    public init(timeoutMilliseconds: Int = 500, maxRetries: Int = 3) {
        self.timeoutMilliseconds = timeoutMilliseconds
        self.maxRetries = maxRetries
    }

    public func cancelAllRequests() async {}
    
    // MARK: - Public API
    
    /// Sends a state change request to WLED device to activate a preset.
    /// - Parameters:
    ///   - address: Device IP address or hostname
    ///   - port: Device HTTP port (typically 80)
    ///   - request: State request with preset ID
    /// - Returns: State response from device
    /// - Throws: NetworkError on failure
    public func postState(
        to address: String,
        port: Int,
        request: WLEDStateRequest
    ) async throws -> WLEDStateResponse {
        let bodyData = try JSONEncoder().encode(request)
        
        let startTime = Date()
        let response: WLEDStateResponse = try await executeWithRetry(
            address: address,
            port: port,
            path: "/json/state",
            method: "POST",
            body: bodyData,
            attempt: 1
        )
        let latency = Date().timeIntervalSince(startTime) * 1000 // milliseconds
        
        await MainActor.run {
            networkLogger.logEvent("http.post.state.success", details: [
                "address": address,
                "port": String(port),
                "preset": String(request.ps),
                "latency_ms": String(format: "%.0f", latency)
            ])
        }
        
        return response
    }
    
    /// Retrieves device information from WLED device.
    /// - Parameters:
    ///   - address: Device IP address or hostname
    ///   - port: Device HTTP port (typically 80)
    /// - Returns: Device information
    /// - Throws: NetworkError on failure
    public func getInfo(
        from address: String,
        port: Int
    ) async throws -> WLEDInfoResponse {
        let startTime = Date()
        let response: WLEDInfoResponse = try await executeWithRetry(
            address: address,
            port: port,
            path: "/json/info",
            method: "GET",
            body: nil,
            attempt: 1
        )
        let latency = Date().timeIntervalSince(startTime) * 1000 // milliseconds
        
        await MainActor.run {
            networkLogger.logEvent("http.get.info.success", details: [
                "address": address,
                "port": String(port),
                "name": response.name,
                "version": response.ver,
                "latency_ms": String(format: "%.0f", latency)
            ])
        }
        
        return response
    }
    
    // MARK: - Private Implementation
    
    /// Executes HTTP request with exponential backoff retry logic.
    private func executeWithRetry<T: Decodable>(
        address: String,
        port: Int,
        path: String,
        method: String,
        body: Data?,
        attempt: Int
    ) async throws -> T {
        let url = "http://\(address):\(port)\(path)"
        do {
            return try await execute(
                address: address,
                port: port,
                path: path,
                method: method,
                body: body
            )
        } catch {
            // Don't retry on HTTP errors (4xx, 5xx), only on network/timeout errors
            if case NetworkError.httpError = error {
                throw error
            }
            
            // Check if we should retry
            if attempt >= maxRetries {
                await MainActor.run {
                    networkLogger.logEvent("http.request.failed.max_retries", details: [
                        "url": url,
                        "method": method,
                        "attempts": String(attempt),
                        "error": error.localizedDescription
                    ])
                }
                throw error
            }
            
            // Calculate exponential backoff delay: 100ms, 200ms, 400ms
            let delayMs = 100 * (1 << (attempt - 1)) // 2^(attempt-1) * 100
            
            await MainActor.run {
                networkLogger.logEvent("http.request.retry", details: [
                    "url": url,
                    "method": method,
                    "attempt": String(attempt),
                    "next_delay_ms": String(delayMs),
                    "error": error.localizedDescription
                ])
            }
            
            // Wait before retry
            try await Task.sleep(for: .milliseconds(delayMs))
            
            // Retry
            return try await executeWithRetry(
                address: address,
                port: port,
                path: path,
                method: method,
                body: body,
                attempt: attempt + 1
            )
        }
    }
    
    /// Executes a single HTTP request without retry.
    private func execute<T: Decodable>(
        address: String,
        port: Int,
        path: String,
        method: String,
        body: Data?
    ) async throws -> T {
        let (statusCode, data) = try await executeRawHTTP(
            address: address,
            port: port,
            path: path,
            method: method,
            body: body
        )
        
        // Check HTTP status code
        guard (200...299).contains(statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "No error message"
            throw NetworkError.httpError(statusCode: statusCode, message: message)
        }
        
        // Parse JSON response
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            throw NetworkError.jsonParsingFailed(error)
        }
    }

    private func executeRawHTTP(
        address: String,
        port: Int,
        path: String,
        method: String,
        body: Data?
    ) async throws -> (statusCode: Int, body: Data) {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw NetworkError.invalidURL
        }

        let request = buildHTTPRequest(
            address: address,
            port: port,
            path: path,
            method: method,
            body: body
        )
        let connection = NWConnection(
            host: Self.endpointHost(for: address),
            port: nwPort,
            using: Self.makeRawHTTPParameters()
        )

        let response: Data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            RawHTTPTransaction(
                connection: connection,
                continuation: continuation,
                timeoutMilliseconds: timeoutMilliseconds
            ).start(request: request)
        }

        return try Self.parseRawHTTPResponse(response)
    }

    private nonisolated static func endpointHost(for address: String) -> NWEndpoint.Host {
        if let ipv4Address = IPv4Address(address) {
            return .ipv4(ipv4Address)
        }

        if let ipv6Address = IPv6Address(address) {
            return .ipv6(ipv6Address)
        }

        return .name(address, nil)
    }

    private func buildHTTPRequest(
        address: String,
        port: Int,
        path: String,
        method: String,
        body: Data?
    ) -> Data {
        let hostHeader = port == 80 ? address : "\(address):\(port)"
        var headers = [
            "\(method) \(path) HTTP/1.1",
            "Host: \(hostHeader)",
            "Accept: application/json",
            "Connection: close"
        ]

        if let body {
            headers.append("Content-Type: application/json")
            headers.append("Content-Length: \(body.count)")
        }

        let head = headers.joined(separator: "\r\n") + "\r\n\r\n"
        var request = Data(head.utf8)
        if let body {
            request.append(body)
        }

        return request
    }

    nonisolated static func parseRawHTTPResponse(_ response: Data) throws -> (statusCode: Int, body: Data) {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = response.range(of: separator),
              let headerText = String(data: response[..<headerRange.lowerBound], encoding: .utf8) else {
            throw NetworkError.invalidResponse("Missing HTTP response headers")
        }

        guard let statusLine = headerText.split(separator: "\r\n").first,
              let statusCode = Int(statusLine.split(separator: " ").dropFirst().first ?? "") else {
            throw NetworkError.invalidResponse("Missing HTTP status code")
        }

        let bodyStart = headerRange.upperBound
        let body = Self.isChunkedResponse(headerText)
            ? try Self.decodeChunkedBody(Data(response[bodyStart...]))
            : Data(response[bodyStart...])
        guard !body.isEmpty else {
            throw NetworkError.noData
        }

        return (statusCode, Data(body))
    }

    nonisolated static func completeRawHTTPResponseData(from response: Data) -> Data? {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = response.range(of: separator),
              let headerText = String(data: response[..<headerRange.lowerBound], encoding: .utf8) else {
            return nil
        }

        let bodyStart = headerRange.upperBound

        if let contentLength = Self.contentLength(from: headerText) {
            let expectedEnd = bodyStart + contentLength
            guard response.count >= expectedEnd else {
                return nil
            }

            return Data(response[..<expectedEnd])
        }

        if Self.isChunkedResponse(headerText),
           let terminatorRange = response.range(of: Data("\r\n0\r\n\r\n".utf8), in: bodyStart..<response.endIndex) {
            return Data(response[..<terminatorRange.upperBound])
        }

        return nil
    }

    private nonisolated static func contentLength(from headerText: String) -> Int? {
        for line in headerText.components(separatedBy: "\r\n").dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }

            let name = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard name == "content-length" else { continue }

            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            return Int(value)
        }

        return nil
    }

    private nonisolated static func isChunkedResponse(_ headerText: String) -> Bool {
        for line in headerText.components(separatedBy: "\r\n").dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }

            let name = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard name == "transfer-encoding" else { continue }

            return parts[1].lowercased().contains("chunked")
        }

        return false
    }

    private nonisolated static func decodeChunkedBody(_ data: Data) throws -> Data {
        var index = data.startIndex
        var decoded = Data()
        let lineEnding = Data("\r\n".utf8)

        while index < data.endIndex {
            guard let lineRange = data.range(of: lineEnding, in: index..<data.endIndex),
                  let sizeLine = String(data: data[index..<lineRange.lowerBound], encoding: .utf8) else {
                throw NetworkError.invalidResponse("Malformed chunked response")
            }

            let sizeText = sizeLine.split(separator: ";", maxSplits: 1).first.map(String.init) ?? sizeLine
            guard let chunkSize = Int(sizeText.trimmingCharacters(in: .whitespacesAndNewlines), radix: 16) else {
                throw NetworkError.invalidResponse("Invalid chunk size")
            }

            index = lineRange.upperBound
            if chunkSize == 0 {
                return decoded
            }

            let chunkEnd = index + chunkSize
            guard chunkEnd <= data.endIndex else {
                throw NetworkError.invalidResponse("Incomplete chunk body")
            }

            decoded.append(data[index..<chunkEnd])
            index = chunkEnd

            guard data[index..<data.endIndex].starts(with: lineEnding) else {
                throw NetworkError.invalidResponse("Missing chunk delimiter")
            }
            index += lineEnding.count
        }

        throw NetworkError.invalidResponse("Missing terminating chunk")
    }

    private static func makeSession(timeoutMilliseconds: Int) -> URLSession {
        let config = makeWLEDSessionConfiguration(timeoutMilliseconds: timeoutMilliseconds)
        return URLSession(configuration: config)
    }

    public static func makeWLEDSessionConfiguration(timeoutMilliseconds: Int) -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = TimeInterval(timeoutMilliseconds) / 1000.0
        config.timeoutIntervalForResource = TimeInterval(timeoutMilliseconds) / 1000.0
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: false,
            kCFNetworkProxiesHTTPSEnable as String: false,
            kCFNetworkProxiesProxyAutoConfigEnable as String: false
        ]
        return config
    }

    nonisolated static func makeRawHTTPParameters() -> NWParameters {
        let parameters = NWParameters.tcp
        parameters.preferNoProxies = true
        return parameters
    }
}

extension HTTPAdapter: WLEDHTTPClient {}

private final class RawHTTPState: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var data = Data()
    private var isFinished = false

    func append(_ newData: Data) -> Data? {
        lock.lock()
        data.append(newData)
        let completeData = HTTPAdapter.completeRawHTTPResponseData(from: data)
        lock.unlock()

        return completeData
    }

    func finish() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard !isFinished else {
            return false
        }

        isFinished = true
        return true
    }
}

private final class RawHTTPTransaction: @unchecked Sendable {
    private let connection: NWConnection
    private let continuation: CheckedContinuation<Data, Error>
    private let timeoutMilliseconds: Int
    private let state = RawHTTPState()

    init(
        connection: NWConnection,
        continuation: CheckedContinuation<Data, Error>,
        timeoutMilliseconds: Int
    ) {
        self.connection = connection
        self.continuation = continuation
        self.timeoutMilliseconds = timeoutMilliseconds
    }

    func start(request: Data) {
        connection.stateUpdateHandler = { newState in
            self.handle(newState, request: request)
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(timeoutMilliseconds)) {
            self.finish(.failure(NetworkError.timeout))
        }

        connection.start(queue: .global(qos: .userInitiated))
    }

    private func handle(_ newState: NWConnection.State, request: Data) {
        switch newState {
        case .ready:
            connection.send(content: request, completion: .contentProcessed { error in
                if let error {
                    self.finish(.failure(error))
                } else {
                    self.receiveNext()
                }
            })
        case .failed(let error):
            finish(.failure(error))
        case .cancelled:
            finish(.failure(NetworkError.deviceUnavailable))
        default:
            break
        }
    }

    private func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
            if let error {
                self.finish(.failure(error))
                return
            }

            if let data, !data.isEmpty,
               let completeResponse = self.state.append(data) {
                self.finish(.success(completeResponse))
                return
            }

            if isComplete {
                self.finish(.success(self.state.data))
            } else {
                self.receiveNext()
            }
        }
    }

    private func finish(_ result: Result<Data, Error>) {
        if state.finish() {
            connection.stateUpdateHandler = nil
            connection.cancel()
            continuation.resume(with: result)
        }
    }
}
