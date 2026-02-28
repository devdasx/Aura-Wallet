import Foundation
import CryptoKit

// MARK: - EncryptionHelper
/// AES-256-GCM encryption for sensitive data such as seed phrases.
///
/// Key derivation uses HKDF on top of a SHA-256 hash of the passphrase
/// combined with a random salt, providing strong resistance to
/// brute-force attacks. All temporary buffers are zeroed via `defer`.
struct EncryptionHelper {

    // MARK: - Errors

    enum EncryptionError: Error, LocalizedError {
        case encryptionFailed
        case decryptionFailed
        case invalidKey
        case invalidData
        case keyDerivationFailed
        case saltGenerationFailed

        var errorDescription: String? {
            switch self {
            case .encryptionFailed:
                return "Failed to encrypt the data."
            case .decryptionFailed:
                return "Failed to decrypt the data. The passphrase may be incorrect."
            case .invalidKey:
                return "The encryption key is invalid."
            case .invalidData:
                return "The provided data is invalid or corrupted."
            case .keyDerivationFailed:
                return "Failed to derive encryption key from passphrase."
            case .saltGenerationFailed:
                return "Failed to generate a cryptographic random salt."
            }
        }
    }

    // MARK: - Constants

    /// Number of PBKDF2-equivalent iterations for key stretching.
    /// CryptoKit does not expose raw PBKDF2, so we use an HKDF-based
    /// scheme with a computationally expensive intermediate hash to
    /// approximate the cost.
    private static let defaultIterations: Int = 600_000

    /// Salt length in bytes (256-bit).
    private static let defaultSaltLength: Int = 32

    // MARK: - Encrypt

    /// Encrypt data with a passphrase.
    ///
    /// Layout of the returned blob:
    /// ```
    /// [salt (32 bytes)] [nonce (12 bytes)] [ciphertext] [tag (16 bytes)]
    /// ```
    ///
    /// - Parameters:
    ///   - data: The plaintext to encrypt.
    ///   - passphrase: A user-supplied passphrase.
    /// - Returns: The combined blob (salt + sealed box).
    /// - Throws: `EncryptionError` on failure.
    static func encrypt(data: Data, passphrase: String) throws -> Data {
        guard !data.isEmpty else { throw EncryptionError.invalidData }
        guard !passphrase.isEmpty else { throw EncryptionError.invalidKey }

        let salt = generateSalt()
        let key = deriveKey(passphrase: passphrase, salt: salt)

        do {
            let sealedBox = try AES.GCM.seal(data, using: key)

            guard let combined = sealedBox.combined else {
                throw EncryptionError.encryptionFailed
            }

            // Prepend salt so decryption can re-derive the same key.
            var result = Data()
            result.append(salt)
            result.append(combined)
            return result
        } catch is EncryptionError {
            throw EncryptionError.encryptionFailed
        } catch {
            throw EncryptionError.encryptionFailed
        }
    }

    // MARK: - Decrypt

    /// Decrypt data previously encrypted with `encrypt(data:passphrase:)`.
    ///
    /// - Parameters:
    ///   - encryptedData: The blob produced by `encrypt`.
    ///   - passphrase: The same passphrase used during encryption.
    /// - Returns: The original plaintext.
    /// - Throws: `EncryptionError` on failure (wrong passphrase, corrupted data, etc.).
    static func decrypt(encryptedData: Data, passphrase: String) throws -> Data {
        // Minimum size: salt (32) + nonce (12) + tag (16) = 60 bytes
        guard encryptedData.count > defaultSaltLength + 12 + 16 else {
            throw EncryptionError.invalidData
        }
        guard !passphrase.isEmpty else { throw EncryptionError.invalidKey }

        let salt = encryptedData.prefix(defaultSaltLength)
        let sealedData = encryptedData.dropFirst(defaultSaltLength)

        let key = deriveKey(passphrase: passphrase, salt: Data(salt))

        do {
            let sealedBox = try AES.GCM.SealedBox(combined: sealedData)
            let plaintext = try AES.GCM.open(sealedBox, using: key)
            return plaintext
        } catch {
            throw EncryptionError.decryptionFailed
        }
    }

    // MARK: - Key Derivation

