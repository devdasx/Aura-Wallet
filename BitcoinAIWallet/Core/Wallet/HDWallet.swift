import Foundation
import CryptoKit

// MARK: - HD Wallet Errors

/// Errors that can occur during HD wallet operations
enum HDWalletError: LocalizedError {
    case invalidMnemonic
    case seedDerivationFailed
    case masterKeyDerivationFailed
    case keyDerivationFailed(String)
    case addressGenerationFailed
    case invalidAddressType
    case walletNotInitialized
    case mnemonicValidationFailed
    case publicKeyComputationFailed

    var errorDescription: String? {
        switch self {
        case .invalidMnemonic:
            return "Invalid mnemonic phrase"
        case .seedDerivationFailed:
            return "Failed to derive seed from mnemonic"
        case .masterKeyDerivationFailed:
            return "Failed to derive master key from seed"
        case .keyDerivationFailed(let path):
            return "Failed to derive key at path: \(path)"
        case .addressGenerationFailed:
            return "Failed to generate Bitcoin address"
        case .invalidAddressType:
            return "Unsupported address type"
        case .walletNotInitialized:
            return "Wallet has not been properly initialized"
        case .mnemonicValidationFailed:
            return "Mnemonic phrase failed validation"
        case .publicKeyComputationFailed:
            return "Failed to compute public key from private key"
        }
    }
}

// MARK: - Address Type

/// Supported Bitcoin address types
enum AddressType: String, CaseIterable, Identifiable {
    /// BIP44 Legacy P2PKH addresses (1...)
    case legacy

    /// BIP49 Nested SegWit P2SH-P2WPKH addresses (3...)
    case nestedSegwit

    /// BIP84 Native SegWit addresses (bc1q...)
    case segwit

    /// BIP86 Taproot addresses (bc1p...)
    case taproot

    var id: String { rawValue }

    /// Human-readable description of the address type
    var displayName: String {
        switch self {
        case .legacy: return "Legacy (1...)"
        case .nestedSegwit: return "Nested SegWit (3...)"
        case .segwit: return "Native SegWit (bc1q...)"
        case .taproot: return "Taproot (bc1p...)"
        }
    }

    /// The BIP number associated with this address type
    var bipNumber: Int {
        switch self {
        case .legacy: return 44
        case .nestedSegwit: return 49
        case .segwit: return 84
        case .taproot: return 86
        }
    }

    /// The witness version for this address type (nil for non-witness types)
    var witnessVersion: UInt8? {
        switch self {
        case .legacy: return nil
        case .nestedSegwit: return nil
        case .segwit: return 0
        case .taproot: return 1
        }
    }
}

// MARK: - HD Wallet

/// BIP32/BIP39/BIP84/BIP86 Hierarchical Deterministic Wallet.
///
/// This is the main wallet class that combines mnemonic phrase management
/// with hierarchical key derivation to generate Bitcoin addresses.
///
/// Supports:
/// - BIP39 mnemonic generation and restoration (12 or 24 words)
/// - BIP32 hierarchical deterministic key derivation
/// - BIP84 Native SegWit addresses (bc1q...)
/// - BIP86 Taproot addresses (bc1p...)
///
/// Usage:
/// ```swift
/// // Create a new wallet
/// let wallet = try HDWallet.create()
///
/// // Get receive address
/// let address = try wallet.nextReceiveAddress()
///
/// // Restore from mnemonic
/// let restored = try HDWallet.restore(words: ["abandon", ...])
/// ```
final class HDWallet: ObservableObject {

    // MARK: - Properties

    /// The BIP39 mnemonic phrase for this wallet
    let mnemonic: Mnemonic

    /// The derived BIP39 seed (64 bytes)
    private let seed: Data

    /// The BIP32 master extended key
    private let masterKey: ExtendedKey

    /// Current receive address index for Legacy (BIP44)
    @Published var currentLegacyReceiveIndex: UInt32 = 0

