// MARK: - AddressValidator.swift
// Bitcoin AI Wallet
//
// Validates Bitcoin addresses using format and length checks.
// Supports mainnet and testnet addresses across all common types:
// P2PKH (1...), P2SH (3...), Segwit (bc1q...), Taproot (bc1p...).
//
// This validator performs structural validation only (prefix, length,
// character set). Full Bech32/Bech32m checksum validation and Base58Check
// checksum validation are handled by the Core library at transaction time.
//
// Platform: iOS 17.0+
// Framework: Foundation

import Foundation

// MARK: - AddressValidator

/// Validates Bitcoin address format, length, and character set.
///
/// This is a lightweight structural validator intended for the chat parser.
/// It catches obviously malformed addresses before they reach the transaction
/// builder. Full checksum validation (Base58Check, Bech32/Bech32m) is
/// deferred to the Core wallet layer.
struct AddressValidator {

    // MARK: - Address Type

    /// The type of a Bitcoin address determined by its prefix.
    enum AddressType: Equatable {
        /// Pay-to-Public-Key-Hash — legacy addresses starting with `1`.
        case p2pkh

        /// Pay-to-Script-Hash — addresses starting with `3`.
        case p2sh

        /// Native SegWit v0 — Bech32 addresses starting with `bc1q`.
        case segwit

        /// Native SegWit v1 (Taproot) — Bech32m addresses starting with `bc1p`.
        case taproot

        /// Address format not recognized.
        case unknown
    }

    // MARK: - Character Sets

    /// Valid characters for Base58Check encoded addresses (P2PKH, P2SH).
    /// Base58 excludes: 0, O, I, l (to avoid visual ambiguity).
    private static let base58Charset = CharacterSet(
        charactersIn: "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
    )

    /// Valid characters for Bech32 / Bech32m encoded addresses (SegWit, Taproot).
    /// Bech32 uses lowercase alphanumeric excluding: 1, b, i, o.
    private static let bech32Charset = CharacterSet(
        charactersIn: "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
    )

    // MARK: - Public API

