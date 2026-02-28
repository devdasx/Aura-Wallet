// MARK: - APIError.swift
// Bitcoin AI Wallet
//
// Comprehensive error types for the network layer.
// Each case maps to a specific failure scenario that can occur during
// HTTP communication, WebSocket messaging, or response parsing.
// Provides human-readable descriptions and retry eligibility.
//
// Platform: iOS 17.0+
// Framework: Foundation

import Foundation

// MARK: - APIError

/// Unified error type for all network operations in the Bitcoin AI Wallet.
///
/// Every network call surfaces failures through this enum so that upstream
/// consumers (view models, services) can pattern-match on specific cases
/// and present context-appropriate UI or trigger automatic recovery.
enum APIError: Error, LocalizedError, Equatable {

    // MARK: - Request Construction

    /// The URL could not be constructed from the endpoint definition.
    case invalidURL

    /// The request payload or parameters are malformed.
    case invalidRequest

    // MARK: - Response Validation

    /// The server returned a response that is not a valid `HTTPURLResponse`.
    case invalidResponse

    /// The server returned an HTTP error status code.
    /// - Parameters:
    ///   - statusCode: The HTTP status code (e.g. 404, 500).
    ///   - message: An optional human-readable message extracted from the response body.
    case httpError(statusCode: Int, message: String?)

    // MARK: - Parsing

    /// The response body could not be decoded into the expected `Decodable` type.
    /// - Parameter underlying: The original `DecodingError` from `JSONDecoder`.
    case decodingError(underlying: Error)

    // MARK: - Transport

    /// A transport-level error occurred (DNS failure, connection reset, TLS handshake, etc.).
    /// - Parameter underlying: The original `URLError` or system error.
    case networkError(underlying: Error)

    /// The request exceeded the configured timeout interval.
    case timeout

    /// The device has no active network connection.
    case noConnection

    // MARK: - Server-Side

    /// The server returned 503 Service Unavailable or is otherwise unreachable.
    case serverUnavailable

    /// The server returned 429 Too Many Requests.
    case rateLimited(retryAfter: TimeInterval?)

    /// The server returned 401 Unauthorized or 403 Forbidden.
    case unauthorized

    // MARK: - WebSocket

    /// The WebSocket connection was closed unexpectedly.
    /// - Parameter code: The close code received from the server, if available.
    case webSocketDisconnected(code: URLSessionWebSocketTask.CloseCode?)

    /// A WebSocket message could not be parsed.
    case webSocketMessageParsingFailed

    // MARK: - Catch-All

    /// An error that does not fit any other case.
    /// - Parameter message: A free-form description of what went wrong.
    case unknown(message: String)

    // MARK: - LocalizedError Conformance

    /// A human-readable description suitable for display in UI alerts.
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The request URL is invalid. Please check the server configuration."

        case .invalidRequest:
            return "The request could not be constructed. Please try again."

        case .invalidResponse:
            return "The server returned an unexpected response format."

        case .httpError(let statusCode, let message):
            if let message = message {
                return "Server error (\(statusCode)): \(message)"
            }
            return "Server returned an error (HTTP \(statusCode))."

        case .decodingError(let underlying):
            return "Failed to process the server response: \(underlying.localizedDescription)"

        case .networkError(let underlying):
            return "A network error occurred: \(underlying.localizedDescription)"

        case .timeout:
            return "The request timed out. Please check your connection and try again."

        case .noConnection:
            return "No internet connection. Please check your network settings."

        case .serverUnavailable:
            return "The server is temporarily unavailable. Please try again later."

        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return "Too many requests. Please wait \(Int(seconds)) seconds before retrying."
            }
            return "Too many requests. Please wait a moment before retrying."

        case .unauthorized:
            return "Authentication failed. Please check your credentials."

        case .webSocketDisconnected(let code):
            if let code = code {
                return "Real-time connection was closed (code: \(code.rawValue))."
            }
            return "Real-time connection was closed unexpectedly."

        case .webSocketMessageParsingFailed:
            return "Failed to parse a real-time update message."

        case .unknown(let message):
            return message
        }
    }

    // MARK: - Retry Eligibility

    /// Indicates whether the error is transient and the request should be retried
    /// with exponential backoff.
    ///
    /// Non-retryable errors (e.g. invalid URL, decoding failures) represent
    /// programming errors or permanent server-side issues that will not resolve
    /// on their own.
    var isRetryable: Bool {
        switch self {
        case .timeout,
             .noConnection,
             .serverUnavailable,
             .networkError:
            return true

        case .rateLimited:
            return true

        case .httpError(let statusCode, _):
            // 5xx errors are typically transient; 408 is Request Timeout
            return statusCode >= 500 || statusCode == 408

        case .webSocketDisconnected:
            return true

        case .invalidURL,
             .invalidRequest,
             .invalidResponse,
             .decodingError,
             .unauthorized,
             .webSocketMessageParsingFailed,
             .unknown:
            return false
        }
    }

    // MARK: - Equatable Conformance

    /// Custom equality that ignores associated `Error` values (which are not `Equatable`).
    static func == (lhs: APIError, rhs: APIError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidURL, .invalidURL),
             (.invalidRequest, .invalidRequest),
             (.invalidResponse, .invalidResponse),
             (.timeout, .timeout),
             (.noConnection, .noConnection),
             (.serverUnavailable, .serverUnavailable),
             (.unauthorized, .unauthorized),
             (.webSocketMessageParsingFailed, .webSocketMessageParsingFailed):
            return true

        case (.httpError(let lCode, let lMsg), .httpError(let rCode, let rMsg)):
            return lCode == rCode && lMsg == rMsg

        case (.rateLimited(let lRetry), .rateLimited(let rRetry)):
            return lRetry == rRetry

        case (.webSocketDisconnected(let lCode), .webSocketDisconnected(let rCode)):
            return lCode == rCode

        case (.unknown(let lMsg), .unknown(let rMsg)):
            return lMsg == rMsg

        case (.decodingError, .decodingError),
             (.networkError, .networkError):
            // Cannot compare underlying errors; treat as equal by case
            return true

        default:
            return false
        }
    }
}

// MARK: - URLError Mapping

extension APIError {

    /// Maps a `URLError` to the most appropriate `APIError` case.
    ///
    /// - Parameter urlError: The `URLError` thrown by `URLSession`.
    /// - Returns: A semantically equivalent `APIError`.
    static func from(urlError: URLError) -> APIError {
        switch urlError.code {
        case .timedOut:
            return .timeout

        case .notConnectedToInternet,
             .dataNotAllowed:
            return .noConnection

        case .networkConnectionLost:
            return .networkError(underlying: urlError)

        case .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed:
            return .serverUnavailable

        case .secureConnectionFailed,
             .serverCertificateUntrusted,
             .serverCertificateHasBadDate,
             .serverCertificateNotYetValid,
             .serverCertificateHasUnknownRoot,
             .clientCertificateRejected:
            return .networkError(underlying: urlError)

        case .cancelled:
            return .unknown(message: "The request was cancelled.")

        default:
            return .networkError(underlying: urlError)
        }
    }
}
