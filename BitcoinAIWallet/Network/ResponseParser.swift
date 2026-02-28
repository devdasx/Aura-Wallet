// MARK: - ResponseParser.swift
// Bitcoin AI Wallet
//
// Validates HTTP responses and decodes JSON payloads into Swift types.
// Centralizes all response-handling logic so that `HTTPClient` and other
// network consumers share a single, consistent parsing pipeline.
//
// Platform: iOS 17.0+
// Framework: Foundation

import Foundation

// MARK: - ResponseParser

/// Validates and parses HTTP responses returned by `URLSession`.
///
/// Usage:
/// ```swift
/// let (data, response) = try await session.data(for: request)
/// try ResponseParser.validate(response: response as! HTTPURLResponse, data: data)
/// let model: MyModel = try ResponseParser.parse(MyModel.self, from: data)
/// ```
struct ResponseParser {

    // MARK: - Private Properties

    /// Shared `JSONDecoder` configured for the Blockbook / standard JSON API conventions.
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            // Try Unix timestamp first (common in Bitcoin APIs)
            if let timestamp = try? container.decode(TimeInterval.self) {
                return Date(timeIntervalSince1970: timestamp)
            }
            // Fall back to ISO 8601
            if let dateString = try? container.decode(String.self) {
                if let date = ISO8601DateFormatter().date(from: dateString) {
                    return date
                }
                // Try ISO 8601 with fractional seconds
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = formatter.date(from: dateString) {
                    return date
                }
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unable to decode date from the provided value."
            )
        }
        return decoder
    }()

    // MARK: - Public API

    /// Decode raw `Data` into a `Decodable` type.
    ///
    /// - Parameters:
    ///   - type: The target `Decodable` type.
    ///   - data: The raw response body bytes.
    /// - Returns: A fully-decoded instance of `T`.
    /// - Throws: `APIError.decodingError` when decoding fails.
    static func parse<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch let decodingError {
            throw APIError.decodingError(underlying: decodingError)
        }
    }

    /// Validate that the HTTP response has an acceptable status code.
    ///
    /// Status codes in the 2xx range are considered successful. All other codes
    /// are mapped to the appropriate `APIError` case.
    ///
    /// - Parameters:
    ///   - response: The `HTTPURLResponse` to validate.
    ///   - data: The response body, used to extract server-provided error messages.
    /// - Throws: An `APIError` when the status code indicates failure.
    static func validate(response: HTTPURLResponse, data: Data) throws {
        let statusCode = response.statusCode

        // 2xx — Success
        guard !(200...299).contains(statusCode) else {
            return
        }

        // Map well-known status codes to specific error cases
        switch statusCode {
        case 401, 403:
            throw APIError.unauthorized

        case 404:
            let message = extractErrorMessage(from: data) ?? "The requested resource was not found."
            throw APIError.httpError(statusCode: statusCode, message: message)

        case 408:
            throw APIError.timeout

        case 429:
            let retryAfter = parseRetryAfterHeader(from: response)
            throw APIError.rateLimited(retryAfter: retryAfter)

        case 500...599:
            if statusCode == 503 {
                throw APIError.serverUnavailable
            }
            let message = extractErrorMessage(from: data)
            throw APIError.httpError(statusCode: statusCode, message: message)

        default:
            let message = extractErrorMessage(from: data)
            throw APIError.httpError(statusCode: statusCode, message: message)
        }
    }

    /// Attempt to extract a human-readable error message from a JSON error response body.
    ///
    /// Tries several common JSON shapes:
    /// - `{ "error": "..." }`
    /// - `{ "message": "..." }`
    /// - `{ "error": { "message": "..." } }`
    ///
    /// - Parameter data: The raw response body.
    /// - Returns: The extracted message, or `nil` if the body is not parseable.
    static func extractErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Fall back to raw string representation if JSON parsing fails
            let rawString = String(data: data, encoding: .utf8)
            return rawString?.isEmpty == false ? rawString : nil
        }

        // Shape: { "error": "message" }
        if let errorString = json["error"] as? String {
            return errorString
        }

        // Shape: { "message": "message" }
        if let messageString = json["message"] as? String {
            return messageString
        }

        // Shape: { "error": { "message": "message" } }
        if let errorDict = json["error"] as? [String: Any],
           let nestedMessage = errorDict["message"] as? String {
            return nestedMessage
        }

        // Shape: { "errors": [{ "message": "message" }] }
        if let errors = json["errors"] as? [[String: Any]],
           let firstMessage = errors.first?["message"] as? String {
            return firstMessage
        }

        return nil
    }

    // MARK: - Private Helpers

    /// Parse the `Retry-After` header from an HTTP 429 response.
    ///
    /// The header may contain either a number of seconds or an HTTP-date.
    /// This implementation handles the seconds format, which is more common
    /// in API rate-limiting responses.
    ///
    /// - Parameter response: The HTTP response containing the header.
    /// - Returns: The number of seconds to wait before retrying, or `nil`.
    private static func parseRetryAfterHeader(from response: HTTPURLResponse) -> TimeInterval? {
        guard let retryAfterValue = response.value(forHTTPHeaderField: "Retry-After") else {
            return nil
        }

        // Try parsing as integer seconds
        if let seconds = TimeInterval(retryAfterValue) {
            return seconds
        }

        // Try parsing as HTTP-date (RFC 7231)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = formatter.date(from: retryAfterValue) {
            let interval = date.timeIntervalSinceNow
            return interval > 0 ? interval : nil
        }

        return nil
    }
}
