// MARK: - APIConfiguration.swift
// Bitcoin AI Wallet
//
// API configuration including base URLs, timeouts, retry policy, and
// user-agent string. Provides preset configurations for mainnet,
// testnet, and testing environments.
//
// Platform: iOS 17.0+
// Dependencies: Foundation

import Foundation

// MARK: - APIConfiguration

/// Holds all configuration needed to connect to a Blockbook API instance
/// and control HTTP client behaviour (timeouts, retries, backoff).
///
/// Use ``default`` for Bitcoin mainnet, ``testnet`` for Bitcoin testnet,
/// or ``testing`` for unit tests. You can also create a custom configuration
/// pointing to any compatible Blockbook server.
///
/// ```swift
/// let config = APIConfiguration.default
/// let api = BlockbookAPI(configuration: config)
/// ```
struct APIConfiguration: Sendable {

    // MARK: - Properties

    /// Base URL for Blockbook REST API requests (e.g. `https://btc1.trezor.io`).
    let blockbookBaseURL: URL

    /// WebSocket URL for Blockbook real-time subscriptions.
    let blockbookWebSocketURL: URL

    /// Maximum time (in seconds) before a single HTTP request is considered timed out.
    let requestTimeout: TimeInterval

    /// Maximum number of automatic retries for retryable errors.
    let maxRetries: Int

    /// Base delay (in seconds) for the first retry. Subsequent retries use exponential backoff.
    let baseRetryDelay: TimeInterval

    /// Maximum delay (in seconds) between retries, capping the exponential growth.
    let maxRetryDelay: TimeInterval

    /// A jitter factor (0.0 ... 1.0) added to retry delays to decorrelate concurrent retries.
    let retryJitterFactor: Double

    /// The `User-Agent` string sent with every request.
    let userAgent: String

    // MARK: - Presets

    /// Bitcoin **mainnet** configuration using Ankr premium Blockbook.
    static let `default` = APIConfiguration(
        blockbookBaseURL: URL(string: Constants.defaultBlockbookURL)!,
        blockbookWebSocketURL: URL(string: "wss://btc1.trezor.io/websocket")!,
        requestTimeout: 30,
        maxRetries: 3,
        baseRetryDelay: 1.0,
        maxRetryDelay: 30.0,
        retryJitterFactor: 0.25,
        userAgent: "BitcoinAIWallet/1.0 (iOS; \(UIDeviceInfo.systemVersion))"
    )

    /// Bitcoin **testnet** configuration using the public Trezor Blockbook testnet instance.
    static let testnet = APIConfiguration(
        blockbookBaseURL: URL(string: "https://tbtc1.trezor.io")!,
        blockbookWebSocketURL: URL(string: "wss://tbtc1.trezor.io/websocket")!,
        requestTimeout: 30,
        maxRetries: 3,
        baseRetryDelay: 1.0,
        maxRetryDelay: 30.0,
        retryJitterFactor: 0.25,
        userAgent: "BitcoinAIWallet/1.0 (iOS; \(UIDeviceInfo.systemVersion))"
    )

    /// A configuration optimised for unit and integration tests.
    static let testing = APIConfiguration(
        blockbookBaseURL: URL(string: "https://btc1.trezor.io")!,
        blockbookWebSocketURL: URL(string: "wss://btc1.trezor.io/websocket")!,
        requestTimeout: 5,
        maxRetries: 1,
        baseRetryDelay: 0.1,
        maxRetryDelay: 0.5,
        retryJitterFactor: 0.0,
        userAgent: "BitcoinAIWallet-Tests/1.0"
    )
}

// MARK: - UIDeviceInfo

/// Lightweight helper that provides device metadata without importing UIKit at the module level.
enum UIDeviceInfo {

    /// The operating system version string (e.g. "17.4.0").
    static var systemVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
}
