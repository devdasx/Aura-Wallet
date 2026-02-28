// MARK: - ScriptBuilder.swift
// Bitcoin AI Wallet
//
// Builds Bitcoin scripts (scriptPubKey, scriptSig, witness programs) and
// provides address decoding (Bech32/Bech32m/Base58Check) for extracting
// the hash program from an address string.
//
// All address decoding is implemented from scratch using only Foundation,
// with zero external dependencies.
//
// Platform: iOS 17.0+
// Framework: Foundation

import Foundation
import CryptoKit

// MARK: - ScriptBuilder

/// Builds Bitcoin locking scripts and decodes addresses to extract their
/// underlying hash programs.
struct ScriptBuilder {

    // MARK: - Opcodes

    /// Standard Bitcoin script opcodes used in locking/unlocking scripts.
    enum OpCode: UInt8 {
        case op0 = 0x00
        case opPushData1 = 0x4c
        case opPushData2 = 0x4d
        case op1 = 0x51
        case opDup = 0x76
        case opEqual = 0x87
        case opEqualVerify = 0x88
        case opHash160 = 0xa9
        case opCheckSig = 0xac
        case opCheckSigVerify = 0xad
    }

    // MARK: - ScriptPubKey Builders

    /// Build a P2WPKH scriptPubKey: OP_0 <20-byte-pubkey-hash>
    ///
    /// Format: [0x00] [0x14] [20-byte hash]
    /// - Parameter pubKeyHash: The 20-byte HASH160 of the compressed public key.
    /// - Returns: The 22-byte scriptPubKey.
    static func p2wpkhScriptPubKey(pubKeyHash: Data) -> Data {
        var script = Data()
        script.append(OpCode.op0.rawValue)         // OP_0 (witness version 0)
        script.append(0x14)                         // Push 20 bytes
        script.append(pubKeyHash)
        return script
    }

    /// Build a P2TR scriptPubKey: OP_1 <32-byte-tweaked-pubkey>
    ///
    /// Format: [0x51] [0x20] [32-byte x-only pubkey]
    /// - Parameter tweakedPubKey: The 32-byte x-only tweaked public key.
    /// - Returns: The 34-byte scriptPubKey.
    static func p2trScriptPubKey(tweakedPubKey: Data) -> Data {
        var script = Data()
        script.append(OpCode.op1.rawValue)          // OP_1 (witness version 1)
        script.append(0x20)                         // Push 32 bytes
        script.append(tweakedPubKey)
        return script
    }

    /// Build a P2PKH scriptPubKey:
    /// OP_DUP OP_HASH160 <20-byte-hash> OP_EQUALVERIFY OP_CHECKSIG
    ///
    /// - Parameter pubKeyHash: The 20-byte HASH160 of the public key.
    /// - Returns: The 25-byte scriptPubKey.
    static func p2pkhScriptPubKey(pubKeyHash: Data) -> Data {
        var script = Data()
        script.append(OpCode.opDup.rawValue)        // OP_DUP
        script.append(OpCode.opHash160.rawValue)    // OP_HASH160
        script.append(0x14)                         // Push 20 bytes
        script.append(pubKeyHash)
        script.append(OpCode.opEqualVerify.rawValue) // OP_EQUALVERIFY
        script.append(OpCode.opCheckSig.rawValue)   // OP_CHECKSIG
        return script
    }

    /// Build a P2SH scriptPubKey: OP_HASH160 <20-byte-script-hash> OP_EQUAL
    ///
    /// - Parameter scriptHash: The 20-byte HASH160 of the redeem script.
    /// - Returns: The 23-byte scriptPubKey.
    static func p2shScriptPubKey(scriptHash: Data) -> Data {
        var script = Data()
        script.append(OpCode.opHash160.rawValue)    // OP_HASH160
        script.append(0x14)                         // Push 20 bytes
        script.append(scriptHash)
        script.append(OpCode.opEqual.rawValue)      // OP_EQUAL
        return script
    }

