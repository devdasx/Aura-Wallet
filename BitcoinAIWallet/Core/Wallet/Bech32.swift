// MARK: - Bech32.swift
// Bitcoin AI Wallet
//
// BIP173 Bech32 encoding and decoding for native SegWit addresses (bc1q...).
// Implements the full Bech32 specification including polymod checksum,
// HRP expansion, 5-bit/8-bit conversion, and address encoding/decoding.
//
// Named `Bech32Coder` to avoid collision with the simplified `Bech32` enum
// in KeyDerivation.swift (which handles basic encode-only for HDWallet).
//
// Reference: https://github.com/bitcoin/bips/blob/master/bip-0173.mediawiki
//
// Platform: iOS 17.0+
// Framework: Foundation (zero external dependencies)

import Foundation

// MARK: - Bech32Coder

/// BIP173 Bech32 encoding and decoding.
///
/// Bech32 is used for native SegWit version 0 addresses (P2WPKH and P2WSH).
/// The encoding scheme uses a BCH error-detecting code with a 6-character checksum,
/// and represents data using a 32-character alphabet that avoids visually ambiguous
/// characters.
///
/// This is the full-featured implementation supporting both encoding and decoding,
/// with complete validation and error reporting. It complements the simpler
/// `Bech32.encode(hrp:witnessVersion:witnessProgram:)` in `KeyDerivation.swift`.
enum Bech32Coder {

    // MARK: - Errors

    /// Errors that can occur during Bech32 encoding or decoding.
    enum Bech32Error: Error, LocalizedError {
        case invalidCharacter
        case invalidChecksum
        case invalidLength
        case invalidHRP
        case invalidWitnessVersion
        case invalidDataLength
        case conversionFailed
        case mixedCase

        var errorDescription: String? {
            switch self {
            case .invalidCharacter:
                return "Bech32 string contains an invalid character"
            case .invalidChecksum:
                return "Bech32 checksum verification failed"
            case .invalidLength:
                return "Bech32 string has an invalid length"
            case .invalidHRP:
                return "Invalid human-readable part (HRP)"
            case .invalidWitnessVersion:
                return "Invalid SegWit witness version"
            case .invalidDataLength:
                return "Invalid data length for witness program"
            case .conversionFailed:
                return "Failed to convert between bit widths"
            case .mixedCase:
                return "Bech32 string contains mixed case characters"
            }
        }
    }

    // MARK: - Constants

    /// The Bech32 character set (32 characters, indexed 0-31).
    /// Excludes: 1, b, i, o to avoid visual ambiguity.
    static let charset = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"

    /// Generator polynomial coefficients for the BCH code.
    static let generator: [UInt32] = [
        0x3b6a57b2,
        0x26508e6d,
        0x1ea119fa,
        0x3d4233dd,
        0x2a1462b3
    ]

    /// The Bech32 checksum constant. For standard Bech32 (BIP173), this is 1.
    static let bech32Const: UInt32 = 1

    /// Separator between the human-readable part and the data part.
    static let separator: Character = "1"

    // MARK: - Encoding

    /// Encode data as a Bech32 string.
    ///
    /// The data array must contain 5-bit values (0-31). The witness version byte
    /// should be prepended to the data before calling this method.
    ///
    /// - Parameters:
    ///   - hrp: Human-readable part (e.g., "bc" for mainnet, "tb" for testnet).
    ///   - data: Array of 5-bit values to encode.
    /// - Returns: The Bech32-encoded string.
    /// - Throws: `Bech32Error` if the HRP is empty or data contains invalid values.
    static func encode(hrp: String, data: [UInt8]) throws -> String {
        let hrpLower = hrp.lowercased()
        guard !hrpLower.isEmpty else {
            throw Bech32Error.invalidHRP
        }

        for value in data {
            guard value < 32 else {
                throw Bech32Error.invalidCharacter
            }
        }

        let checksum = createChecksum(hrp: hrpLower, data: data)
        let combined = data + checksum

        let charsetArray = Array(charset)
        var result = hrpLower + String(separator)

        for value in combined {
            result.append(charsetArray[Int(value)])
        }

        return result
    }

    // MARK: - Decoding

