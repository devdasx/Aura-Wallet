// MARK: - Bech32m.swift
// Bitcoin AI Wallet
//
// BIP350 Bech32m encoding and decoding for Taproot addresses (bc1p...).
// Bech32m is identical to Bech32 except for a different checksum constant,
// which provides better error-detection properties for SegWit version 1+.
//
// Named `Bech32mCoder` to avoid collision with the `Bech32` enum in
// KeyDerivation.swift (which handles both Bech32 and Bech32m via an
// internal Encoding enum).
//
// Reference: https://github.com/bitcoin/bips/blob/master/bip-0350.mediawiki
//
// Platform: iOS 17.0+
// Framework: Foundation (zero external dependencies)

import Foundation

// MARK: - Bech32mCoder

/// BIP350 Bech32m encoding and decoding.
///
/// Bech32m is used for SegWit witness version 1 and above (Taproot/P2TR).
/// It is identical to Bech32 in structure but uses a different constant
/// (`0x2bc830a3` instead of `1`) in the checksum computation, which provides
/// superior error detection for the longer witness programs used by Taproot.
enum Bech32mCoder {

    // MARK: - Constants

    /// The Bech32m checksum constant, as defined in BIP350.
    static let bech32mConst: UInt32 = 0x2bc830a3

    // MARK: - Encoding

    /// Encode data as a Bech32m string.
    ///
    /// The data array must contain 5-bit values (0-31). The witness version byte
    /// (e.g., 0x01 for Taproot) should be prepended to the data before calling.
    ///
    /// - Parameters:
    ///   - hrp: Human-readable part (e.g., "bc" for mainnet, "tb" for testnet).
    ///   - data: Array of 5-bit values to encode.
    /// - Returns: The Bech32m-encoded string.
    /// - Throws: `Bech32Coder.Bech32Error` if the HRP is empty or data is invalid.
    static func encode(hrp: String, data: [UInt8]) throws -> String {
        let hrpLower = hrp.lowercased()
        guard !hrpLower.isEmpty else {
            throw Bech32Coder.Bech32Error.invalidHRP
        }

        for value in data {
            guard value < 32 else {
                throw Bech32Coder.Bech32Error.invalidCharacter
            }
        }

        let checksum = createChecksum(hrp: hrpLower, data: data)
        let combined = data + checksum

        let charsetArray = Array(Bech32Coder.charset)
        var result = hrpLower + String(Bech32Coder.separator)

        for value in combined {
            result.append(charsetArray[Int(value)])
        }

        return result
    }

    // MARK: - Decoding

    /// Decode a Bech32m string into its human-readable part and data.
    ///
    /// - Parameter string: The Bech32m-encoded string to decode.
    /// - Returns: A tuple of (hrp, data) where data is an array of 5-bit values.
    /// - Throws: `Bech32Coder.Bech32Error` if the string is malformed or checksum is invalid.
    static func decode(_ string: String) throws -> (hrp: String, data: [UInt8]) {
        // Check for mixed case
        let hasUpper = string.contains(where: { $0.isUppercase })
        let hasLower = string.contains(where: { $0.isLowercase })
        if hasUpper && hasLower {
            throw Bech32Coder.Bech32Error.mixedCase
        }

        let lowercased = string.lowercased()

        // Validate overall length (max 90 characters per BIP173/BIP350)
        guard lowercased.count >= 8, lowercased.count <= 90 else {
            throw Bech32Coder.Bech32Error.invalidLength
        }

        // Find the last separator
        guard let separatorIndex = lowercased.lastIndex(of: Bech32Coder.separator) else {
            throw Bech32Coder.Bech32Error.invalidHRP
        }

        let hrp = String(lowercased[lowercased.startIndex..<separatorIndex])
        guard !hrp.isEmpty else {
            throw Bech32Coder.Bech32Error.invalidHRP
        }

        // Validate HRP characters (ASCII 33-126)
        for scalar in hrp.unicodeScalars {
            guard scalar.value >= 33, scalar.value <= 126 else {
                throw Bech32Coder.Bech32Error.invalidHRP
            }
        }

        let dataStart = lowercased.index(after: separatorIndex)
        let dataPart = String(lowercased[dataStart...])

        // Data part must be at least 6 characters (checksum)
        guard dataPart.count >= 6 else {
            throw Bech32Coder.Bech32Error.invalidLength
        }

        // Decode data characters to 5-bit values
        let charsetArray = Array(Bech32Coder.charset)
        var data = [UInt8]()
        data.reserveCapacity(dataPart.count)

        for char in dataPart {
            guard let index = charsetArray.firstIndex(of: char) else {
                throw Bech32Coder.Bech32Error.invalidCharacter
            }
            data.append(UInt8(index))
        }

        // Verify checksum using Bech32m constant
        guard verifyChecksum(hrp: hrp, data: data) else {
            throw Bech32Coder.Bech32Error.invalidChecksum
        }

        // Remove the 6-byte checksum
        let payload = Array(data.dropLast(6))

        return (hrp: hrp, data: payload)
    }

