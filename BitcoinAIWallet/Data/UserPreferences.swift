// MARK: - UserPreferences.swift
// Bitcoin AI Wallet
//
// User settings and preferences stored in UserDefaults via @AppStorage.
// Provides a centralized, observable store for all user-configurable
// options used throughout the application.
//
// Platform: iOS 17.0+
// Frameworks: Foundation, SwiftUI

import Foundation
import SwiftUI

// MARK: - UserPreferences

/// Centralized store for all user-configurable settings.
///
/// `UserPreferences` uses `@AppStorage` property wrappers to automatically
/// persist values to `UserDefaults` and notify SwiftUI views of changes.
/// It is designed as a singleton accessed via `UserPreferences.shared`.
///
/// ## Usage
/// ```swift
/// // Read a preference
/// let currency = UserPreferences.shared.displayCurrency
///
/// // Observe changes in SwiftUI
/// @ObservedObject var prefs = UserPreferences.shared
/// Text("Currency: \(prefs.displayCurrency)")
/// ```
///
/// ## Thread Safety
/// `@AppStorage` reads and writes are synchronized through `UserDefaults`,
/// which is thread-safe for reads and coalesces writes.
final class UserPreferences: ObservableObject {

    // MARK: - Singleton

    /// Shared instance used throughout the application.
    static let shared = UserPreferences()

    // MARK: - Display Preferences

    /// The user's preferred fiat currency for balance display.
    ///
    /// Supported values: `"USD"`, `"EUR"`, `"GBP"`, `"JPY"`, `"CAD"`, `"AUD"`, `"CHF"`.
    @AppStorage("display_currency") var displayCurrency: String = "USD"

    /// The user's preferred visual theme.
    ///
    /// Values: `"dark"`, `"light"`, `"system"`.
    @AppStorage("theme_preference") var themePreference: String = "system"

    /// The user's preferred chat font.
    ///
    /// Values: `"default"` (Georgia), `"system"` (SF Pro), `"monospace"`, `"dyslexic"`.
    @AppStorage("chat_font") var chatFont: String = "default"

    /// The user's preferred language code (ISO 639-1).
    ///
    /// Supported: `"en"`, `"es"`, `"ar"`.
    @AppStorage("app_language") var appLanguage: String = "en"

    /// Whether to hide the wallet balance on the main screen for privacy.
    @AppStorage("hide_balance") var hideBalance: Bool = false

    /// Whether to show Tips & Tricks after AI responses.
    @AppStorage("tips_enabled") var tipsEnabled: Bool = true

    // MARK: - Security Preferences

    /// Whether biometric authentication (Face ID / Touch ID) is enabled.
    @AppStorage("biometrics_enabled") var biometricsEnabled: Bool = true

    /// Auto-lock timeout in seconds. The app locks after this many seconds of inactivity.
    ///
    /// Common values: `60` (1 min), `300` (5 min), `600` (10 min), `0` (disabled).
    @AppStorage("auto_lock_timeout") var autoLockTimeout: Int = 300

    // MARK: - Network Preferences

    /// The base URL for the Blockbook API instance.
    ///
    /// Default points to the public Trezor Blockbook mainnet server.
    /// Advanced users may configure their own server for privacy.
    @AppStorage("blockbook_url") var blockbookURL: String = "https://rpc.ankr.com/premium-http/btc_blockbook/42cb7796858fdf001f82278d929e8b61c865af79cd4efffbe574f344312e6ab2"

    /// The default fee level for transaction construction.
    ///
    /// Values: `"low"`, `"medium"`, `"high"`, `"custom"`.
    @AppStorage("default_fee_level") var defaultFeeLevel: String = "medium"

    // MARK: - Wallet Configuration

    /// The preferred Bitcoin address type for receiving.
    ///
    /// Values: `"segwit"` (BIP-84, bc1q...) or `"taproot"` (BIP-86, bc1p...).
    @AppStorage("address_type") var preferredAddressType: String = "segwit"

    /// BIP84 SegWit receive address derivation index.
    @AppStorage("receive_address_index") var receiveAddressIndex: Int = 0

    /// BIP84 SegWit change address derivation index.
    @AppStorage("change_address_index") var changeAddressIndex: Int = 0

    /// BIP44 Legacy receive address derivation index.
    @AppStorage("legacy_receive_index") var legacyReceiveIndex: Int = 0

    /// BIP44 Legacy change address derivation index.
    @AppStorage("legacy_change_index") var legacyChangeIndex: Int = 0

    /// BIP49 Nested SegWit receive address derivation index.
    @AppStorage("nested_segwit_receive_index") var nestedSegwitReceiveIndex: Int = 0

    /// BIP49 Nested SegWit change address derivation index.
    @AppStorage("nested_segwit_change_index") var nestedSegwitChangeIndex: Int = 0

    /// BIP86 Taproot receive address derivation index.
    @AppStorage("taproot_receive_index") var taprootReceiveIndex: Int = 0

    /// BIP86 Taproot change address derivation index.
    @AppStorage("taproot_change_index") var taprootChangeIndex: Int = 0

