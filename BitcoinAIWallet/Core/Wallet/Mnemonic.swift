import Foundation
import CryptoKit

// MARK: - Mnemonic Errors

/// Errors that can occur during mnemonic generation and validation
enum MnemonicError: LocalizedError {
    case entropyGenerationFailed
    case invalidEntropyLength
    case invalidWordCount
    case invalidWord(String)
    case checksumMismatch
    case wordlistCompromised
    case seedDerivationFailed

    var errorDescription: String? {
        switch self {
        case .entropyGenerationFailed:
            return "Failed to generate cryptographically secure random entropy"
        case .invalidEntropyLength:
            return "Entropy length must be 128 bits (12 words) or 256 bits (24 words)"
        case .invalidWordCount:
            return "Mnemonic must contain exactly 12 or 24 words"
        case .invalidWord(let word):
            return "Word '\(word)' is not in the BIP39 wordlist"
        case .checksumMismatch:
            return "Mnemonic checksum verification failed"
        case .wordlistCompromised:
            return "BIP39 wordlist integrity check failed"
        case .seedDerivationFailed:
            return "Failed to derive seed from mnemonic using PBKDF2"
        }
    }
}

// MARK: - Mnemonic Strength

/// Defines the entropy strength for mnemonic generation
enum MnemonicStrength: Int {
    /// 128 bits of entropy, produces 12 words
    case twelve = 128
    /// 256 bits of entropy, produces 24 words
    case twentyFour = 256

    /// Number of words produced by this strength
    var wordCount: Int {
        switch self {
        case .twelve: return 12
        case .twentyFour: return 24
        }
    }

    /// Number of checksum bits
    var checksumBits: Int {
        rawValue / 32
    }

    /// Total number of bits (entropy + checksum)
    var totalBits: Int {
        rawValue + checksumBits
    }
}

// MARK: - Mnemonic

/// BIP39 mnemonic phrase for deterministic key generation.
///
/// A mnemonic encodes entropy as a sequence of English words that can be
/// written down and used to recover a wallet. Supports 12-word (128-bit)
/// and 24-word (256-bit) mnemonics per BIP-0039.
struct Mnemonic {

    // MARK: - Properties

    /// The ordered list of mnemonic words
    let words: [String]

    /// The entropy strength used to generate this mnemonic
    let strength: MnemonicStrength

    /// The mnemonic phrase as a single space-separated string
    var phrase: String {
        words.joined(separator: " ")
    }

    // MARK: - Initialization

    /// Creates a mnemonic from pre-validated words and strength.
    /// This is internal; use `generate()` or `restore()` instead.
    private init(words: [String], strength: MnemonicStrength) {
        self.words = words
        self.strength = strength
    }

    // MARK: - Generation

    /// Generate a new random mnemonic phrase.
    ///
    /// Uses `SecRandomCopyBytes` for cryptographically secure entropy generation.
    /// The entropy is checksummed using SHA-256 and encoded as BIP39 words.
    ///
    /// - Parameter strength: The desired strength (`.twelve` for 12 words, `.twentyFour` for 24 words)
    /// - Returns: A new `Mnemonic` instance
    /// - Throws: `MnemonicError` if entropy generation or wordlist validation fails
    static func generate(strength: MnemonicStrength = .twelve) throws -> Mnemonic {
        // Verify wordlist integrity
        guard BIP39Wordlist.isIntact else {
            throw MnemonicError.wordlistCompromised
        }

        // Generate entropy
        let entropyBytes = strength.rawValue / 8
        var entropy = Data(count: entropyBytes)
        let status = entropy.withUnsafeMutableBytes { bufferPointer in
            SecRandomCopyBytes(kSecRandomDefault, entropyBytes, bufferPointer.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw MnemonicError.entropyGenerationFailed
        }

        // Convert entropy to mnemonic words
        let words = try entropyToWords(entropy)

        // Determine strength from word count
        guard let resolvedStrength = strengthFromWordCount(words.count) else {
            throw MnemonicError.invalidWordCount
        }

        return Mnemonic(words: words, strength: resolvedStrength)
    }

    // MARK: - Restoration

    /// Restore a mnemonic from an existing word list.
    ///
    /// Validates that all words are in the BIP39 wordlist and the checksum is correct.
    ///
    /// - Parameter words: An array of 12 or 24 BIP39 English words
    /// - Returns: A validated `Mnemonic` instance
    /// - Throws: `MnemonicError` if validation fails
    static func restore(words: [String]) throws -> Mnemonic {
        let normalizedWords = words.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }

        // Validate word count
        guard let strength = strengthFromWordCount(normalizedWords.count) else {
            throw MnemonicError.invalidWordCount
        }

        // Validate each word exists in the wordlist
        for word in normalizedWords {
            guard BIP39Wordlist.isValid(word: word) else {
                throw MnemonicError.invalidWord(word)
            }
        }

        // Validate checksum
        guard validate(words: normalizedWords) else {
            throw MnemonicError.checksumMismatch
        }

        return Mnemonic(words: normalizedWords, strength: strength)
    }

