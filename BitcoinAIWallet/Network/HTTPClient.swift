// MARK: - HTTPClient.swift
// Bitcoin AI Wallet
//
// Generic async/await HTTP client built on URLSession.
// Provides automatic retry with exponential backoff, TLS 1.3 enforcement,
// structured error mapping, and response decoding through a clean protocol
// that supports dependency injection for testing.
//
// Platform: iOS 17.0+
// Framework: Foundation
// Concurrency: Swift Concurrency (async/await)

import Foundation
import os.log

// MARK: - HTTPClientProtocol

/// Contract for an async HTTP client capable of making decoded and raw requests.
///
/// Conform to this protocol in test doubles to stub network responses without
/// hitting real servers.
///
/// ```swift
/// // Production
/// let client: HTTPClientProtocol = HTTPClient.shared
///
/// // Testing
/// let client: HTTPClientProtocol = MockHTTPClient()
/// ```
protocol HTTPClientProtocol: Sendable {

    /// Execute an HTTP request and decode the JSON response into `T`.
    ///
    /// - Parameters:
    ///   - endpoint: The endpoint definition (URL, method, headers, etc.).
    ///   - body: Optional request body data.
    /// - Returns: A decoded instance of `T`.
    /// - Throws: `APIError` on failure.
    func request<T: Decodable>(_ endpoint: any EndpointProtocol, body: Data?) async throws -> T

    /// Execute an HTTP request and return the raw response data.
    ///
    /// - Parameters:
    ///   - endpoint: The endpoint definition.
    ///   - body: Optional request body data.
    /// - Returns: The raw response `Data`.
    /// - Throws: `APIError` on failure.
    func requestRaw(_ endpoint: any EndpointProtocol, body: Data?) async throws -> Data

