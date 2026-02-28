import Foundation
import os

// MARK: - AppLogger
// Centralized logging utility for the Bitcoin AI Wallet.
// Wraps Apple's unified logging system (os.Logger) with category-based
// channels and convenience methods for each severity level.
//
// Usage:
//   AppLogger.debug("Fetching UTXOs for address...", category: .wallet)
//   AppLogger.error("WebSocket disconnected unexpectedly", category: .network)
//
// All logs are routed through the os subsystem so they appear in
// Console.app, Xcode console, and log archives with proper filtering.

enum AppLogger {

    // MARK: - Subsystem

    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.bitcoinai.wallet"

    // MARK: - Category Loggers

    private static let general  = os.Logger(subsystem: subsystem, category: "general")
    private static let network  = os.Logger(subsystem: subsystem, category: "network")
    private static let wallet   = os.Logger(subsystem: subsystem, category: "wallet")
    private static let security = os.Logger(subsystem: subsystem, category: "security")
    private static let chat     = os.Logger(subsystem: subsystem, category: "chat")
    private static let ui       = os.Logger(subsystem: subsystem, category: "ui")

    // MARK: - Category Enum

    /// Logical groupings for log messages. Each category maps to a
    /// dedicated `os.Logger` instance so logs can be filtered in Console.app.
    enum Category {
        case general
        case network
        case wallet
        case security
        case chat
        case ui
    }

    // MARK: - Severity Methods

    /// Log a debug-level message.
    /// Use for verbose diagnostic information during development.
    static func debug(_ message: String, category: Category = .general) {
        logger(for: category).debug("\(message, privacy: .private)")
    }

    /// Log an informational message.
    /// Use for routine operational events (e.g. "sync completed").
    static func info(_ message: String, category: Category = .general) {
        logger(for: category).info("\(message, privacy: .private)")
    }

    /// Log a warning message.
    /// Use when something unexpected happened but the app can continue.
    static func warning(_ message: String, category: Category = .general) {
        logger(for: category).warning("\(message, privacy: .private)")
    }

    /// Log an error message.
    /// Use when an operation failed and requires user attention or recovery.
    static func error(_ message: String, category: Category = .general) {
        logger(for: category).error("\(message, privacy: .private)")
    }

    /// Log a critical message.
    /// Use for unrecoverable situations that may lead to data loss or crash.
    static func critical(_ message: String, category: Category = .general) {
        logger(for: category).critical("\(message, privacy: .private)")
    }

    // MARK: - Private

    /// Returns the `os.Logger` instance for a given category.
    private static func logger(for category: Category) -> os.Logger {
        switch category {
        case .general:  return general
        case .network:  return network
        case .wallet:   return wallet
        case .security: return security
        case .chat:     return chat
        case .ui:       return ui
        }
    }
}