    // MARK: - Validation

    /// Validate a mnemonic phrase by checking wordlist membership and checksum.
    ///
    /// - Parameter words: The mnemonic words to validate
    /// - Returns: `true` if the mnemonic is valid (correct words and checksum)
    static func validate(words: [String]) -> Bool {
        let normalizedWords = words.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }

        // Check word count
        guard let strength = strengthFromWordCount(normalizedWords.count) else {
            return false
        }

        // Check all words are valid
        var indices = [Int]()
        for word in normalizedWords {
            guard let index = BIP39Wordlist.index(of: word) else {
                return false
            }
            indices.append(index)
        }

        // Reconstruct the entropy + checksum bits
        var bits = [Bool]()
        for index in indices {
            for bit in (0..<11).reversed() {
                bits.append((index >> bit) & 1 == 1)
            }
        }

        // Split into entropy bits and checksum bits
        let entropyBitCount = strength.rawValue
        let checksumBitCount = strength.checksumBits

        guard bits.count == entropyBitCount + checksumBitCount else {
            return false
        }

        let entropyBits = Array(bits[0..<entropyBitCount])
        let checksumBits = Array(bits[entropyBitCount..<(entropyBitCount + checksumBitCount)])

        // Convert entropy bits back to bytes
        var entropyBytes = Data(count: entropyBitCount / 8)
        for i in 0..<entropyBytes.count {
            var byte: UInt8 = 0
            for bit in 0..<8 {
                if entropyBits[i * 8 + bit] {
                    byte |= (1 << (7 - bit))
                }
            }
            entropyBytes[i] = byte
        }

        // Compute expected checksum
        let hash = SHA256.hash(data: entropyBytes)
        let hashBytes = Array(hash)
        var expectedChecksumBits = [Bool]()
        for i in 0..<checksumBitCount {
            let byteIndex = i / 8
            let bitIndex = 7 - (i % 8)
            expectedChecksumBits.append((hashBytes[byteIndex] >> bitIndex) & 1 == 1)
        }