    /// Create a scriptPubKey from a Bitcoin address string.
    ///
    /// Decodes the address, determines its type, and builds the appropriate
    /// locking script.
    ///
    /// Supported address types:
    /// - P2PKH (1...)       -> OP_DUP OP_HASH160 <hash> OP_EQUALVERIFY OP_CHECKSIG
    /// - P2SH  (3...)       -> OP_HASH160 <hash> OP_EQUAL
    /// - P2WPKH (bc1q...)   -> OP_0 <20-byte hash>
    /// - P2TR   (bc1p...)   -> OP_1 <32-byte key>
    ///
    /// - Parameter address: A valid Bitcoin address.
    /// - Returns: The corresponding scriptPubKey.
    /// - Throws: `TransactionError.invalidAddress` if the address cannot be decoded.
    static func scriptPubKey(for address: String) throws -> Data {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try Bech32/Bech32m first (bc1q... / bc1p... / tb1q... / tb1p...)
        let lowercased = trimmed.lowercased()
        if lowercased.hasPrefix("bc1") || lowercased.hasPrefix("tb1") {
            return try decodeBech32Address(lowercased)
        }

        // Try Base58Check (1... / 3... / m... / n... / 2...)
        if let firstChar = trimmed.first {
            switch firstChar {
            case "1", "m", "n":
                // P2PKH
                guard let decoded = Base58Check.decode(trimmed) else {
                    throw TransactionError.invalidAddress
                }
                // decoded = [version_byte (1)] [payload (20)] [checksum stripped]
                guard decoded.count == 21 else {
                    throw TransactionError.invalidAddress
                }
                let pubKeyHash = decoded.dropFirst(1) // Remove version byte
                return p2pkhScriptPubKey(pubKeyHash: Data(pubKeyHash))

            case "3", "2":
                // P2SH
                guard let decoded = Base58Check.decode(trimmed) else {
                    throw TransactionError.invalidAddress
                }
                guard decoded.count == 21 else {
                    throw TransactionError.invalidAddress
                }
                let scriptHash = decoded.dropFirst(1)
                return p2shScriptPubKey(scriptHash: Data(scriptHash))

            default:
                throw TransactionError.invalidAddress
            }
        }

        throw TransactionError.invalidAddress
    }

    // MARK: - Data Pushing

    /// Push data onto the script stack with the proper length prefix.
    ///
    /// Bitcoin script uses different opcodes for different data lengths:
    /// - 1-75 bytes:  single byte length prefix
    /// - 76-255 bytes: OP_PUSHDATA1 + 1-byte length
    /// - 256-65535 bytes: OP_PUSHDATA2 + 2-byte LE length
    ///
    /// - Parameter data: The data to push.
    /// - Returns: The push opcode(s) followed by the data.
    static func pushData(_ data: Data) -> Data {
        var result = Data()
        let length = data.count

        if length == 0 {
            result.append(OpCode.op0.rawValue)
        } else if length <= 75 {
            result.append(UInt8(length))
            result.append(data)
        } else if length <= 255 {
            result.append(OpCode.opPushData1.rawValue)
            result.append(UInt8(length))
            result.append(data)
        } else if length <= 65535 {
            result.append(OpCode.opPushData2.rawValue)
            var len = UInt16(length).littleEndian
            result.append(Data(bytes: &len, count: 2))
            result.append(data)
        }
        // Larger data pushes are not used in standard transactions

        return result
    }

    // MARK: - Bech32 Address Decoding

    /// Decode a Bech32 or Bech32m encoded Bitcoin address into its scriptPubKey.
    ///
    /// Uses the existing `Bech32Coder` (from Core/Wallet/Bech32.swift) for decoding.
    ///
    /// - Parameter address: A lowercase bech32/bech32m address.
    /// - Returns: The scriptPubKey for the decoded witness program.
    /// - Throws: `TransactionError.invalidAddress` on decode failure.
    private static func decodeBech32Address(_ address: String) throws -> Data {
        // Determine HRP from the address prefix
        let hrp: String
        if address.hasPrefix("bc1") {
            hrp = "bc"
        } else if address.hasPrefix("tb1") {
            hrp = "tb"
        } else {
            throw TransactionError.invalidAddress
        }

        // Decode using the existing Bech32Coder from Bech32.swift
        let decoded: (version: UInt8, program: Data)
        do {
            decoded = try Bech32Coder.decodeSegWitAddress(hrp: hrp, address: address)
        } catch {
            throw TransactionError.invalidAddress
        }

        let witnessVersion = Int(decoded.version)
        let program = decoded.program

        switch witnessVersion {
        case 0:
            // P2WPKH (20 bytes) or P2WSH (32 bytes)
            if program.count == 20 {
                return p2wpkhScriptPubKey(pubKeyHash: program)
            } else if program.count == 32 {
                // P2WSH: OP_0 <32-byte hash>
                var script = Data()
                script.append(OpCode.op0.rawValue)
                script.append(0x20)
                script.append(program)
                return script
            }
            throw TransactionError.invalidAddress

        case 1:
            // P2TR (32 bytes)
            guard program.count == 32 else {
                throw TransactionError.invalidAddress
            }
            return p2trScriptPubKey(tweakedPubKey: program)

        default:
            // Future witness versions (2-16)
            guard witnessVersion >= 2 && witnessVersion <= 16 else {
                throw TransactionError.invalidAddress
            }
            var script = Data()
            // OP_n = 0x50 + n (OP_1 = 0x51, OP_2 = 0x52, etc.)
            script.append(UInt8(0x50 + witnessVersion))
            script.append(UInt8(program.count))
            script.append(program)
            return script
        }
    }
}