    /// Decode a Bech32 string into its human-readable part and data.
    ///
    /// - Parameter string: The Bech32-encoded string to decode.
    /// - Returns: A tuple of (hrp, data) where data is an array of 5-bit values
    ///   (including the witness version as the first element).
    /// - Throws: `Bech32Error` if the string is malformed or the checksum is invalid.
    static func decode(_ string: String) throws -> (hrp: String, data: [UInt8]) {
        // Check for mixed case
        let hasUpper = string.contains(where: { $0.isUppercase })
        let hasLower = string.contains(where: { $0.isLowercase })
        if hasUpper && hasLower {
            throw Bech32Error.mixedCase
        }

        let lowercased = string.lowercased()

        // Validate overall length (max 90 characters per BIP173)
        guard lowercased.count >= 8, lowercased.count <= 90 else {
            throw Bech32Error.invalidLength
        }

        // Find the last separator
        guard let separatorIndex = lowercased.lastIndex(of: separator) else {
            throw Bech32Error.invalidHRP
        }

        let hrp = String(lowercased[lowercased.startIndex..<separatorIndex])
        guard !hrp.isEmpty else {
            throw Bech32Error.invalidHRP
        }

        // Validate HRP characters (ASCII 33-126)
        for scalar in hrp.unicodeScalars {
            guard scalar.value >= 33, scalar.value <= 126 else {
                throw Bech32Error.invalidHRP
            }
        }

        let dataStart = lowercased.index(after: separatorIndex)
        let dataPart = String(lowercased[dataStart...])

        // Data part must be at least 6 characters (checksum)
        guard dataPart.count >= 6 else {
            throw Bech32Error.invalidLength
        }

        // Decode data characters to 5-bit values
        let charsetArray = Array(charset)
        var data = [UInt8]()
        data.reserveCapacity(dataPart.count)

        for char in dataPart {
            guard let index = charsetArray.firstIndex(of: char) else {
                throw Bech32Error.invalidCharacter
            }
            data.append(UInt8(index))
        }

        // Verify checksum
        guard verifyChecksum(hrp: hrp, data: data) else {
            throw Bech32Error.invalidChecksum
        }

        // Remove the 6-byte checksum
        let payload = Array(data.dropLast(6))

        return (hrp: hrp, data: payload)
    }

    // MARK: - Bit Conversion

    /// Convert between different bit-width representations.
    ///
    /// Used to convert between 8-bit byte arrays and 5-bit Bech32 value arrays.
    ///
    /// - Parameters:
    ///   - data: The input data array.
    ///   - fromBits: The bit width of each input element (e.g., 8).
    ///   - toBits: The bit width of each output element (e.g., 5).
    ///   - pad: Whether to pad the output with zeros if there are remaining bits.
    /// - Returns: The converted data array.
    /// - Throws: `Bech32Error.conversionFailed` if conversion fails.
    static func convertBits(data: [UInt8], fromBits: Int, toBits: Int, pad: Bool) throws -> [UInt8] {
        var accumulator: UInt32 = 0
        var bits: Int = 0
        var result = [UInt8]()
        let maxValue: UInt32 = (1 << toBits) - 1

        for value in data {
            let v = UInt32(value)
            guard v >> fromBits == 0 else {
                throw Bech32Error.conversionFailed
            }
            accumulator = (accumulator << fromBits) | v
            bits += fromBits

            while bits >= toBits {
                bits -= toBits
                result.append(UInt8((accumulator >> bits) & maxValue))
            }
        }

        if pad {
            if bits > 0 {
                result.append(UInt8((accumulator << (toBits - bits)) & maxValue))
            }
        } else {
            if bits >= fromBits {
                throw Bech32Error.conversionFailed
            }
            if (accumulator << (toBits - bits)) & maxValue != 0 {
                throw Bech32Error.conversionFailed
            }
        }

        return result
    }

    // MARK: - Checksum

    /// Create the 6-byte Bech32 checksum for the given HRP and data.
    ///
    /// - Parameters:
    ///   - hrp: The human-readable part.
    ///   - data: The data values (5-bit each).
    /// - Returns: Array of 6 checksum values (5-bit each).
    static func createChecksum(hrp: String, data: [UInt8]) -> [UInt8] {
        let values = hrpExpand(hrp) + data + [0, 0, 0, 0, 0, 0]
        let polymodValue = polymod(values) ^ bech32Const
        var checksum = [UInt8]()
        checksum.reserveCapacity(6)

        for i in 0..<6 {
            checksum.append(UInt8((polymodValue >> (5 * (5 - i))) & 31))
        }

        return checksum
    }