    /// Current change address index for Legacy (BIP44)
    @Published var currentLegacyChangeIndex: UInt32 = 0

    /// Current receive address index for Nested SegWit (BIP49)
    @Published var currentNestedSegwitReceiveIndex: UInt32 = 0

    /// Current change address index for Nested SegWit (BIP49)
    @Published var currentNestedSegwitChangeIndex: UInt32 = 0

    /// Current receive address index for SegWit (BIP84)
    @Published var currentReceiveIndex: UInt32 = 0

    /// Current change address index for SegWit (BIP84)
    @Published var currentChangeIndex: UInt32 = 0

    /// Current receive address index for Taproot (BIP86)
    @Published var currentTaprootReceiveIndex: UInt32 = 0

    /// Current change address index for Taproot (BIP86)
    @Published var currentTaprootChangeIndex: UInt32 = 0

    /// Human-readable part for Bech32 addresses ("bc" for mainnet)
    private let hrp = "bc"

    // MARK: - Initialization

    /// Create a wallet from an existing mnemonic phrase.
    ///
    /// - Parameters:
    ///   - mnemonic: A validated `Mnemonic` instance
    ///   - passphrase: Optional BIP39 passphrase for additional security (default: empty)
    /// - Throws: `HDWalletError` if seed or master key derivation fails
    init(mnemonic: Mnemonic, passphrase: String = "") throws {
        self.mnemonic = mnemonic

        // Derive seed using PBKDF2-HMAC-SHA512
        let derivedSeed = mnemonic.toSeed(passphrase: passphrase)
        guard derivedSeed.count == 64 else {
            throw HDWalletError.seedDerivationFailed
        }
        self.seed = derivedSeed

        // Derive master key
        do {
            self.masterKey = try ExtendedKey.masterKey(from: derivedSeed)
        } catch {
            throw HDWalletError.masterKeyDerivationFailed
        }
    }

    // MARK: - Factory Methods

    /// Generate a new wallet with a fresh random mnemonic.
    ///
    /// - Parameter strength: Mnemonic strength (`.twelve` for 12 words, `.twentyFour` for 24 words)
    /// - Returns: A new `HDWallet` instance
    /// - Throws: `HDWalletError` or `MnemonicError` if generation fails
    static func create(strength: MnemonicStrength = .twelve) throws -> HDWallet {
        let mnemonic = try Mnemonic.generate(strength: strength)
        return try HDWallet(mnemonic: mnemonic)
    }

    /// Restore a wallet from an existing mnemonic word list.
    ///
    /// Validates all words and the checksum before creating the wallet.
    ///
    /// - Parameters:
    ///   - words: Array of 12 or 24 BIP39 English words
    ///   - passphrase: Optional BIP39 passphrase (default: empty)
    /// - Returns: A restored `HDWallet` instance
    /// - Throws: `HDWalletError` or `MnemonicError` if the words are invalid
    static func restore(words: [String], passphrase: String = "") throws -> HDWallet {
        let mnemonic = try Mnemonic.restore(words: words)
        return try HDWallet(mnemonic: mnemonic, passphrase: passphrase)
    }

    /// Restore a wallet from a space-separated mnemonic phrase string.
    ///
    /// - Parameters:
    ///   - phrase: Space-separated mnemonic words
    ///   - passphrase: Optional BIP39 passphrase (default: empty)
    /// - Returns: A restored `HDWallet` instance
    /// - Throws: `HDWalletError` or `MnemonicError` if the phrase is invalid
    static func restore(phrase: String, passphrase: String = "") throws -> HDWallet {
        let words = phrase.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .map { String($0) }
        return try restore(words: words, passphrase: passphrase)
    }

    // MARK: - Key Derivation