        // Compare checksums
        return checksumBits == expectedChecksumBits
    }

    // MARK: - Seed Derivation

    /// Derive a 512-bit seed from the mnemonic phrase using PBKDF2-HMAC-SHA512.
    ///
    /// Per BIP39, the seed is derived using:
    /// - Password: the mnemonic phrase (UTF-8 NFKD normalized)
    /// - Salt: "mnemonic" + passphrase (UTF-8 NFKD normalized)
    /// - Iterations: 2048
    /// - Key length: 64 bytes (512 bits)
    ///
    /// - Parameter passphrase: Optional passphrase for additional security (default: empty string)
    /// - Returns: 64-byte seed suitable for BIP32 master key derivation
    func toSeed(passphrase: String = "") -> Data {
        let password = phrase.decomposedStringWithCompatibilityMapping
        let salt = ("mnemonic" + passphrase).decomposedStringWithCompatibilityMapping

        guard let passwordData = password.data(using: .utf8),
              let saltData = salt.data(using: .utf8) else {
            // This should never happen with valid UTF-8 strings
            return Data(count: 64)
        }

        return Mnemonic.pbkdf2HMACSHA512(
            password: passwordData,
            salt: saltData,
            iterations: 2048,
            keyLength: 64
        )
    }

    // MARK: - Private Helpers

    /// Convert entropy bytes to BIP39 mnemonic words.
    ///
    /// - Parameter entropy: The random entropy (16 or 32 bytes)
    /// - Returns: Array of mnemonic words
    /// - Throws: `MnemonicError` if entropy length is invalid
    private static func entropyToWords(_ entropy: Data) throws -> [String] {
        let entropyBits = entropy.count * 8
        guard entropyBits == 128 || entropyBits == 256 else {
            throw MnemonicError.invalidEntropyLength
        }

        // Calculate checksum
        let checksumBitCount = entropyBits / 32
        let hash = SHA256.hash(data: entropy)
        let hashBytes = Array(hash)

        // Build the full bit array: entropy + checksum
        var bits = [Bool]()
        bits.reserveCapacity(entropyBits + checksumBitCount)

        // Append entropy bits
        for byte in entropy {
            for bit in (0..<8).reversed() {
                bits.append((byte >> bit) & 1 == 1)
            }
        }

        // Append checksum bits
        for i in 0..<checksumBitCount {
            let byteIndex = i / 8
            let bitIndex = 7 - (i % 8)
            bits.append((hashBytes[byteIndex] >> bitIndex) & 1 == 1)
        }

        // Split into 11-bit groups and map to words
        let wordCount = bits.count / 11
        var words = [String]()
        words.reserveCapacity(wordCount)

        for i in 0..<wordCount {
            var index = 0
            for bit in 0..<11 {
                if bits[i * 11 + bit] {
                    index |= (1 << (10 - bit))
                }
            }
            guard let word = BIP39Wordlist.word(at: index) else {
                throw MnemonicError.wordlistCompromised
            }
            words.append(word)
        }

        return words
    }

    /// Determine the mnemonic strength from the word count.
    ///
    /// - Parameter count: Number of words
    /// - Returns: The corresponding `MnemonicStrength`, or nil if invalid
    private static func strengthFromWordCount(_ count: Int) -> MnemonicStrength? {
        switch count {
        case 12: return .twelve
        case 24: return .twentyFour
        default: return nil
        }
    }

    // MARK: - PBKDF2 Implementation

    /// PBKDF2 with HMAC-SHA512 implemented using CryptoKit.
    ///
    /// This is a pure-Swift implementation that avoids CommonCrypto dependency.
    /// Follows RFC 2898 / PKCS#5 v2.0 specification.
    ///
    /// - Parameters:
    ///   - password: The password bytes
    ///   - salt: The salt bytes
    ///   - iterations: Number of iterations (2048 for BIP39)
    ///   - keyLength: Desired output key length in bytes
    /// - Returns: The derived key
    static func pbkdf2HMACSHA512(
        password: Data,
        salt: Data,
        iterations: Int,
        keyLength: Int
    ) -> Data {
        let hashLength = 64  // SHA-512 output is 64 bytes
        let blockCount = (keyLength + hashLength - 1) / hashLength

        var derivedKey = Data()
        derivedKey.reserveCapacity(keyLength)

        let symmetricKey = SymmetricKey(data: password)

        for blockIndex in 1...blockCount {
            // U_1 = HMAC(password, salt || INT_32_BE(blockIndex))
            var saltWithIndex = salt
            withUnsafeBytes(of: UInt32(blockIndex).bigEndian) { bytes in
                saltWithIndex.append(contentsOf: bytes)
            }

            var u = Data(HMAC<SHA512>.authenticationCode(
                for: saltWithIndex,
                using: symmetricKey
            ))
            var result = u

            // U_2 ... U_c
            for _ in 1..<iterations {
                u = Data(HMAC<SHA512>.authenticationCode(
                    for: u,
                    using: symmetricKey
                ))
                // XOR into result
                for j in 0..<result.count {
                    result[j] ^= u[j]
                }
            }

            derivedKey.append(result)
        }

        // Truncate to desired key length
        return Data(derivedKey.prefix(keyLength))
    }
}