    /// Verify the Bech32 checksum of the given HRP and data.
    ///
    /// - Parameters:
    ///   - hrp: The human-readable part.
    ///   - data: The full data including the 6-byte checksum.
    /// - Returns: `true` if the checksum is valid.
    static func verifyChecksum(hrp: String, data: [UInt8]) -> Bool {
        let values = hrpExpand(hrp) + data
        return polymod(values) == bech32Const
    }

    // MARK: - Polymod

    /// Compute the Bech32 polymod checksum value.
    ///
    /// This implements the BCH error-detecting code used by Bech32.
    ///
    /// - Parameter values: The combined HRP expansion and data values.
    /// - Returns: The 30-bit polymod checksum value.
    static func polymod(_ values: [UInt8]) -> UInt32 {
        var checksum: UInt32 = 1

        for value in values {
            let top = checksum >> 25
            checksum = ((checksum & 0x1ffffff) << 5) ^ UInt32(value)

            for i in 0..<5 {
                if (top >> i) & 1 == 1 {
                    checksum ^= generator[i]
                }
            }
        }

        return checksum
    }

    // MARK: - HRP Expansion

    /// Expand the human-readable part for checksum computation.
    ///
    /// The HRP is expanded by taking each character's ASCII value,
    /// splitting it into high bits (>> 5) and low bits (& 31),
    /// separated by a zero byte.
    ///
    /// - Parameter hrp: The human-readable part string.
    /// - Returns: The expanded HRP values for polymod input.
    static func hrpExpand(_ hrp: String) -> [UInt8] {
        var result = [UInt8]()
        result.reserveCapacity(hrp.count * 2 + 1)

        for char in hrp.unicodeScalars {
            result.append(UInt8(char.value >> 5))
        }

        result.append(0)

        for char in hrp.unicodeScalars {
            result.append(UInt8(char.value & 31))
        }

        return result
    }

    // MARK: - SegWit Address Helpers

    /// Decode a SegWit address into its witness version and program.
    ///
    /// - Parameters:
    ///   - hrp: Expected human-readable part ("bc" or "tb").
    ///   - address: The Bech32-encoded SegWit address.
    /// - Returns: A tuple of (witnessVersion, witnessProgram).
    /// - Throws: `Bech32Error` if the address is invalid.
    static func decodeSegWitAddress(hrp: String, address: String) throws -> (version: UInt8, program: Data) {
        let decoded = try decode(address)

        guard decoded.hrp == hrp else {
            throw Bech32Error.invalidHRP
        }

        guard let witnessVersion = decoded.data.first else {
            throw Bech32Error.invalidDataLength
        }

        // witnessVersion already safely extracted via .first
        guard witnessVersion <= 16 else {
            throw Bech32Error.invalidWitnessVersion
        }

        let programData = try convertBits(
            data: Array(decoded.data.dropFirst()),
            fromBits: 5,
            toBits: 8,
            pad: false
        )

        // Witness version 0 requires exactly 20 or 32 bytes
        if witnessVersion == 0 {
            guard programData.count == 20 || programData.count == 32 else {
                throw Bech32Error.invalidDataLength
            }
        }

        // General witness program length: 2-40 bytes
        guard programData.count >= 2, programData.count <= 40 else {
            throw Bech32Error.invalidDataLength
        }

        return (version: witnessVersion, program: Data(programData))
    }

    /// Encode a SegWit address from a witness version and program.
    ///
    /// Convenience method that handles the 8-to-5-bit conversion and
    /// prepends the witness version. This is compatible with the API
    /// that `HDWallet` expects.
    ///
    /// - Parameters:
    ///   - hrp: Human-readable part ("bc" for mainnet, "tb" for testnet).
    ///   - witnessVersion: Witness version (0 for SegWit, 1 for Taproot).
    ///   - witnessProgram: The witness program data (20 or 32 bytes).
    /// - Returns: The Bech32-encoded address string, or nil if parameters are invalid.
    static func encodeAddress(hrp: String, witnessVersion: UInt8, witnessProgram: Data) -> String? {
        guard witnessProgram.count >= 2, witnessProgram.count <= 40 else { return nil }
        guard witnessVersion <= 16 else { return nil }

        if witnessVersion == 0 {
            guard witnessProgram.count == 20 || witnessProgram.count == 32 else { return nil }
        }

        guard let converted = try? convertBits(
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
