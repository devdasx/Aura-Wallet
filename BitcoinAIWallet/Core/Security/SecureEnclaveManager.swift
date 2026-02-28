import Foundation
import Security
import CryptoKit

// MARK: - SecureEnclaveManager
/// Hardware-backed key operations using the Secure Enclave.
///
/// Keys generated here never leave the Secure Enclave hardware; only
/// public keys and signed / encrypted outputs are returned to the caller.
final class SecureEnclaveManager {

    // MARK: - Singleton

    static let shared = SecureEnclaveManager()
    private init() {}

    // MARK: - Constants

    private let keyTag = "com.bitcoinai.wallet.enclave.key"

    // MARK: - Errors

    enum SecureEnclaveError: Error, LocalizedError {
        case notAvailable
        case keyGenerationFailed(String)
        case keyNotFound
        case signingFailed(String)
        case encryptionFailed(String)
        case decryptionFailed(String)
        case publicKeyExportFailed
        case deletionFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .notAvailable:
                return "Secure Enclave is not available on this device."
            case .keyGenerationFailed(let detail):
                return "Failed to generate Secure Enclave key pair: \(detail)"
            case .keyNotFound:
                return "No Secure Enclave key pair found for this wallet."
            case .signingFailed(let detail):
                return "Secure Enclave signing operation failed: \(detail)"
            case .encryptionFailed(let detail):
                return "Secure Enclave encryption failed: \(detail)"
            case .decryptionFailed(let detail):
                return "Secure Enclave decryption failed: \(detail)"
            case .publicKeyExportFailed:
                return "Failed to export public key from Secure Enclave."
            case .deletionFailed(let status):
                return "Failed to delete Secure Enclave key (status \(status))."
            }
        }
    }

    // MARK: - Availability

    /// Whether the current device has a Secure Enclave.
    var isAvailable: Bool {
        SecureEnclave.isAvailable
    }

    // MARK: - Key Generation

    /// Generate an elliptic-curve key pair inside the Secure Enclave.
    ///
    /// If a key pair with the same tag already exists it is deleted first
    /// so the caller always gets a fresh key.
    ///
    /// - Returns: A `SecKey` reference to the private key (the actual
    ///   private key material never leaves the Secure Enclave).
    /// - Throws: `SecureEnclaveError` on failure.
    @discardableResult
    func generateKeyPair() throws -> SecKey {
        guard isAvailable else { throw SecureEnclaveError.notAvailable }

        // Remove any previous key with the same tag.
        try? deleteKeyPair()

        // Access control: require device unlock; no additional biometric gate
        // so that the app can use the key after the user unlocks the phone.
        var accessError: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage],
            &accessError
        ) else {
            let msg = accessError?.takeRetainedValue().localizedDescription ?? "unknown"
            throw SecureEnclaveError.keyGenerationFailed(msg)
        }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String:           kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String:      256,
            kSecAttrTokenID as String:            kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String:    true,
                kSecAttrApplicationTag as String: keyTag.data(using: .utf8)!,
                kSecAttrAccessControl as String:  accessControl
            ] as [String: Any]
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            let msg = error?.takeRetainedValue().localizedDescription ?? "unknown"
            throw SecureEnclaveError.keyGenerationFailed(msg)
        }

        return privateKey
    }

    // MARK: - Signing

    /// Sign arbitrary data using the Secure Enclave private key.
    ///
    /// Uses ECDSA with SHA-256.
    ///
    /// - Parameter data: The data to sign.
    /// - Returns: The DER-encoded ECDSA signature.
    /// - Throws: `SecureEnclaveError` on failure.
    func sign(data: Data) throws -> Data {
        let privateKey = try loadPrivateKey()

        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .ecdsaSignatureMessageX962SHA256,
            data as CFData,
            &error
        ) else {
            let msg = error?.takeRetainedValue().localizedDescription ?? "unknown"
            throw SecureEnclaveError.signingFailed(msg)
        }

        return signature as Data
    }

    // MARK: - Encryption

    /// Encrypt data using the Secure Enclave public key (eciesEncryptionCofactorX963SHA256AESGCM).
    ///
    /// - Parameter data: The plaintext data.
    /// - Returns: The ciphertext.
    /// - Throws: `SecureEnclaveError` on failure.
    func encrypt(data: Data) throws -> Data {
        let privateKey = try loadPrivateKey()

        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw SecureEnclaveError.publicKeyExportFailed
        }

        let algorithm = SecKeyAlgorithm.eciesEncryptionCofactorX963SHA256AESGCM

        guard SecKeyIsAlgorithmSupported(publicKey, .encrypt, algorithm) else {
            throw SecureEnclaveError.encryptionFailed("Algorithm not supported.")
        }

        var error: Unmanaged<CFError>?
        guard let ciphertext = SecKeyCreateEncryptedData(
            publicKey,
            algorithm,
            data as CFData,
            &error
        ) else {
            let msg = error?.takeRetainedValue().localizedDescription ?? "unknown"
            throw SecureEnclaveError.encryptionFailed(msg)
        }

        return ciphertext as Data
    }

    // MARK: - Decryption

    /// Decrypt data using the Secure Enclave private key.
    ///
    /// - Parameter data: The ciphertext produced by `encrypt(data:)`.
    /// - Returns: The original plaintext.
    /// - Throws: `SecureEnclaveError` on failure.
    func decrypt(data: Data) throws -> Data {
        let privateKey = try loadPrivateKey()

        let algorithm = SecKeyAlgorithm.eciesEncryptionCofactorX963SHA256AESGCM

        guard SecKeyIsAlgorithmSupported(privateKey, .decrypt, algorithm) else {
            throw SecureEnclaveError.decryptionFailed("Algorithm not supported.")
        }

        var error: Unmanaged<CFError>?
        guard let plaintext = SecKeyCreateDecryptedData(
            privateKey,
            algorithm,
            data as CFData,
            &error
        ) else {
            let msg = error?.takeRetainedValue().localizedDescription ?? "unknown"
            throw SecureEnclaveError.decryptionFailed(msg)
        }

        return plaintext as Data
    }

    // MARK: - Key Deletion

    /// Delete the Secure Enclave key pair associated with this wallet.
    ///
    /// - Throws: `SecureEnclaveError.deletionFailed` when the keychain
    ///   returns an unexpected status.
    func deleteKeyPair() throws {
        let query: [String: Any] = [
            kSecClass as String:              kSecClassKey,
            kSecAttrApplicationTag as String:  keyTag.data(using: .utf8)!,
            kSecAttrKeyType as String:         kSecAttrKeyTypeECSECPrimeRandom
        ]

        let status = SecItemDelete(query as CFDictionary)

        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw SecureEnclaveError.deletionFailed(status)
        }
    }

    // MARK: - Public Key Export

    /// Export the raw public key bytes (X9.63 uncompressed point format).
    ///
    /// - Returns: The public key data.
    /// - Throws: `SecureEnclaveError` on failure.
    func publicKey() throws -> Data {
        let privateKey = try loadPrivateKey()

        guard let pubKey = SecKeyCopyPublicKey(privateKey) else {
            throw SecureEnclaveError.publicKeyExportFailed
        }

        var error: Unmanaged<CFError>?
        guard let pubKeyData = SecKeyCopyExternalRepresentation(pubKey, &error) else {
            throw SecureEnclaveError.publicKeyExportFailed
        }

        return pubKeyData as Data
    }

    // MARK: - Private Helpers

    /// Load the existing private key reference from the keychain.
    private func loadPrivateKey() throws -> SecKey {
        let query: [String: Any] = [
            kSecClass as String:              kSecClassKey,
            kSecAttrApplicationTag as String:  keyTag.data(using: .utf8)!,
            kSecAttrKeyType as String:         kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String:           true,
            kSecMatchLimit as String:          kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            // swiftlint:disable:next force_cast
            return item as! SecKey
        case errSecItemNotFound:
            throw SecureEnclaveError.keyNotFound
        default:
            throw SecureEnclaveError.keyGenerationFailed("Failed to load key (status \(status)).")
        }
    }
}