    /// Get the private key at a specific derivation path.
    ///
    /// - Parameter path: BIP32 derivation path (e.g., "m/84'/0'/0'/0/0")
    /// - Returns: 32-byte private key data
    /// - Throws: `HDWalletError` if derivation fails
    func privateKey(path: String) throws -> Data {
        do {
            let key = try ExtendedKey.derivePath(path, from: seed)
            return key.privateKey
        } catch {
            throw HDWalletError.keyDerivationFailed(path)
        }
    }

    /// Get the compressed public key at a specific derivation path.
    ///
    /// - Parameter path: BIP32 derivation path (e.g., "m/84'/0'/0'/0/0")
    /// - Returns: 33-byte compressed public key data
    /// - Throws: `HDWalletError` if derivation fails
    func publicKey(path: String) throws -> Data {
        do {
            let key = try ExtendedKey.derivePath(path, from: seed)
            return key.publicKey
        } catch {
            throw HDWalletError.keyDerivationFailed(path)
        }
    }

    /// Get the extended key at a specific derivation path.
    ///
    /// - Parameter path: BIP32 derivation path
    /// - Returns: The full `ExtendedKey` at that path
    /// - Throws: `HDWalletError` if derivation fails
    func extendedKey(path: String) throws -> ExtendedKey {
        do {
            return try ExtendedKey.derivePath(path, from: seed)
        } catch {
            throw HDWalletError.keyDerivationFailed(path)
        }
    }

    // MARK: - Address Generation

    /// Get the next unused receive address.
    ///
    /// Automatically increments the internal receive index counter.
    ///
    /// - Parameter type: The address type (default: `.segwit` for bc1q...)
    /// - Returns: The Bitcoin address string
    /// - Throws: `HDWalletError` if address generation fails
    @discardableResult
    func nextReceiveAddress(type: AddressType = .segwit) throws -> String {
        let index: UInt32
        switch type {
        case .legacy:
            index = currentLegacyReceiveIndex
        case .nestedSegwit:
            index = currentNestedSegwitReceiveIndex
        case .segwit:
            index = currentReceiveIndex
        case .taproot:
            index = currentTaprootReceiveIndex
        }

        let address = try generateAddress(type: type, change: 0, index: index)

        // Increment the counter on the main queue for @Published properties
        DispatchQueue.main.async { [weak self] in
            switch type {
            case .legacy:
                self?.currentLegacyReceiveIndex += 1
            case .nestedSegwit:
                self?.currentNestedSegwitReceiveIndex += 1
            case .segwit:
                self?.currentReceiveIndex += 1
            case .taproot:
                self?.currentTaprootReceiveIndex += 1
            }
        }

        return address
    }

    /// Get the next unused change address.
    ///
    /// Automatically increments the internal change index counter.
    ///
    /// - Parameter type: The address type (default: `.segwit` for bc1q...)
    /// - Returns: The Bitcoin address string
    /// - Throws: `HDWalletError` if address generation fails
    @discardableResult
    func nextChangeAddress(type: AddressType = .segwit) throws -> String {
        let index: UInt32
        switch type {
        case .legacy:
            index = currentLegacyChangeIndex
        case .nestedSegwit:
            index = currentNestedSegwitChangeIndex
        case .segwit:
            index = currentChangeIndex
        case .taproot:
            index = currentTaprootChangeIndex
        }

        let address = try generateAddress(type: type, change: 1, index: index)

        // Increment the counter on the main queue for @Published properties
        DispatchQueue.main.async { [weak self] in
            switch type {
            case .legacy:
                self?.currentLegacyChangeIndex += 1
            case .nestedSegwit:
                self?.currentNestedSegwitChangeIndex += 1
            case .segwit:
                self?.currentChangeIndex += 1
            case .taproot:
                self?.currentTaprootChangeIndex += 1
            }
        }

        return address
    }

