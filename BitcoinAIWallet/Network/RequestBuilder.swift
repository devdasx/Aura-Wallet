// MARK: - RequestBuilder.swift
// Bitcoin AI Wallet
//
// Constructs URLRequest instances from endpoint definitions.
// Centralizes URL assembly, header injection, and body attachment
// so that callers only provide high-level intent (endpoint + optional body).
//
// Platform: iOS 17.0+
// Framework: Foundation

import Foundation

// MARK: - EndpointProtocol

/// Defines the shape of an API endpoint.
///
/// Types conforming to this protocol describe everything needed to construct
/// an HTTP request: base URL, path, method, query parameters, and headers.
/// Both `BlockbookEndpoint` (in `BlockbookEndpoints.swift`) and any future
/// endpoint enums should conform to this protocol.
protocol EndpointProtocol: Sendable {
    var baseURL: URL { get }
    var path: String { get }
    var method: HTTPMethod { get }
    var queryItems: [URLQueryItem]? { get }
    var headers: [String: String]? { get }
}

// MARK: - RetryConfiguration

/// Configuration governing retry behaviour with exponential backoff.
///
/// Used by `HTTPClient` to determine when and how long to wait before
/// retrying a failed request.
struct RetryConfiguration: Sendable {

    // MARK: - Properties

    /// Maximum number of automatic retries for retryable errors.
    let maxAttempts: Int

    /// Base delay (in seconds) for the first retry. Subsequent retries use exponential backoff.
    let baseDelay: TimeInterval

    /// Maximum delay (in seconds) between retries, capping the exponential growth.
    let maxDelay: TimeInterval

    /// A jitter factor (0.0 ... 1.0) added to retry delays to decorrelate concurrent retries.
    let jitterFactor: Double

    // MARK: - Presets

    /// The production retry configuration.
    static let `default` = RetryConfiguration(
        maxAttempts: 3,
        baseDelay: 1.0,
        maxDelay: 30.0,
        jitterFactor: 0.25
    )

    /// A configuration optimised for unit and integration tests.
    static let testing = RetryConfiguration(
        maxAttempts: 1,
        baseDelay: 0.1,
        maxDelay: 0.5,
        jitterFactor: 0.0
    )

    // MARK: - Backoff Calculation

    /// Calculate the delay for a retry attempt using exponential backoff with jitter.
    ///
    /// Formula: `min(maxDelay, baseDelay * 2^attempt) * (1 + random(0, jitterFactor))`
    ///
    /// - Parameter attempt: The zero-based retry attempt index.
    /// - Returns: The delay in seconds.
    func delay(forAttempt attempt: Int) -> TimeInterval {
        let exponentialDelay = baseDelay * pow(2.0, Double(attempt))
        let cappedDelay = min(exponentialDelay, maxDelay)

        // Add jitter to decorrelate concurrent retries
        let jitter = cappedDelay * jitterFactor * Double.random(in: 0...1)

        return cappedDelay + jitter
    }
}

// MARK: - RequestBuilder

/// Stateless factory that assembles `URLRequest` instances from endpoint definitions.
///
/// All methods are static and pure -- they carry no mutable state.
///
/// ```swift
/// let request = try RequestBuilder.build(
///     baseURL: config.blockbookBaseURL,
///     endpoint: .address("bc1q...", details: "txs", page: 1, pageSize: 25)
/// )
/// ```
struct RequestBuilder {

    // MARK: - Build from BlockbookEndpoint

    /// Build a complete `URLRequest` from a `BlockbookEndpoint`.
    ///
    /// - Parameters:
    ///   - baseURL: The scheme + host to prepend to the endpoint path.
    ///   - endpoint: The `BlockbookEndpoint` describing the request.
    ///   - body: Optional request body data.
    ///   - timeout: Request timeout interval. Defaults to the value from `APIConfiguration.default`.
    /// - Returns: A fully-configured `URLRequest`.
    /// - Throws: `APIError.invalidURL` if the URL cannot be constructed.
    static func build(
        baseURL: URL,
        endpoint: BlockbookEndpoint,
        body: Data? = nil,
        timeout: TimeInterval = APIConfiguration.default.requestTimeout
    ) throws -> URLRequest {
        let url = try buildURL(
            base: baseURL,
            path: endpoint.path,
            queryItems: endpoint.queryItems
        )

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.timeoutInterval = timeout

        // Apply default headers
        let defaults = defaultHeaders()
        for (key, value) in defaults {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Apply endpoint-specific headers (override defaults if needed)
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

    // MARK: - Build from EndpointProtocol

    /// Build a complete `URLRequest` from a generic `EndpointProtocol` conformance.
    ///
    /// - Parameters:
    ///   - endpoint: Any type conforming to `EndpointProtocol`.
    ///   - body: Optional request body data.
    ///   - timeout: Request timeout interval. Defaults to the value from `APIConfiguration.default`.
    /// - Returns: A fully-configured `URLRequest`.
    /// - Throws: `APIError.invalidURL` if the URL cannot be constructed.
    static func build(
        endpoint: any EndpointProtocol,
        body: Data? = nil,
        timeout: TimeInterval = APIConfiguration.default.requestTimeout
    ) throws -> URLRequest {
        let url = try buildURL(
            base: endpoint.baseURL,
            path: endpoint.path,
            queryItems: endpoint.queryItems
        )

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.timeoutInterval = timeout

        // Apply default headers
        let defaults = defaultHeaders()
        for (key, value) in defaults {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Apply endpoint-specific headers
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

    // MARK: - URL Construction

    /// Assemble a complete URL from base, path, and optional query items.
    ///
    /// - Parameters:
    ///   - base: The base URL (scheme + host).
    ///   - path: The path component to append.
    ///   - queryItems: Optional URL query parameters.
    /// - Returns: The fully-qualified URL.
    /// - Throws: `APIError.invalidURL` if `URLComponents` cannot produce a valid URL.
    static func buildURL(
        base: URL,
        path: String,
        queryItems: [URLQueryItem]?
    ) throws -> URL {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: true) else {
            throw APIError.invalidURL
        }

        // Append path, ensuring no double-slashes
        let basePath = components.path.hasSuffix("/")
            ? String(components.path.dropLast())
            : components.path
        let endpointPath = path.hasPrefix("/") ? path : "/\(path)"
        components.path = basePath + endpointPath

        // Attach query items
        if let queryItems = queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw APIError.invalidURL
        }

        return url
    }

    // MARK: - Default Headers

    /// Returns the set of headers sent with every API request.
    ///
    /// Includes Content-Type, Accept, User-Agent, and cache directives.
    ///
    /// - Returns: A dictionary of header name-value pairs.
    static func defaultHeaders() -> [String: String] {
        return [
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": APIConfiguration.default.userAgent,
            "Accept-Encoding": "gzip, deflate",
            "Cache-Control": "no-cache"
        ]
    }
}

// MARK: - BlockbookEndpoint + EndpointProtocol

extension BlockbookEndpoint: EndpointProtocol {

    /// The base URL defaults to the mainnet Blockbook instance.
    ///
    /// In practice, the `RequestBuilder.build(baseURL:endpoint:)` overload
    /// is preferred so that the base URL comes from `APIConfiguration` rather
    /// than this hardcoded default.
    var baseURL: URL {
        APIConfiguration.default.blockbookBaseURL
    }

    /// Additional headers specific to this endpoint (beyond the defaults).
    var headers: [String: String]? {
        switch self {
        case .sendTransaction:
            return ["Content-Type": "text/plain"]
        default:
            return nil
        }
    }
}