// MARK: - Base58Check

/// Base58Check encoder/decoder for legacy Bitcoin addresses.
///
/// Implements the Base58Check encoding used by P2PKH and P2SH addresses.
/// Zero external dependencies; uses CryptoKit only for SHA-256.
struct Base58Check {

    /// The Base58 alphabet (excludes 0, O, I, l to avoid visual ambiguity).
    private static let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")

    /// Reverse lookup table: ASCII value -> Base58 digit value.
    private static let alphabetMap: [Character: UInt8] = {
        var map = [Character: UInt8]()
        for (i, char) in alphabet.enumerated() {
            map[char] = UInt8(i)
        }
        return map
    }()

    /// Decode a Base58Check-encoded string.
    ///
    /// Verifies the 4-byte checksum (double SHA-256 of payload).
    ///
    /// - Parameter string: The Base58Check-encoded string.
    /// - Returns: The decoded payload (version byte + data) without checksum,
    ///            or nil if decoding or checksum verification fails.
    static func decode(_ string: String) -> Data? {
        // Decode base58 to raw bytes
        guard let raw = decodeBase58(string) else {
            return nil
        }

        // Must have at least 4 bytes for checksum + 1 byte payload
        guard raw.count >= 5 else {
            return nil
        }

        // Split into payload and checksum
        let payload = raw.prefix(raw.count - 4)
        let checksum = raw.suffix(4)

        // Verify checksum: first 4 bytes of double SHA-256
        let hash = doubleSHA256(Data(payload))
        let expectedChecksum = hash.prefix(4)

        guard checksum.elementsEqual(expectedChecksum) else {
            return nil
        }

        return Data(payload)
    }

    /// Raw Base58 decoding (without checksum verification).
    ///
    /// - Parameter string: The Base58-encoded string.
    /// - Returns: The decoded bytes, or nil on invalid characters.
    private static func decodeBase58(_ string: String) -> Data? {
        // Count leading '1's (which represent leading zero bytes)
        var leadingZeros = 0
        for char in string {
            if char == "1" {
                leadingZeros += 1
            } else {
                break
            }
        }

        // Decode the rest using base-58 arithmetic
        // Maximum possible size: ceil(string.count * log(58) / log(256))
        let size = string.count * 733 / 1000 + 1
        var output = [UInt8](repeating: 0, count: size)

        for char in string {
            guard let value = alphabetMap[char] else {
                return nil // Invalid character
            }

            var carry = Int(value)
            var i = size - 1
            while i >= 0 {
                carry += 58 * Int(output[i])
                output[i] = UInt8(carry % 256)
                carry /= 256
                i -= 1
            }
        }

        // Skip leading zeros in the output
        var startIndex = 0
        while startIndex < output.count && output[startIndex] == 0 {
            startIndex += 1
        }

        // Build result: leading zero bytes + decoded bytes
        var result = Data(repeating: 0, count: leadingZeros)
        result.append(contentsOf: output[startIndex...])
        return result
    }

    /// Compute double SHA-256 hash.
    ///
    /// - Parameter data: Input data.
    /// - Returns: The 32-byte double SHA-256 hash.
    private static func doubleSHA256(_ data: Data) -> Data {
        let first = SHA256.hash(data: data)
        let second = SHA256.hash(data: Data(first))
        return Data(second)
    }
}