    // MARK: - Checksum

    /// Create the 6-byte Bech32m checksum for the given HRP and data.
    ///
    /// Uses the Bech32m constant (`0x2bc830a3`) instead of the Bech32 constant (`1`).
    ///
    /// - Parameters:
    ///   - hrp: The human-readable part.
    ///   - data: The data values (5-bit each).
    /// - Returns: Array of 6 checksum values (5-bit each).
    static func createChecksum(hrp: String, data: [UInt8]) -> [UInt8] {
        let values = Bech32Coder.hrpExpand(hrp) + data + [0, 0, 0, 0, 0, 0]
        let polymodValue = Bech32Coder.polymod(values) ^ bech32mConst
        var checksum = [UInt8]()
        checksum.reserveCapacity(6)

        for i in 0..<6 {
            checksum.append(UInt8((polymodValue >> (5 * (5 - i))) & 31))
        }

        return checksum
    }

    /// Verify the Bech32m checksum of the given HRP and data.
    ///
    /// - Parameters:
    ///   - hrp: The human-readable part.
    ///   - data: The full data including the 6-byte checksum.
    /// - Returns: `true` if the checksum is valid for Bech32m.
    static func verifyChecksum(hrp: String, data: [UInt8]) -> Bool {
        let values = Bech32Coder.hrpExpand(hrp) + data
        return Bech32Coder.polymod(values) == bech32mConst
    }

    // MARK: - SegWit Address Helpers

    /// Decode a SegWit v1+ address (Taproot) into its witness version and program.
    ///
    /// - Parameters:
    ///   - hrp: Expected human-readable part ("bc" or "tb").
    ///   - address: The Bech32m-encoded address.
    /// - Returns: A tuple of (witnessVersion, witnessProgram).
    /// - Throws: `Bech32Coder.Bech32Error` if the address is invalid.
    static func decodeSegWitAddress(hrp: String, address: String) throws -> (version: UInt8, program: Data) {
        let decoded = try decode(address)

        guard decoded.hrp == hrp else {
            throw Bech32Coder.Bech32Error.invalidHRP
        }

        guard !decoded.data.isEmpty else {
            throw Bech32Coder.Bech32Error.invalidDataLength
        }

        let witnessVersion = decoded.data[0]

        // Bech32m is used for witness version 1 and above
        guard witnessVersion >= 1, witnessVersion <= 16 else {
            throw Bech32Coder.Bech32Error.invalidWitnessVersion
        }

        let programData = try Bech32Coder.convertBits(
            data: Array(decoded.data.dropFirst()),
            fromBits: 5,
            toBits: 8,
            pad: false
        )

        // Witness version 1 (Taproot) requires exactly 32 bytes
        if witnessVersion == 1 {
            guard programData.count == 32 else {
                throw Bech32Coder.Bech32Error.invalidDataLength
            }
        }

        // General witness program length: 2-40 bytes
        guard programData.count >= 2, programData.count <= 40 else {
            throw Bech32Coder.Bech32Error.invalidDataLength
        }

        return (version: witnessVersion, program: Data(programData))
    }

    /// Encode a Taproot address from a witness version and program.
    ///
    /// Convenience method that handles the 8-to-5-bit conversion and
    /// prepends the witness version.
    ///
    /// - Parameters:
    ///   - hrp: Human-readable part ("bc" for mainnet, "tb" for testnet).
    ///   - witnessVersion: Witness version (must be >= 1).
    ///   - witnessProgram: The witness program data (32 bytes for Taproot).
    /// - Returns: The Bech32m-encoded address string, or nil if parameters are invalid.
    static func encodeAddress(hrp: String, witnessVersion: UInt8, witnessProgram: Data) -> String? {
        guard witnessProgram.count >= 2, witnessProgram.count <= 40 else { return nil }
        guard witnessVersion >= 1, witnessVersion <= 16 else { return nil }

        if witnessVersion == 1 {
            guard witnessProgram.count == 32 else { return nil }
        }

        guard let converted = try? Bech32Coder.convertBits(
            data: Array(witnessProgram),
            fromBits: 8,
            toBits: 5,
            pad: true
        ) else {
            return nil
        }

        let data = [witnessVersion] + converted
        return try? encode(hrp: hrp, data: data)
    }
}
