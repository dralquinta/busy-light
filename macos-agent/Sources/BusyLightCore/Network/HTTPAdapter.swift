import Foundation

/// HTTP adapter for WLED JSON API communication.
/// Handles HTTP requests with timeout, retry logic, and structured logging.
public actor HTTPAdapter {
    private let session: URLSession
    private let timeoutMilliseconds: Int
    private let maxRetries: Int = 3
    
    public init(timeoutMilliseconds: Int = 500) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = TimeInterval(timeoutMilliseconds) / 1000.0
        config.timeoutIntervalForResource = TimeInterval(timeoutMilliseconds) / 1000.0
        self.session = URLSession(configuration: config)
        self.timeoutMilliseconds = timeoutMilliseconds
    }
    
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
        let url = try buildURL(address: address, port: port, path: "/json/state")
        let bodyData = try JSONEncoder().encode(request)
        
        let startTime = Date()
        let response: WLEDStateResponse = try await executeWithRetry(
            url: url,
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
        let url = try buildURL(address: address, port: port, path: "/json/info")
        
        let startTime = Date()
        let response: WLEDInfoResponse = try await executeWithRetry(
            url: url,
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
        url: URL,
        method: String,
        body: Data?,
        attempt: Int
    ) async throws -> T {
        do {
            return try await execute(url: url, method: method, body: body)
        } catch {
            // Don't retry on HTTP errors (4xx, 5xx), only on network/timeout errors
            if case NetworkError.httpError = error {
                throw error
            }
            
            // Check if we should retry
            if attempt >= maxRetries {
                await MainActor.run {
                    networkLogger.logEvent("http.request.failed.max_retries", details: [
                        "url": url.absoluteString,
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
                    "url": url.absoluteString,
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
                url: url,
                method: method,
                body: body,
                attempt: attempt + 1
            )
        }
    }
    
    /// Executes a single HTTP request without retry.
    private func execute<T: Decodable>(
        url: URL,
        method: String,
        body: Data?
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        if let body = body {
            request.httpBody = body
        }
        
        let (data, urlResponse) = try await session.data(for: request)
        
        guard let httpResponse = urlResponse as? HTTPURLResponse else {
            throw NetworkError.invalidResponse("Not an HTTP response")
        }
        
        // Check HTTP status code
        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "No error message"
            throw NetworkError.httpError(statusCode: httpResponse.statusCode, message: message)
        }
        
        // Parse JSON response
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            throw NetworkError.jsonParsingFailed(error)
        }
    }
    
    /// Builds a complete URL from components.
    private func buildURL(address: String, port: Int, path: String) throws -> URL {
        var components = URLComponents()
        components.scheme = "http"
        components.host = address
        components.port = port
        components.path = path
        
        guard let url = components.url else {
            throw NetworkError.invalidURL
        }
        
        return url
    }
}