    /// Generate an address at a specific index without incrementing counters.
    ///
    /// - Parameters:
    ///   - type: The address type
    ///   - account: Account index (default: 0)
    ///   - change: 0 for receive, 1 for change
    ///   - index: Address index
    /// - Returns: The Bitcoin address string
    /// - Throws: `HDWalletError` if address generation fails
    func addressAt(type: AddressType = .segwit, account: UInt32 = 0, change: UInt32, index: UInt32) throws -> String {
        try generateAddress(type: type, account: account, change: change, index: index)
    }

    /// Generate a batch of receive addresses.
    ///
    /// Useful for pre-generating addresses for display or gap limit scanning.
    ///
    /// - Parameters:
    ///   - type: The address type
    ///   - count: Number of addresses to generate
    ///   - startIndex: Starting index (default: 0)
    /// - Returns: Array of (index, address) tuples
    /// - Throws: `HDWalletError` if address generation fails
    func generateReceiveAddresses(type: AddressType = .segwit, count: Int, startIndex: UInt32 = 0) throws -> [(index: UInt32, address: String)] {
        var addresses = [(index: UInt32, address: String)]()
        addresses.reserveCapacity(count)

        for i in 0..<UInt32(count) {
            let index = startIndex + i
            let address = try generateAddress(type: type, change: 0, index: index)
            addresses.append((index: index, address: address))
        }

        return addresses
    }

    // MARK: - Extended Public Key

    /// Get the extended public key (xpub) for a specific account.
    ///
    /// The xpub can be shared to allow watch-only address generation
    /// without exposing private keys.
    ///
    /// - Parameter account: Account index (default: 0)
    /// - Returns: Base58Check-encoded xpub string
    /// - Throws: `HDWalletError` if derivation fails
    func extendedPublicKey(account: UInt32 = 0) throws -> String {
        let path = DerivationPath.segwitAccount(account: account)
        do {
            let key = try ExtendedKey.derivePath(path, from: seed)
            return key.serializedPublic
        } catch {
            throw HDWalletError.keyDerivationFailed(path)
        }
    }

    /// Get the extended public key for a specific address type and account.
    ///
    /// Returns the appropriate serialization format:
    /// - BIP44 (legacy): xpub (version 0x0488B21E)
    /// - BIP49 (nested SegWit): ypub (version 0x049D7CB2)
    /// - BIP84 (native SegWit): zpub (version 0x04B24746)
    /// - BIP86 (taproot): xpub at m/86'/0'/account'
    ///
    /// - Parameters:
    ///   - type: The address type determining the derivation path and serialization
    ///   - account: Account index (default: 0)
    /// - Returns: Base58Check-encoded extended public key string
    /// - Throws: `HDWalletError` if derivation fails
    func extendedPublicKeyForType(_ type: AddressType, account: UInt32 = 0) throws -> String {
        let path: String
        let versionBytes: [UInt8]

        switch type {
        case .legacy:
            path = DerivationPath.legacyAccount(account: account)
            versionBytes = [0x04, 0x88, 0xB2, 0x1E] // xpub
        case .nestedSegwit:
            path = DerivationPath.nestedSegwitAccount(account: account)
            versionBytes = [0x04, 0x9D, 0x7C, 0xB2] // ypub
        case .segwit:
            path = DerivationPath.segwitAccount(account: account)
            versionBytes = [0x04, 0xB2, 0x47, 0x46] // zpub
        case .taproot:
            path = DerivationPath.taprootAccount(account: account)
            versionBytes = [0x04, 0x88, 0xB2, 0x1E] // xpub (no standard for taproot)
        }

        do {
            let key = try ExtendedKey.derivePath(path, from: seed)
            return key.serializedPublicWithVersion(versionBytes)
        } catch {
            throw HDWalletError.keyDerivationFailed(path)
        }
    }