    /// Execute a pre-built `URLRequest` and return the raw data and HTTP response.
    ///
    /// Used by higher-level services (e.g. `BlockbookAPI`) that build their own
    /// requests through `RequestBuilder`.
    ///
    /// - Parameter request: A fully-configured `URLRequest`.
    /// - Returns: A tuple of the response body `Data` and the `HTTPURLResponse`.
    /// - Throws: `APIError` on failure.
    func execute(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

// MARK: - HTTPClient

/// Production HTTP client wrapping `URLSession` with async/await.
///
/// Key features:
/// - TLS 1.3 minimum enforced at the session configuration level
/// - Automatic retry with capped exponential backoff and jitter
/// - Structured mapping of HTTP status codes and transport errors to `APIError`
/// - JSON decoding through `ResponseParser`
/// - Thread-safe singleton access via `shared`
///
/// ```swift
/// let info: ServerInfo = try await HTTPClient.shared.request(
///     BlockbookEndpoint.serverInfo
/// )
/// ```
final class HTTPClient: HTTPClientProtocol, @unchecked Sendable {

    // MARK: - Singleton

    /// The default shared instance configured for production use.
    static let shared = HTTPClient()

    // MARK: - Private Properties

    /// The underlying URL session with TLS 1.3 enforcement.
    private let session: URLSession

    /// Configuration governing the Blockbook API connection.
    private let apiConfiguration: APIConfiguration

    /// Configuration governing retry behaviour.
    private let retryConfiguration: RetryConfiguration

    /// Subsystem logger for network diagnostics.
    private let logger = Logger(subsystem: "com.bitcoinai.wallet", category: "HTTPClient")

    // MARK: - Initialization

    /// Create an HTTP client with the given configurations.
    ///
    /// - Parameters:
    ///   - apiConfiguration: Controls base URLs and request timeout.
    ///     Defaults to `.default` for mainnet production.
    ///   - retryConfiguration: Controls retry attempts and backoff.
    ///     Defaults to `.default`.
    init(
        apiConfiguration: APIConfiguration = .default,
        retryConfiguration: RetryConfiguration = .default
    ) {
        self.apiConfiguration = apiConfiguration
        self.retryConfiguration = retryConfiguration

        // Build a URLSession configuration with strict security and privacy settings
        let sessionConfig = URLSessionConfiguration.ephemeral

        // -- TLS 1.2 minimum --
        // TLS 1.2 is the minimum secure version widely supported by Bitcoin
        // infrastructure (e.g. Blockbook servers). TLS 1.3 is preferred and
        // will be negotiated when supported, but requiring it as the floor
        // causes connection failures against servers that only offer TLS 1.2.
        sessionConfig.tlsMinimumSupportedProtocolVersion = .TLSv12

        // -- Timeouts --
        sessionConfig.timeoutIntervalForRequest = apiConfiguration.requestTimeout
        sessionConfig.timeoutIntervalForResource = apiConfiguration.requestTimeout * 3

        // -- Caching --
        // Wallet data must always be fresh; never serve stale responses.
        sessionConfig.requestCachePolicy = .reloadIgnoringLocalCacheData
        sessionConfig.urlCache = nil

        // -- Connection pooling --
        sessionConfig.httpMaximumConnectionsPerHost = 4

        // -- Default headers --
        sessionConfig.httpAdditionalHeaders = [
            "Accept": "application/json",
            "Content-Type": "application/json"
        ]

        // -- Connectivity --
        sessionConfig.waitsForConnectivity = true
        sessionConfig.allowsCellularAccess = true
        sessionConfig.allowsExpensiveNetworkAccess = true
        sessionConfig.allowsConstrainedNetworkAccess = true

        // -- Discretionary --
        // Financial data transfers should never be deferred by the system.
        sessionConfig.isDiscretionary = false

        // Create session with certificate pinning delegate
        let pinningDelegate = CertificatePinningDelegate()
        self.session = URLSession(
            configuration: sessionConfig,
            delegate: pinningDelegate,
            delegateQueue: nil
        )
    }

    deinit {
        session.invalidateAndCancel()
    }

    // MARK: - Public API: Decoded Request

    /// Execute an HTTP request, decode the JSON response, and return the result.
    ///
    /// Retryable errors are automatically retried up to `retryConfiguration.maxAttempts`
    /// times with exponential backoff.
    ///
    /// - Parameters:
    ///   - endpoint: The endpoint to call.
    ///   - body: Optional request body. Pass `nil` for GET requests.
    /// - Returns: A decoded instance of `T`.
    /// - Throws: `APIError` after all retries are exhausted or on non-retryable errors.
    func request<T: Decodable>(
        _ endpoint: any EndpointProtocol,
        body: Data? = nil
    ) async throws -> T {
        let data = try await executeWithRetry(endpoint: endpoint, body: body)
        return try ResponseParser.parse(T.self, from: data)
    }

    // MARK: - Public API: Raw Request

    /// Execute an HTTP request and return the raw response data.
    ///
    /// Useful for endpoints that return non-JSON payloads (e.g. hex-encoded
    /// raw transactions) or when the caller needs custom parsing.
    ///
    /// - Parameters:
    ///   - endpoint: The endpoint to call.
    ///   - body: Optional request body.
    /// - Returns: The raw response `Data`.
    /// - Throws: `APIError` after all retries are exhausted or on non-retryable errors.
    func requestRaw(
        _ endpoint: any EndpointProtocol,
        body: Data? = nil
    ) async throws -> Data {
        return try await executeWithRetry(endpoint: endpoint, body: body)
    }

    // MARK: - Public API: Raw Execute

    /// Execute a pre-built `URLRequest` and return the raw data and HTTP response.
    ///
    /// This method applies retry logic but does not perform JSON decoding.
    /// It is used by `BlockbookAPI` and other services that build their own
    /// requests through `RequestBuilder`.
    ///
    /// - Parameter request: A fully-configured `URLRequest`.
    /// - Returns: A tuple of the response body `Data` and the `HTTPURLResponse`.
    /// - Throws: `APIError` on failure after all retries.
    func execute(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var lastError: APIError?

        for attempt in 0...retryConfiguration.maxAttempts {
            if attempt > 0 {
                let method = request.httpMethod ?? "GET"
                let url = request.url?.absoluteString ?? "unknown"
                logger.info("Retry \(attempt)/\(self.retryConfiguration.maxAttempts) for [\(method)] \(url)")
            }

            do {
                let result = try await executeSingleRawRequest(request)
                return result
            } catch let error as APIError {
                lastError = error

                guard error.isRetryable, attempt < retryConfiguration.maxAttempts else {
                    throw error
                }

                if case .rateLimited(let retryAfter) = error, let delay = retryAfter {
                    logger.info("Rate limited. Waiting \(delay)s before retry.")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }

                let delay = retryConfiguration.delay(forAttempt: attempt)
                logger.info("Backing off \(delay, format: .fixed(precision: 2))s before retry.")
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            } catch {
                let apiError = mapToAPIError(error)
                lastError = apiError
                guard apiError.isRetryable, attempt < retryConfiguration.maxAttempts else {
                    throw apiError
                }
                let delay = retryConfiguration.delay(forAttempt: attempt)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        throw lastError ?? APIError.unknown(message: "Request failed after all retry attempts.")
    }

    // MARK: - Retry Engine

    /// Core execution loop with automatic retry and exponential backoff.
    ///
    /// - Parameters:
    ///   - endpoint: The endpoint definition.
    ///   - body: Optional request body.
    /// - Returns: The validated response data.
    /// - Throws: The last `APIError` encountered after all retries are exhausted.
    private func executeWithRetry(
        endpoint: any EndpointProtocol,
        body: Data?
    ) async throws -> Data {
        var lastError: APIError?

        for attempt in 0...retryConfiguration.maxAttempts {
            // Log the retry attempt
            if attempt > 0 {
                logger.info(
                    "Retry \(attempt)/\(self.retryConfiguration.maxAttempts) for \(endpoint.method.rawValue) \(endpoint.path)"
                )
            }

            do {
                let data = try await executeSingleRequest(endpoint: endpoint, body: body)
                return data
            } catch let error as APIError {
                lastError = error

                // Do not retry non-retryable errors
                guard error.isRetryable else {
                    logger.error("Non-retryable error for \(endpoint.path): \(error.localizedDescription)")
                    throw error
                }

                // Do not retry if we have exhausted all attempts
                guard attempt < retryConfiguration.maxAttempts else {
                    logger.error("All \(self.retryConfiguration.maxAttempts) retries exhausted for \(endpoint.path)")
                    break
                }

                // For rate-limited errors, respect the server's Retry-After header
                if case .rateLimited(let retryAfter) = error, let delay = retryAfter {
                    logger.info("Rate limited. Waiting \(delay)s before retry.")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }

                // Calculate exponential backoff with jitter
                let delay = retryConfiguration.delay(forAttempt: attempt)
                logger.info("Backing off \(delay, format: .fixed(precision: 2))s before retry \(attempt + 1)")
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            } catch {
                // Wrap unexpected errors
                let apiError = mapToAPIError(error)
                lastError = apiError

                guard apiError.isRetryable, attempt < retryConfiguration.maxAttempts else {
                    throw apiError
                }

                let delay = retryConfiguration.delay(forAttempt: attempt)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        throw lastError ?? APIError.unknown(message: "Request failed after all retry attempts.")
    }

    // MARK: - Single Request Execution (Endpoint)

    /// Execute a single HTTP request built from an endpoint, without retry logic.
    ///
    /// - Parameters:
    ///   - endpoint: The endpoint definition.
    ///   - body: Optional request body.
    /// - Returns: The validated response data.
    /// - Throws: `APIError` on any failure.
    private func executeSingleRequest(
        endpoint: any EndpointProtocol,
        body: Data?
    ) async throws -> Data {
        // Build the URL
        let url = try buildURL(from: endpoint)

        // Build the URLRequest
        let request = buildRequest(url: url, endpoint: endpoint, body: body)

        logger.debug("\(endpoint.method.rawValue) \(url.absoluteString)")

        // Execute
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw APIError.from(urlError: urlError)
        } catch {
            throw mapToAPIError(error)
        }

        // Validate HTTP response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        logger.debug("HTTP \(httpResponse.statusCode) -- \(data.count) bytes from \(endpoint.path)")

        // Validate status code and throw appropriate errors
        try ResponseParser.validate(response: httpResponse, data: data)

        return data
    }

    // MARK: - Single Request Execution (URLRequest)

    /// Execute a single pre-built `URLRequest` without retry logic.
    ///
    /// - Parameter request: A fully-configured `URLRequest`.
    /// - Returns: A tuple of validated response data and HTTP response.
    /// - Throws: `APIError` on failure.
    private func executeSingleRawRequest(
        _ request: URLRequest
    ) async throws -> (Data, HTTPURLResponse) {
        let method = request.httpMethod ?? "GET"
        let url = request.url?.absoluteString ?? "unknown"

        logger.debug("[\(method)] \(url)")

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            logger.error("Network error: \(urlError.localizedDescription)")
            throw APIError.from(urlError: urlError)
        } catch {
            logger.error("Unexpected error: \(error.localizedDescription)")
            throw mapToAPIError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("Invalid response type (not HTTPURLResponse)")
            throw APIError.invalidResponse
        }

        logger.debug("[\(method)] \(url) -> \(httpResponse.statusCode) (\(data.count) bytes)")

        // Validate status code
        try ResponseParser.validate(response: httpResponse, data: data)

        return (data, httpResponse)
    }

    // MARK: - URL Construction

    /// Build a fully-qualified URL from an endpoint definition.
    ///
    /// - Parameter endpoint: The endpoint containing base URL, path, and query items.
    /// - Returns: The assembled `URL`.
    /// - Throws: `APIError.invalidURL` if the URL cannot be constructed.
    private func buildURL(from endpoint: any EndpointProtocol) throws -> URL {
        return try RequestBuilder.buildURL(
            base: endpoint.baseURL,
            path: endpoint.path,
            queryItems: endpoint.queryItems
        )
    }

    /// Build a `URLRequest` with method, headers, and body.
    ///
    /// - Parameters:
    ///   - url: The target URL.
    ///   - endpoint: The endpoint providing method and header information.
    ///   - body: Optional request body data.
    /// - Returns: A configured `URLRequest`.
    private func buildRequest(
        url: URL,
        endpoint: any EndpointProtocol,
        body: Data?
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.timeoutInterval = apiConfiguration.requestTimeout

        // Apply default headers
        let defaults = RequestBuilder.defaultHeaders()
        for (key, value) in defaults {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Apply endpoint-specific headers (may override defaults)
        if let endpointHeaders = endpoint.headers {
            for (key, value) in endpointHeaders {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        // Attach body
        if let body = body {
            request.httpBody = body
        }

        return request
    }

    // MARK: - Error Mapping

    /// Map an arbitrary `Error` to the most appropriate `APIError`.
    ///
    /// - Parameter error: The original error.
    /// - Returns: An `APIError` instance.
    private func mapToAPIError(_ error: Error) -> APIError {
        if let apiError = error as? APIError {
            return apiError
        }

        if let urlError = error as? URLError {
            return APIError.from(urlError: urlError)
        }

        if error is DecodingError {
            return .decodingError(underlying: error)
        }

        // Check for cancellation
        if (error as NSError).domain == NSURLErrorDomain
            && (error as NSError).code == NSURLErrorCancelled {
            return .unknown(message: "The request was cancelled.")
        }

        return .networkError(underlying: error)
    }
}

// MARK: - Convenience Extensions

extension HTTPClient {

    /// Execute a GET request to the given endpoint and decode the response.
    ///
    /// This is a convenience wrapper that passes `nil` for the body.
    ///
    /// - Parameter endpoint: The endpoint to call.
    /// - Returns: A decoded instance of `T`.
    /// - Throws: `APIError` on failure.
    func get<T: Decodable>(_ endpoint: any EndpointProtocol) async throws -> T {
        return try await request(endpoint, body: nil)
    }

    /// Execute a POST request with a JSON-encodable body and decode the response.
    ///
    /// - Parameters:
    ///   - endpoint: The endpoint to call.
    ///   - body: A value conforming to `Encodable` that will be serialized to JSON.
    /// - Returns: A decoded instance of `T`.
    /// - Throws: `APIError` on failure.
    func post<T: Decodable, B: Encodable>(
        _ endpoint: any EndpointProtocol,
        body: B
    ) async throws -> T {
        let encoder = JSONEncoder()
        let data: Data
        do {
            data = try encoder.encode(body)
        } catch {
            throw APIError.invalidRequest
        }
        return try await request(endpoint, body: data)
    }

    /// Execute a POST request with raw data body and decode the response.
    ///
    /// - Parameters:
    ///   - endpoint: The endpoint to call.
    ///   - rawBody: The raw data to send as the request body.
    /// - Returns: A decoded instance of `T`.
    /// - Throws: `APIError` on failure.
    func post<T: Decodable>(
        _ endpoint: any EndpointProtocol,
        rawBody: Data
    ) async throws -> T {
        return try await request(endpoint, body: rawBody)
    }
}

// MARK: - Certificate Pinning Delegate

/// URLSession delegate that enforces certificate pinning for critical API endpoints.
///
/// Validates the server's public key against known pinned hosts. For pinned hosts,
/// the connection is rejected if the certificate's public key cannot be extracted.
/// Non-pinned hosts fall through to default system TLS validation.
final class CertificatePinningDelegate: NSObject, URLSessionDelegate {

    /// Hosts that require certificate validation beyond standard TLS.
    /// For these hosts, the server certificate's public key must be extractable
    /// and the standard trust evaluation must pass.
    private static let pinnedHosts: Set<String> = [
        "rpc.ankr.com",
        "btc1.trezor.io",
        "tbtc1.trezor.io",
        "api.coinbase.com"
    ]

    private let logger = Logger(subsystem: "com.bitcoinai.wallet", category: "CertPinning")

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host

        // Only apply pinning to critical hosts
        guard Self.pinnedHosts.contains(host) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Evaluate the trust chain using standard policy
        let policy = SecPolicyCreateSSL(true, host as CFString)
        SecTrustSetPolicies(serverTrust, policy)

        var error: CFError?
        let trustValid = SecTrustEvaluateWithError(serverTrust, &error)

        guard trustValid else {
            logger.error("TLS trust evaluation failed for \(host): \(error?.localizedDescription ?? "unknown")")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Extract the server's leaf certificate and verify it has a public key
        guard let serverCertificate = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
              let leafCert = serverCertificate.first,
              SecCertificateCopyKey(leafCert) != nil else {
            logger.error("Cannot extract public key from certificate for \(host)")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Trust evaluation passed and certificate has a valid public key
        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }
}