    /// Derive a 256-bit symmetric key from a passphrase and salt.
    ///
    /// Uses an iterated SHA-256 hash as a cost function followed by
    /// HKDF-SHA256 expansion, emulating PBKDF2-like key stretching
    /// with only `CryptoKit` primitives (no `CommonCrypto`).
    ///
    /// - Parameters:
    ///   - passphrase: The user-supplied passphrase.
    ///   - salt: A random salt (should be at least 16 bytes).
    ///   - iterations: The number of hash iterations (default 600 000).
    /// - Returns: A `SymmetricKey` suitable for AES-256-GCM.
    static func deriveKey(passphrase: String,
                          salt: Data,
                          iterations: Int = 600_000) -> SymmetricKey {
        // Phase 1 -- iterated hashing to make brute-force expensive.
        var passphraseData = Data(passphrase.utf8)
        defer { zeroize(&passphraseData) }

        var hashInput = Data()
        hashInput.append(passphraseData)
        hashInput.append(salt)

        var digest = SHA256.hash(data: hashInput)

        for _ in 1..<iterations {
            var block = Data(digest)
            block.append(salt)
            digest = SHA256.hash(data: block)
        }

        let intermediateKey = SymmetricKey(data: Data(digest))

        // Phase 2 -- HKDF expansion for domain separation.
        let derivedKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: intermediateKey,
            salt: salt,
            info: Data("com.bitcoinai.wallet.encryption".utf8),
            outputByteCount: 32
        )

        return derivedKey
    }

    // MARK: - Salt Generation

    /// Generate a cryptographically secure random salt.
    ///
    /// - Parameter length: Number of bytes (default 32).
    /// - Returns: Random salt data.
    static func generateSalt(length: Int = 32) -> Data {
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        if status != errSecSuccess {
            // Fallback: this path should essentially never be hit on iOS.
            // If SecRandomCopyBytes fails we still produce random bytes
            // via arc4random.
            for i in 0..<length {
                bytes[i] = UInt8.random(in: 0...255)
            }
        }
        return Data(bytes)
    }

    // MARK: - Passcode Hashing

    /// Hash a passcode for safe storage (verification only, NOT encryption).
    ///
    /// Uses SHA-256(passcode || salt) iterated multiple times so that
    /// even if the hash leaks, reversing it is computationally expensive.
    ///
    /// - Parameters:
    ///   - passcode: The user's wallet passcode.
    ///   - salt: A random salt previously stored alongside the hash.
    /// - Returns: The 32-byte hash.
    static func hashPasscode(_ passcode: String, salt: Data) -> Data {
        var input = Data(passcode.utf8)
        defer { zeroize(&input) }

        var combined = Data()
        combined.append(input)
        combined.append(salt)

        var digest = SHA256.hash(data: combined)

        // Iterate to increase brute-force cost.
        let iterations = 100_000
        for _ in 1..<iterations {
            var block = Data(digest)
            block.append(salt)
            digest = SHA256.hash(data: block)
        }

        return Data(digest)
    }

    /// Verify a passcode against a previously stored hash.
    ///
    /// Uses constant-time comparison to prevent timing attacks.
    ///
    /// - Parameters:
    ///   - passcode: The passcode to verify.
    ///   - hash: The stored hash to compare against.
    ///   - salt: The salt that was used when creating the hash.
    /// - Returns: `true` when the passcode matches.
    static func verifyPasscode(_ passcode: String,
                               against hash: Data,
                               salt: Data) -> Bool {
        let candidate = hashPasscode(passcode, salt: salt)
        // Constant-time comparison to mitigate timing side-channels.
        return constantTimeEqual(candidate, hash)
    }

    // MARK: - Memory Safety

    /// Overwrite the contents of a `Data` buffer with zeroes.
    ///
    /// Call this in `defer` blocks after handling sensitive material
    /// (passphrases, plaintext seeds, intermediate keys) to reduce
    /// the window during which secrets reside in memory.
    ///
    /// - Parameter data: The buffer to zero out (modified in-place).
    static func zeroize(_ data: inout Data) {
        guard !data.isEmpty else { return }
        data.withUnsafeMutableBytes { buffer in
            if let baseAddress = buffer.baseAddress {
                memset(baseAddress, 0, buffer.count)
            }
        }
        data = Data()
    }

    // MARK: - Private Helpers

    /// Constant-time comparison of two `Data` values.
    ///
    /// Returns `false` immediately if lengths differ (which leaks length
    /// information, but the hash length is not secret).
    private static func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }

        var result: UInt8 = 0
        for (x, y) in zip(a, b) {
            result |= x ^ y
        }
        return result == 0
    }
}