    /// Get the extended private key (xprv) for a specific account.
    ///
    /// WARNING: This exposes the private key material. Handle with extreme care.
    ///
    /// - Parameter account: Account index (default: 0)
    /// - Returns: Base58Check-encoded xprv string
    /// - Throws: `HDWalletError` if derivation fails
    func extendedPrivateKey(account: UInt32 = 0) throws -> String {
        let path = DerivationPath.segwitAccount(account: account)
        do {
            let key = try ExtendedKey.derivePath(path, from: seed)
            return key.serialized
        } catch {
            throw HDWalletError.keyDerivationFailed(path)
        }
    }

    // MARK: - Wallet Info

    /// The master key fingerprint (first 4 bytes of master public key hash)
    var masterFingerprint: Data {
        masterKey.fingerprintForChildren
    }

    /// The master key fingerprint as a hex string
    var masterFingerprintHex: String {
        masterFingerprint.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Private Address Generation

    /// Generate a Bitcoin address for the given parameters.
    ///
    /// - Parameters:
    ///   - type: Address type (segwit or taproot)
    ///   - account: Account index
    ///   - change: 0 for receive, 1 for change
    ///   - index: Address index
    /// - Returns: The Bitcoin address string
    /// - Throws: `HDWalletError` if generation fails
    private func generateAddress(
        type: AddressType,
        account: UInt32 = 0,
        change: UInt32,
        index: UInt32
    ) throws -> String {
        let path: String
        switch type {
        case .legacy:
            path = DerivationPath.legacy(account: account, change: change, index: index)
        case .nestedSegwit:
            path = DerivationPath.nestedSegwit(account: account, change: change, index: index)
        case .segwit:
            path = DerivationPath.segwit(account: account, change: change, index: index)
        case .taproot:
            path = DerivationPath.taproot(account: account, change: change, index: index)
        }

        let key: ExtendedKey
        do {
            key = try ExtendedKey.derivePath(path, from: seed)
        } catch {
            throw HDWalletError.keyDerivationFailed(path)
        }

        switch type {
        case .legacy:
            return try makeLegacyAddress(publicKey: key.publicKey)
        case .nestedSegwit:
            return try makeNestedSegwitAddress(publicKey: key.publicKey)
        case .segwit:
            return try makeSegwitAddress(publicKey: key.publicKey)
        case .taproot:
            return try makeTaprootAddress(compressedPublicKey: key.publicKey)
        }
    }

    /// Generate a BIP44 Legacy P2PKH (1...) address.
    ///
    /// Address = Base58Check(0x00 + RIPEMD160(SHA256(compressed_public_key)))
    ///
    /// - Parameter publicKey: 33-byte compressed public key
    /// - Returns: 1... address string
    /// - Throws: `HDWalletError` if generation fails
    private func makeLegacyAddress(publicKey: Data) throws -> String {
        guard publicKey.count == 33 else {
            throw HDWalletError.publicKeyComputationFailed
        }

        // Hash160 = RIPEMD160(SHA256(publicKey))
        let sha256Hash = Data(SHA256.hash(data: publicKey))
        let hash160 = ripemd160(sha256Hash)

        // Prepend version byte 0x00 for mainnet P2PKH
        var payload = Data([0x00])
        payload.append(hash160)

        return base58CheckEncode(payload)
    }

    /// Generate a BIP49 Nested SegWit P2SH-P2WPKH (3...) address.
    ///
    /// 1. Compute witness program: OP_0 <RIPEMD160(SHA256(pubkey))>
    /// 2. Compute redeem script hash: RIPEMD160(SHA256(witness_program))
    /// 3. Address = Base58Check(0x05 + script_hash)
    ///
    /// - Parameter publicKey: 33-byte compressed public key
    /// - Returns: 3... address string
    /// - Throws: `HDWalletError` if generation fails
    private func makeNestedSegwitAddress(publicKey: Data) throws -> String {
        guard publicKey.count == 33 else {
            throw HDWalletError.publicKeyComputationFailed
        }

        // Hash160 of the public key
        let sha256Hash = Data(SHA256.hash(data: publicKey))
        let keyHash = ripemd160(sha256Hash)

        // Build the witness program (redeemScript): OP_0 <20-byte-hash>
        var redeemScript = Data([0x00, 0x14]) // OP_0 + push 20 bytes
        redeemScript.append(keyHash)

        // Hash160 of the redeem script
        let scriptSha = Data(SHA256.hash(data: redeemScript))
        let scriptHash = ripemd160(scriptSha)

        // Prepend version byte 0x05 for mainnet P2SH
        var payload = Data([0x05])
        payload.append(scriptHash)

        return base58CheckEncode(payload)
    }

    /// Generate a BIP84 Native SegWit (bc1q) address.
    ///
    /// Witness program = RIPEMD160(SHA256(compressed_public_key))
    /// Address = Bech32(hrp, witnessVersion=0, witness_program)
    ///
    /// - Parameter publicKey: 33-byte compressed public key
    /// - Returns: bc1q... address string
    /// - Throws: `HDWalletError` if generation fails
    private func makeSegwitAddress(publicKey: Data) throws -> String {
        guard publicKey.count == 33 else {
            throw HDWalletError.publicKeyComputationFailed
        }

        // Hash160 = RIPEMD160(SHA256(publicKey))
        let sha256Hash = Data(SHA256.hash(data: publicKey))
        let hash160 = ripemd160(sha256Hash)

        guard let address = SegWitAddressEncoder.encode(hrp: hrp, witnessVersion: 0, witnessProgram: hash160) else {
            throw HDWalletError.addressGenerationFailed
        }

        return address
    }

    /// Generate a BIP86 Taproot (bc1p) address.
    ///
    /// Implements BIP341 key-path spending with BIP86 key tweaking:
    /// 1. Extract x-only internal public key (32 bytes)
    /// 2. If y is odd, negate to get the even-y variant
    /// 3. Compute tweak: t = tagged_hash("TapTweak", internal_key)
    /// 4. Compute output key: Q = P + t * G
    /// 5. Witness program = x(Q) (32 bytes, x-only)
    ///
    /// - Parameter compressedPublicKey: 33-byte compressed public key
    /// - Returns: bc1p... address string
    /// - Throws: `HDWalletError` if generation fails
    private func makeTaprootAddress(compressedPublicKey: Data) throws -> String {
        guard compressedPublicKey.count == 33 else {
            throw HDWalletError.publicKeyComputationFailed
        }

        // Use TaprootTweaker to compute the tweaked x-only output key
        guard let outputKeyX = TaprootTweaker.tweakedOutputKeyX(from: compressedPublicKey) else {
            throw HDWalletError.addressGenerationFailed
        }

        // Encode as Bech32m (witness version 1) address
        guard let address = SegWitAddressEncoder.encode(hrp: hrp, witnessVersion: 1, witnessProgram: outputKeyX) else {
            throw HDWalletError.addressGenerationFailed
        }

        return address
    }
}

// MARK: - Secure Memory Helpers

extension HDWallet {

    /// Securely wipe sensitive data from memory.
    ///
    /// Uses volatile writes to prevent compiler optimization from removing the wipe.
    /// Call this when sensitive data is being discarded.
    ///
    /// - Parameter data: The data to securely zero out
    static func secureWipe(_ data: inout Data) {
        let count = data.count
        data.withUnsafeMutableBytes { buffer in
            if let baseAddress = buffer.baseAddress {
                // Volatile-style wipe: write zeros
                memset(baseAddress, 0, count)
                // Read back to ensure compiler does not optimize away the wipe
                _ = buffer.load(as: UInt8.self)
            }
        }
        data = Data()
    }
}

// MARK: - Debug Description (Non-sensitive)

extension HDWallet: CustomStringConvertible {

    /// A safe description that does NOT expose sensitive key material.
    var description: String {
        let wordCount = mnemonic.words.count
        let fingerprint = masterFingerprintHex
        return "HDWallet(words: \(wordCount), fingerprint: \(fingerprint))"
    }
}