    // MARK: - App State

    /// Whether the user has completed the initial onboarding flow.
    @AppStorage("has_completed_onboarding") var hasCompletedOnboarding: Bool = false

    /// Unix timestamp of the last successful wallet sync.
    @AppStorage("last_sync_timestamp") var lastSyncTimestamp: Double = 0

    // MARK: - Initialization

    private init() {}

    // MARK: - Computed Properties

    /// The last sync date derived from the stored Unix timestamp.
    ///
    /// Returns `nil` if the wallet has never been synced.
    var lastSyncDate: Date? {
        guard lastSyncTimestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: lastSyncTimestamp)
    }

    /// Whether the wallet has ever been synced with the network.
    var hasEverSynced: Bool {
        lastSyncTimestamp > 0
    }

    /// Records the current time as the last sync timestamp.
    func recordSync() {
        lastSyncTimestamp = Date().timeIntervalSince1970
    }

    // MARK: - Address Index Management

    /// Advances the receive address index by one and returns the new index.
    ///
    /// - Returns: The newly incremented receive address index.
    @discardableResult
    func advanceReceiveIndex() -> Int {
        receiveAddressIndex += 1
        return receiveAddressIndex
    }

    /// Advances the change address index by one and returns the new index.
    ///
    /// - Returns: The newly incremented change address index.
    @discardableResult
    func advanceChangeIndex() -> Int {
        changeAddressIndex += 1
        return changeAddressIndex
    }

    // MARK: - Reset to Defaults

    /// Resets all preferences to their factory default values.
    ///
    /// This removes all keys managed by `UserPreferences` from `UserDefaults`.
    /// Does **not** delete Keychain items or Core Data; use `CoreDataStack.deleteAll()`
    /// and `KeychainManager.deleteAll()` separately for a full wallet wipe.
    func resetToDefaults() {
        let defaults = UserDefaults.standard

        let keys = [
            "display_currency",
            "theme_preference",
            "app_language",
            "biometrics_enabled",
            "default_fee_level",
            "blockbook_url",
            "has_completed_onboarding",
            "auto_lock_timeout",
            "hide_balance",
            "tips_enabled",
            "chat_font",
            "address_type",
            "last_sync_timestamp",
            "receive_address_index",
            "change_address_index",
            "legacy_receive_index",
            "legacy_change_index",
            "nested_segwit_receive_index",
            "nested_segwit_change_index",
            "taproot_receive_index",
            "taproot_change_index"
        ]

        for key in keys {
            defaults.removeObject(forKey: key)
        }

        defaults.synchronize()

        // Reset published properties to defaults.
        // @AppStorage reads from UserDefaults on access, so re-assigning
        // triggers the objectWillChange publisher for SwiftUI.
        displayCurrency = "USD"
        themePreference = "system"
        chatFont = "default"
        appLanguage = "en"
        biometricsEnabled = true
        defaultFeeLevel = "medium"
        blockbookURL = Constants.defaultBlockbookURL
        hasCompletedOnboarding = false
        autoLockTimeout = 300
        hideBalance = false
        tipsEnabled = true
        preferredAddressType = "segwit"
        lastSyncTimestamp = 0
        receiveAddressIndex = 0
        changeAddressIndex = 0
        legacyReceiveIndex = 0
        legacyChangeIndex = 0
        nestedSegwitReceiveIndex = 0
        nestedSegwitChangeIndex = 0
        taprootReceiveIndex = 0
        taprootChangeIndex = 0

        DataLogger.info("User preferences reset to defaults.")
    }

    // MARK: - Validation

    /// Validates that the Blockbook URL is a well-formed HTTPS URL.
    ///
    /// - Returns: `true` if the URL is valid and uses HTTPS.
    var isBlockbookURLValid: Bool {
        guard let url = URL(string: blockbookURL) else { return false }
        return url.scheme?.lowercased() == "https" && url.host != nil
    }

    /// Returns a validated `URL` for the Blockbook server, falling back
    /// to the default if the stored URL is invalid.
    var validatedBlockbookURL: URL {
        if let url = URL(string: blockbookURL), url.scheme?.lowercased() == "https" {
            return url
        }
        // swiftlint:disable:next force_unwrapping
        return URL(string: Constants.defaultBlockbookURL)! // Compile-time constant, always valid
    }

    // MARK: - Fee Level

    /// Supported fee level options.
    static let feeLevels = ["low", "medium", "high", "custom"]

    /// Whether the current fee level is a standard preset (not custom).
    var isStandardFeeLevel: Bool {
        ["low", "medium", "high"].contains(defaultFeeLevel)
    }

    // MARK: - Supported Currencies

    /// The list of fiat currencies supported for balance display.
    static let supportedCurrencies = [
        ("USD", "US Dollar"),
        ("EUR", "Euro"),
        ("GBP", "British Pound"),
        ("JPY", "Japanese Yen"),
        ("CAD", "Canadian Dollar"),
        ("AUD", "Australian Dollar"),
        ("CHF", "Swiss Franc")
    ]
}