    /// Validates whether the given string is a structurally valid Bitcoin address.
    ///
    /// Checks prefix, length, and character set. Does not verify checksums.
    ///
    /// - Parameter address: The address string to validate.
    /// - Returns: `true` if the address passes all structural checks.
    func isValid(_ address: String) -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let type = addressType(trimmed)
        switch type {
        case .p2pkh, .p2sh:
            return validateBase58Address(trimmed)
        case .segwit, .taproot:
            return validateBech32Address(trimmed)
        case .unknown:
            // Also check testnet formats
            if isTestnetAddress(trimmed) {
                return validateTestnetAddress(trimmed)
            }
            return false
        }
    }

    /// Determines the address type based on its prefix.
    ///
    /// - Parameter address: The address string to classify.
    /// - Returns: The `AddressType` corresponding to the address prefix.
    func addressType(_ address: String) -> AddressType {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unknown }

        // Bech32 / Bech32m (case-insensitive prefix check)
        let lowercased = trimmed.lowercased()
        if lowercased.hasPrefix("bc1q") {
            return .segwit
        }
        if lowercased.hasPrefix("bc1p") {
            return .taproot
        }

        // Base58Check
        let firstChar = trimmed[trimmed.startIndex]
        if firstChar == "1" {
            return .p2pkh
        }
        if firstChar == "3" {
            return .p2sh
        }

        return .unknown
    }

    /// Checks whether the address belongs to Bitcoin mainnet.
    ///
    /// - Parameter address: The address to check.
    /// - Returns: `true` if the address uses a mainnet prefix.
    func isMainnet(_ address: String) -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()

        // Bech32 mainnet prefix
        if lowercased.hasPrefix("bc1") {
            return true
        }

        // Base58 mainnet prefixes
        guard let first = trimmed.first else { return false }
        return first == "1" || first == "3"
    }

    /// Checks whether the address belongs to Bitcoin testnet.
    ///
    /// - Parameter address: The address to check.
    /// - Returns: `true` if the address uses a testnet prefix.
    func isTestnet(_ address: String) -> Bool {
        return isTestnetAddress(address.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Private Helpers

    /// Validates a Base58Check address (P2PKH or P2SH).
    ///
    /// Checks:
    /// - Length is between 25 and 34 characters (inclusive).
    /// - All characters are valid Base58 characters.
    /// - Base58Check checksum is valid.
    private func validateBase58Address(_ address: String) -> Bool {
        // Length: P2PKH and P2SH addresses are 25-34 characters
        let length = address.count
        guard length >= 25, length <= 34 else { return false }

        // Character set validation
        guard address.unicodeScalars.allSatisfy({ AddressValidator.base58Charset.contains($0) }) else {
            return false
        }

        // Checksum validation via Base58Check decoder.
        // Returns nil if the 4-byte checksum at the end doesn't match.
        guard Base58Check.decode(address) != nil else {
            return false
        }

        return true
    }

    /// Validates a Bech32 / Bech32m address (SegWit or Taproot).
    ///
    /// Checks:
    /// - Correct prefix (`bc1q` for SegWit, `bc1p` for Taproot).
    /// - Appropriate length for the address type.
    /// - Data part contains only valid Bech32 characters.
    /// - No mixed case in the data part.
    /// - Bech32/Bech32m checksum is valid.
    private func validateBech32Address(_ address: String) -> Bool {
        // Bech32 addresses must be entirely lowercase or entirely uppercase.
        // Normalize to lowercase for validation.
        let lowercased = address.lowercased()

        // Check that the original is not mixed case (excluding the prefix separator)
        let hasUpper = address.contains(where: { $0.isUppercase })
        let hasLower = address.contains(where: { $0.isLowercase })
        if hasUpper && hasLower {
            return false
        }

        // Extract the data part after "bc1"
        guard lowercased.hasPrefix("bc1") else { return false }
        let dataStart = lowercased.index(lowercased.startIndex, offsetBy: 3)
        let dataPart = String(lowercased[dataStart...])

        // Must have at least the witness version character + data
        guard dataPart.count >= 2 else { return false }

        // Validate character set of data part
        guard dataPart.unicodeScalars.allSatisfy({ AddressValidator.bech32Charset.contains($0) }) else {
            return false
        }

        // Length validation based on address type
        if lowercased.hasPrefix("bc1q") {
            // SegWit v0: P2WPKH = 42 chars, P2WSH = 62 chars
            let length = lowercased.count
            guard length == 42 || length == 62 else { return false }
        } else if lowercased.hasPrefix("bc1p") {
            // Taproot v1: always 62 characters
            guard lowercased.count == 62 else { return false }
        } else {
            return false
        }

        // Full Bech32/Bech32m checksum validation via the decoder
        do {
            if lowercased.hasPrefix("bc1q") {
                // SegWit v0 uses Bech32
                _ = try Bech32Coder.decodeSegWitAddress(hrp: "bc", address: lowercased)
            } else {
                // Taproot v1 uses Bech32m
                _ = try Bech32mCoder.decodeSegWitAddress(hrp: "bc", address: lowercased)
            }
            return true
        } catch {
            return false
        }
    }

    /// Checks if an address uses testnet prefixes.
    private func isTestnetAddress(_ address: String) -> Bool {
        let lowercased = address.lowercased()

        // Testnet Bech32 prefix
        if lowercased.hasPrefix("tb1") {
            return true
        }

        // Testnet Base58 prefixes: m, n (P2PKH), 2 (P2SH)
        guard let first = address.first else { return false }
        return first == "m" || first == "n" || first == "2"
    }

    /// Validates a testnet address structure.
    private func validateTestnetAddress(_ address: String) -> Bool {
        let lowercased = address.lowercased()

        if lowercased.hasPrefix("tb1") {
            // Testnet Bech32 — same structure rules as mainnet
            let dataStart = lowercased.index(lowercased.startIndex, offsetBy: 3)
            let dataPart = String(lowercased[dataStart...])
            guard dataPart.count >= 2 else { return false }
            guard dataPart.unicodeScalars.allSatisfy({ AddressValidator.bech32Charset.contains($0) }) else {
                return false
            }
            // tb1q... (SegWit) or tb1p... (Taproot)
            if lowercased.hasPrefix("tb1q") {
                let length = lowercased.count
                return length == 42 || length == 62
            }
            if lowercased.hasPrefix("tb1p") {
                return lowercased.count == 62
            }
            return false
        }

        // Testnet Base58: m/n (P2PKH), 2 (P2SH)
        guard let first = address.first else { return false }
        if first == "m" || first == "n" || first == "2" {
            let length = address.count
            guard length >= 25, length <= 34 else { return false }
            guard address.unicodeScalars.allSatisfy({ AddressValidator.base58Charset.contains($0) }) else {
                return false
            }
            return true
        }

        return false
    }
}
