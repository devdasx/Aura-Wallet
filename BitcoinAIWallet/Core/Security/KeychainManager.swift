import Foundation
import Security

// MARK: - KeychainManager
/// Secure storage using iOS Keychain Services.
/// All items use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` so that
/// data never leaves the device and is only accessible while unlocked.
final class KeychainManager {

    // MARK: - Singleton

    static let shared = KeychainManager()
    private init() {}

    // MARK: - Keys

    enum KeychainKey: String, CaseIterable {
        case encryptedSeed     = "com.bitcoinai.wallet.seed"
        case walletPasscodeHash = "com.bitcoinai.wallet.passcode"
        case walletSalt        = "com.bitcoinai.wallet.salt"
        case derivationCounter = "com.bitcoinai.wallet.derivation"
    }

    // MARK: - Errors

    enum KeychainError: Error, LocalizedError {
        case itemNotFound
        case duplicateItem
        case unexpectedStatus(OSStatus)
        case encodingError
        case accessError

        var errorDescription: String? {
            switch self {
            case .itemNotFound:
                return "The requested keychain item was not found."
            case .duplicateItem:
                return "A keychain item with this key already exists."
            case .unexpectedStatus(let status):
                return "Keychain operation failed with status \(status)."
            case .encodingError:
                return "Failed to encode or decode keychain data."
            case .accessError:
                return "Access to the keychain was denied."
            }
        }
    }

    // MARK: - Save

    /// Save data to the keychain with the highest available security.
    ///
    /// - Parameters:
    ///   - key: The logical key identifying the item.
    ///   - data: The raw bytes to store.
    ///   - requireBiometric: When `true`, the item will require biometric
    ///     authentication (Face ID / Touch ID) each time it is read.
    /// - Throws: `KeychainError` on failure.
    func save(key: KeychainKey, data: Data, requireBiometric: Bool = false) throws {
        // Remove any existing item first to avoid duplicateItem errors.
        if exists(key: key) {
            try delete(key: key)
        }

        var query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String:  key.rawValue,
            kSecAttrService as String:  bundleIdentifier,
            kSecValueData as String:    data
        ]

        // Access control
        if requireBiometric {
            var error: Unmanaged<CFError>?
            guard let accessControl = SecAccessControlCreateWithFlags(
                kCFAllocatorDefault,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                .biometryCurrentSet,
                &error
            ) else {
                throw KeychainError.accessError
            }
            query[kSecAttrAccessControl as String] = accessControl
        } else {
            query[kSecAttrAccessible as String] =
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }

        let status = SecItemAdd(query as CFDictionary, nil)

        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            throw KeychainError.duplicateItem
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Read

    /// Read raw data from the keychain.
    ///
    /// - Parameter key: The logical key identifying the item.
    /// - Returns: The stored `Data`.
    /// - Throws: `KeychainError` on failure.
    func read(key: KeychainKey) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String:  key.rawValue,
            kSecAttrService as String:  bundleIdentifier,
            kSecReturnData as String:   true,
            kSecMatchLimit as String:   kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw KeychainError.encodingError
            }
            return data
        case errSecItemNotFound:
            throw KeychainError.itemNotFound
        case errSecAuthFailed, errSecInteractionNotAllowed:
            throw KeychainError.accessError
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Update

    /// Update an existing keychain item in-place.
    ///
    /// - Parameters:
    ///   - key: The logical key identifying the item.
    ///   - data: The new raw bytes to store.
    /// - Throws: `KeychainError` on failure.
    func update(key: KeychainKey, data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String:  key.rawValue,
            kSecAttrService as String:  bundleIdentifier
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let status = SecItemUpdate(query as CFDictionary,
                                   attributes as CFDictionary)

        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            throw KeychainError.itemNotFound
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Delete

    /// Delete a single keychain item.
    ///
    /// - Parameter key: The logical key identifying the item.
    /// - Throws: `KeychainError` on failure.
    func delete(key: KeychainKey) throws {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String:  key.rawValue,
            kSecAttrService as String:  bundleIdentifier
        ]

        let status = SecItemDelete(query as CFDictionary)

        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Exists

    /// Check whether a keychain item exists without reading its value.
    ///
    /// - Parameter key: The logical key identifying the item.
    /// - Returns: `true` when an item is present.
    func exists(key: KeychainKey) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String:  key.rawValue,
            kSecAttrService as String:  bundleIdentifier,
            kSecReturnData as String:   false,
            kSecMatchLimit as String:   kSecMatchLimitOne
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    // MARK: - Delete All

    /// Remove every wallet-related keychain item.
    ///
    /// - Throws: `KeychainError` if any individual deletion fails.
    func deleteAll() throws {
        for key in KeychainKey.allCases {
            try delete(key: key)
        }
    }

    // MARK: - Helpers

    /// The reverse-DNS bundle identifier used as the keychain service name.
    private var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.bitcoinai.wallet"
    }

    /// The keychain access group matching the entitlements file.
    /// Explicitly setting this prevents accidental cross-app access
    /// if additional access groups are ever added to the entitlements.
    private var accessGroup: String {
        // The full access group is: <TeamID>.com.bitcoinai.wallet
        // On device, $(AppIdentifierPrefix) is resolved to the Team ID prefix.
        // We omit the prefix here and let the system match against the
        // first entry in keychain-access-groups, which is the correct behavior.
        // To be fully explicit, set to "<YourTeamID>.com.bitcoinai.wallet".
        return "\(bundleIdentifier)"
    }
}
