// MARK: - AddressGenerator.swift
// Bitcoin AI Wallet
//
// Generates Bitcoin addresses from public keys.
// Supports Native SegWit (P2WPKH, bc1q...) and Taproot (P2TR, bc1p...).
//
// Dependencies:
// - Bech32.swift (BIP173 encoding for SegWit v0)
// - Bech32m.swift (BIP350 encoding for Taproot v1+)
// - CryptoKit (SHA256 only — RIPEMD160 is implemented from scratch below)
//
// References:
// - BIP141: SegWit witness program definition
// - BIP173: Bech32 address format
// - BIP340: Schnorr signatures / x-only public keys
// - BIP341: Taproot output key tweaking
// - BIP350: Bech32m address format
//
// Platform: iOS 17.0+
// Framework: Foundation, CryptoKit (zero external dependencies)

import Foundation
import CryptoKit

// MARK: - AddressGenerator

/// Generates Bitcoin addresses from compressed public keys.
///
/// Supports two modern address types:
/// - **P2WPKH (Native SegWit)**: `bc1q...` addresses using BIP173 Bech32 encoding.
///   Witness program = RIPEMD160(SHA256(compressedPubKey)), 20 bytes.
/// - **P2TR (Taproot)**: `bc1p...` addresses using BIP350 Bech32m encoding.
///   Witness program = tweaked x-only public key, 32 bytes.
struct AddressGenerator {

    // MARK: - Errors

    /// Errors that can occur during address generation.
    enum AddressError: Error, LocalizedError {
        case invalidPublicKey
        case encodingFailed
        case unsupportedType
        case invalidKeyLength
        case tweakFailed

        var errorDescription: String? {
            switch self {
            case .invalidPublicKey:
                return "The provided public key is not a valid compressed public key"
            case .encodingFailed:
                return "Failed to encode the address"
            case .unsupportedType:
                return "The requested address type is not supported"
            case .invalidKeyLength:
                return "Public key must be exactly 33 bytes (compressed)"
            case .tweakFailed:
                return "Failed to compute Taproot key tweak"
            }
        }
    }

    // MARK: - Network

    /// Bitcoin network selection for address generation.
    enum Network {
        /// Bitcoin mainnet — addresses use HRP "bc".
        case mainnet
        /// Bitcoin testnet — addresses use HRP "tb".
        case testnet

        /// The human-readable part for Bech32/Bech32m encoding.
        var hrp: String {
            switch self {
            case .mainnet: return "bc"
            case .testnet: return "tb"
            }
        }
    }

    // MARK: - SegWit Address (P2WPKH)

    /// Generate a Native SegWit (P2WPKH) address from a compressed public key.
    ///
    /// Creates a `bc1q...` address (witness version 0, 20-byte witness program).
    /// The witness program is computed as Hash160 = RIPEMD160(SHA256(pubkey)).
    ///
    /// - Parameters:
    ///   - publicKey: A 33-byte compressed public key (02/03 prefix).
    ///   - network: The target network (default: mainnet).
    /// - Returns: A Bech32-encoded SegWit address string.
    /// - Throws: `AddressError` if the key is invalid, or `Bech32Error` on encoding failure.
    static func generateSegWitAddress(publicKey: Data, network: Network = .mainnet) throws -> String {
        guard publicKey.count == 33 else {
            throw AddressError.invalidKeyLength
        }

        // Validate compressed public key prefix (0x02 or 0x03)
        let prefix = publicKey[publicKey.startIndex]
        guard prefix == 0x02 || prefix == 0x03 else {
            throw AddressError.invalidPublicKey
        }

        // Step 1: SHA-256 hash of the public key
        let sha256Hash = SHA256.hash(data: publicKey)

        // Step 2: RIPEMD-160 hash of the SHA-256 result (Hash160)
        let hash160 = RIPEMD160.hash(Data(sha256Hash))

        // Step 3: Build witness program
        //   - Witness version 0 (single byte)
        //   - Followed by the 20-byte hash converted to 5-bit groups
        var data: [UInt8] = [0x00] // witness version 0
        let converted = try Bech32Coder.convertBits(
            data: Array(hash160),
            fromBits: 8,
            toBits: 5,
            pad: true
        )
        data.append(contentsOf: converted)

        // Step 4: Bech32 encode (BIP173 for witness version 0)
        return try Bech32Coder.encode(hrp: network.hrp, data: data)
    }

    // MARK: - Taproot Address (P2TR)

    /// Generate a Taproot (P2TR) address from a compressed public key.
    ///
    /// Creates a `bc1p...` address (witness version 1, 32-byte witness program).
    /// The witness program is the tweaked x-only public key per BIP341.
    ///
    /// For key-path-only spending (no script tree), the tweak is computed as:
    /// `t = tagged_hash("TapTweak", internal_key)`
    /// and the output key is `P + t*G` (point addition on secp256k1).
    ///
    /// - Parameters:
    ///   - publicKey: A 33-byte compressed public key (02/03 prefix).
    ///   - network: The target network (default: mainnet).
    /// - Returns: A Bech32m-encoded Taproot address string.
    /// - Throws: `AddressError` if the key is invalid, or `Bech32Error` on encoding failure.
    static func generateTaprootAddress(publicKey: Data, network: Network = .mainnet) throws -> String {
        guard publicKey.count == 33 else {
            throw AddressError.invalidKeyLength
        }

        // Validate compressed public key prefix (0x02 or 0x03)
        let prefix = publicKey[publicKey.startIndex]
        guard prefix == 0x02 || prefix == 0x03 else {
            throw AddressError.invalidPublicKey
        }

        // Step 1: Extract the x-only public key (drop the 1-byte prefix)
        let xOnlyKey = Data(publicKey.dropFirst())
        guard xOnlyKey.count == 32 else {
            throw AddressError.invalidPublicKey
        }

        // Step 2: Compute the taproot tweaked output key
        let tweakedKey = try computeTaprootTweak(xOnlyKey: xOnlyKey)

        // Step 3: Build witness program
        //   - Witness version 1 (single byte)
        //   - Followed by the 32-byte tweaked key converted to 5-bit groups
        var data: [UInt8] = [0x01] // witness version 1
        let converted = try Bech32Coder.convertBits(
            data: Array(tweakedKey),
            fromBits: 8,
            toBits: 5,
            pad: true
        )
        data.append(contentsOf: converted)

        // Step 4: Bech32m encode (BIP350 for witness version >= 1)
        return try Bech32mCoder.encode(hrp: network.hrp, data: data)
    }

    // MARK: - Taproot Tweak

    /// Compute the Taproot output key from an internal (x-only) public key.
    ///
    /// Per BIP341, for key-path-only spending (no script tree):
    /// 1. Compute `t = tagged_hash("TapTweak", internal_key)` -- the tweak scalar.
    /// 2. The output key is `internal_key + t * G` (EC point addition).
    ///
    /// - Parameter xOnlyKey: The 32-byte x-only internal public key.
    /// - Returns: The 32-byte tweaked output key (x-coordinate of Q).
    /// - Throws: `AddressError.tweakFailed` if the tweak computation fails.
    private static func computeTaprootTweak(xOnlyKey: Data) throws -> Data {
        // Compute the tweak: t = tagged_hash("TapTweak", xOnlyKey)
        let tweak = taggedHash(tag: "TapTweak", data: xOnlyKey)

        // Validate that the tweak is within the secp256k1 scalar field order
        let order = TaprootCurve.scalarOrder
        let tweakScalar = TaprootCurve.bytesToBigInt(Array(tweak))

        guard TaprootCurve.compare(tweakScalar, order) < 0,
              !TaprootCurve.isZero(tweakScalar) else {
            throw AddressError.tweakFailed
        }

        // Lift the x-only key to a curve point with even y-coordinate
        guard let internalPoint = TaprootCurve.liftX(Array(xOnlyKey)) else {
            throw AddressError.tweakFailed
        }

        // Compute t * G
        let tG = TaprootCurve.scalarMultiplyBase(tweakScalar)

        // Compute Q = P + t*G
        guard let outputPoint = TaprootCurve.pointAdd(internalPoint, tG) else {
            throw AddressError.tweakFailed
        }

        // Return the x-coordinate of Q as the output key (32 bytes)
        return Data(TaprootCurve.bigIntToBytes(outputPoint.x, length: 32))
    }

    // MARK: - Tagged Hash

    /// Compute a BIP340 tagged hash.
    ///
    /// `tagged_hash(tag, msg) = SHA256(SHA256(tag) || SHA256(tag) || msg)`
    ///
    /// The tag hash is computed once and concatenated twice before the message,
    /// providing domain separation between different uses of SHA256 in the
    /// Bitcoin protocol.
    ///
    /// - Parameters:
    ///   - tag: The tag string (e.g., "TapTweak", "TapLeaf").
    ///   - data: The message data to hash.
    /// - Returns: The 32-byte tagged hash.
    static func taggedHash(tag: String, data: Data) -> Data {
        let tagHash = Data(SHA256.hash(data: Data(tag.utf8)))
        var input = Data()
        input.reserveCapacity(tagHash.count * 2 + data.count)
        input.append(tagHash)
        input.append(tagHash)
        input.append(data)
        return Data(SHA256.hash(data: input))
    }

    // MARK: - Address Validation

    /// Validate a Bitcoin address by attempting to decode it.
    ///
    /// Checks both Bech32 (SegWit v0) and Bech32m (Taproot v1+) encodings.
    /// Also performs basic structural checks for legacy address formats.
    ///
    /// - Parameter address: The Bitcoin address string to validate.
    /// - Returns: `true` if the address is structurally valid.
    static func validate(address: String) -> Bool {
        let lowercased = address.lowercased()

        // Bech32/Bech32m addresses
        if lowercased.hasPrefix("bc1") || lowercased.hasPrefix("tb1") {
            let hrp = lowercased.hasPrefix("bc1") ? "bc" : "tb"

            // Try Bech32 first (witness version 0)
            if let decoded = try? Bech32Coder.decodeSegWitAddress(hrp: hrp, address: address) {
                return decoded.version == 0
            }

            // Try Bech32m (witness version 1+)
            if let decoded = try? Bech32mCoder.decodeSegWitAddress(hrp: hrp, address: address) {
                return decoded.version >= 1
            }

            return false
        }

        // Legacy addresses -- basic structural check
        if let type = ScriptType.from(address: address) {
            switch type {
            case .p2pkh:
                return address.count >= 25 && address.count <= 34
            case .p2sh:
                return address.count >= 25 && address.count <= 34
            default:
                return false
            }
        }

        return false
    }

    // MARK: - Address Type Detection

    /// Determine the script type of a Bitcoin address.
    ///
    /// Uses prefix analysis and, for Bech32/Bech32m addresses, attempts
    /// full decoding to verify the witness version.
    ///
    /// - Parameter address: The Bitcoin address string.
    /// - Returns: The `ScriptType` if recognized, or `nil` for unknown formats.
    static func addressType(_ address: String) -> ScriptType? {
        return ScriptType.from(address: address)
    }
}

// MARK: - RIPEMD160

/// Pure-Swift implementation of the RIPEMD-160 hash function.
///
/// RIPEMD-160 produces a 160-bit (20-byte) hash digest. It is used in Bitcoin
/// for the Hash160 operation: `Hash160(x) = RIPEMD160(SHA256(x))`, which
/// derives the 20-byte public key hash used in P2PKH and P2WPKH addresses.
///
/// CryptoKit does not provide RIPEMD-160, so this is a complete from-scratch
/// implementation following the original specification by Hans Dobbertin,
/// Antoon Bosselaers, and Bart Preneel (1996).
///
/// Reference: https://homes.esat.kuleuven.be/~bosselaers/ripemd160.html
struct RIPEMD160 {

    // MARK: - Public API

    /// Compute the RIPEMD-160 hash of the input data.
    ///
    /// - Parameter data: The input data to hash.
    /// - Returns: A 20-byte `Data` containing the RIPEMD-160 digest.
    static func hash(_ data: Data) -> Data {
        var message = Array(data)

        // Step 1: Pad the message
        let originalLength = UInt64(message.count) * 8
        message.append(0x80)

        // Append zeros until message length is 56 mod 64
        while message.count % 64 != 56 {
            message.append(0x00)
        }

        // Append original length in bits as 64-bit little-endian
        for i in 0..<8 {
            message.append(UInt8((originalLength >> (i * 8)) & 0xff))
        }

        // Step 2: Initialize hash values
        var h0: UInt32 = 0x67452301
        var h1: UInt32 = 0xefcdab89
        var h2: UInt32 = 0x98badcfe
        var h3: UInt32 = 0x10325476
        var h4: UInt32 = 0xc3d2e1f0

        // Step 3: Process each 512-bit (64-byte) block
        let blockCount = message.count / 64
        for blockIndex in 0..<blockCount {
            let blockStart = blockIndex * 64

            // Parse block into 16 32-bit little-endian words
            var x = [UInt32](repeating: 0, count: 16)
            for i in 0..<16 {
                let offset = blockStart + i * 4
                x[i] = UInt32(message[offset])
                    | (UInt32(message[offset + 1]) << 8)
                    | (UInt32(message[offset + 2]) << 16)
                    | (UInt32(message[offset + 3]) << 24)
            }

            // Initialize working variables
            var al = h0, bl = h1, cl = h2, dl = h3, el = h4  // Left round
            var ar = h0, br = h1, cr = h2, dr = h3, er = h4  // Right round

            // Left rounds
            for j in 0..<80 {
                var f: UInt32
                var k: UInt32

                switch j {
                case 0..<16:
                    f = bl ^ cl ^ dl
                    k = 0x00000000
                case 16..<32:
                    f = (bl & cl) | (~bl & dl)
                    k = 0x5a827999
                case 32..<48:
                    f = (bl | ~cl) ^ dl
                    k = 0x6ed9eba1
                case 48..<64:
                    f = (bl & dl) | (cl & ~dl)
                    k = 0x8f1bbcdc
                default: // 64..<80
                    f = bl ^ (cl | ~dl)
                    k = 0xa953fd4e
                }

                let t = al &+ f &+ x[Int(rl[j])] &+ k
                let rotated = rotateLeft(t, by: Int(sl[j]))
                let temp = rotated &+ el
                al = el
                el = dl
                dl = rotateLeft(cl, by: 10)
                cl = bl
                bl = temp
            }

            // Right rounds
            for j in 0..<80 {
                var f: UInt32
                var k: UInt32

                switch j {
                case 0..<16:
                    f = br ^ (cr | ~dr)
                    k = 0x50a28be6
                case 16..<32:
                    f = (br & dr) | (cr & ~dr)
                    k = 0x5c4dd124
                case 32..<48:
                    f = (br | ~cr) ^ dr
                    k = 0x6d703ef3
                case 48..<64:
                    f = (br & cr) | (~br & dr)
                    k = 0x7a6d76e9
                default: // 64..<80
                    f = br ^ cr ^ dr
                    k = 0x00000000
                }

                let t = ar &+ f &+ x[Int(rr[j])] &+ k
                let rotated = rotateLeft(t, by: Int(sr[j]))
                let temp = rotated &+ er
                ar = er
                er = dr
                dr = rotateLeft(cr, by: 10)
                cr = br
                br = temp
            }

            // Final addition
            let t = h1 &+ cl &+ dr
            h1 = h2 &+ dl &+ er
            h2 = h3 &+ el &+ ar
            h3 = h4 &+ al &+ br
            h4 = h0 &+ bl &+ cr
            h0 = t
        }

        // Step 4: Produce the final hash value (little-endian)
        var result = Data(count: 20)
        result[0]  = UInt8(h0 & 0xff)
        result[1]  = UInt8((h0 >> 8) & 0xff)
        result[2]  = UInt8((h0 >> 16) & 0xff)
        result[3]  = UInt8((h0 >> 24) & 0xff)
        result[4]  = UInt8(h1 & 0xff)
        result[5]  = UInt8((h1 >> 8) & 0xff)
        result[6]  = UInt8((h1 >> 16) & 0xff)
        result[7]  = UInt8((h1 >> 24) & 0xff)
        result[8]  = UInt8(h2 & 0xff)
        result[9]  = UInt8((h2 >> 8) & 0xff)
        result[10] = UInt8((h2 >> 16) & 0xff)
        result[11] = UInt8((h2 >> 24) & 0xff)
        result[12] = UInt8(h3 & 0xff)
        result[13] = UInt8((h3 >> 8) & 0xff)
        result[14] = UInt8((h3 >> 16) & 0xff)
        result[15] = UInt8((h3 >> 24) & 0xff)
        result[16] = UInt8(h4 & 0xff)
        result[17] = UInt8((h4 >> 8) & 0xff)
        result[18] = UInt8((h4 >> 16) & 0xff)
        result[19] = UInt8((h4 >> 24) & 0xff)

        return result
    }

    // MARK: - Convenience

    /// Compute Hash160: RIPEMD160(SHA256(data)).
    ///
    /// This is the standard Bitcoin public key hash used in P2PKH and P2WPKH.
    ///
    /// - Parameter data: The input data (typically a compressed public key).
    /// - Returns: A 20-byte `Data` containing the Hash160 digest.
    static func hash160(_ data: Data) -> Data {
        let sha256 = SHA256.hash(data: data)
        return hash(Data(sha256))
    }

    // MARK: - Internal Helpers

    /// Left-rotate a 32-bit value by the specified number of bits.
    private static func rotateLeft(_ value: UInt32, by bits: Int) -> UInt32 {
        return (value << bits) | (value >> (32 - bits))
    }

    // MARK: - Round Constants

    /// Message word selection for left rounds (indices into the 16-word block).
    private static let rl: [Int] = [
        // Round 1
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
        // Round 2
        7, 4, 13, 1, 10, 6, 15, 3, 12, 0, 9, 5, 2, 14, 11, 8,
        // Round 3
        3, 10, 14, 4, 9, 15, 8, 1, 2, 7, 0, 6, 13, 11, 5, 12,
        // Round 4
        1, 9, 11, 10, 0, 8, 12, 4, 13, 3, 7, 15, 14, 5, 6, 2,
        // Round 5
        4, 0, 5, 9, 7, 12, 2, 10, 14, 1, 3, 8, 11, 6, 15, 13
    ]

    /// Message word selection for right rounds.
    private static let rr: [Int] = [
        // Round 1
        5, 14, 7, 0, 9, 2, 11, 4, 13, 6, 15, 8, 1, 10, 3, 12,
        // Round 2
        6, 11, 3, 7, 0, 13, 5, 10, 14, 15, 8, 12, 4, 9, 1, 2,
        // Round 3
        15, 5, 1, 3, 7, 14, 6, 9, 11, 8, 12, 2, 10, 0, 4, 13,
        // Round 4
        8, 6, 4, 1, 3, 11, 15, 0, 5, 12, 2, 13, 9, 7, 10, 14,
        // Round 5
        12, 15, 10, 4, 1, 5, 8, 7, 6, 2, 13, 14, 0, 3, 9, 11
    ]

    /// Left rotation amounts for left rounds.
    private static let sl: [Int] = [
        // Round 1
        11, 14, 15, 12, 5, 8, 7, 9, 11, 13, 14, 15, 6, 7, 9, 8,
        // Round 2
        7, 6, 8, 13, 11, 9, 7, 15, 7, 12, 15, 9, 11, 7, 13, 12,
        // Round 3
        11, 13, 6, 7, 14, 9, 13, 15, 14, 8, 13, 6, 5, 12, 7, 5,
        // Round 4
        11, 12, 14, 15, 14, 15, 9, 8, 9, 14, 5, 6, 8, 6, 5, 12,
        // Round 5
        9, 15, 5, 11, 6, 8, 13, 12, 5, 12, 13, 14, 11, 8, 5, 6
    ]

    /// Left rotation amounts for right rounds.
    private static let sr: [Int] = [
        // Round 1
        8, 9, 9, 11, 13, 15, 15, 5, 7, 7, 8, 11, 14, 14, 12, 6,
        // Round 2
        9, 13, 15, 7, 12, 8, 9, 11, 7, 7, 12, 7, 6, 15, 13, 11,
        // Round 3
        9, 7, 15, 11, 8, 6, 6, 14, 12, 13, 5, 14, 13, 13, 7, 5,
        // Round 4
        15, 5, 8, 11, 14, 14, 6, 14, 6, 9, 12, 9, 12, 5, 15, 8,
        // Round 5
        8, 5, 12, 9, 12, 5, 14, 6, 8, 13, 6, 5, 15, 13, 11, 11
    ]
}

// MARK: - TaprootCurve (secp256k1 Arithmetic)

/// Minimal secp256k1 elliptic curve arithmetic for Taproot key tweaking.
///
/// This is a file-private implementation that provides just enough EC math
/// to compute `P + t*G` where P is the internal public key, t is the tweak
/// scalar, and G is the generator point. This avoids any external dependency
/// on libsecp256k1.
///
/// Named `TaprootCurve` to avoid collision with the `Secp256k1` enum in
/// `KeyDerivation.swift` (which uses UInt64 limbs and Jacobian coordinates).
/// This implementation uses UInt32 limbs and affine coordinates, optimized
/// for the single operation needed: Taproot output key tweaking.
///
/// The secp256k1 curve is defined by: `y^2 = x^3 + 7` over `F_p` where
/// `p = 2^256 - 2^32 - 977`.
///
/// All arithmetic uses arrays of `UInt32` to represent 256-bit integers,
/// stored in big-endian limb order (most significant limb first, 8 limbs).
private enum TaprootCurve {

    // MARK: - Types

    /// A point on the secp256k1 curve in affine coordinates.
    struct Point {
        let x: [UInt32]   // 8 limbs, big-endian
        let y: [UInt32]   // 8 limbs, big-endian
        let isInfinity: Bool

        static let infinity = Point(
            x: [UInt32](repeating: 0, count: 8),
            y: [UInt32](repeating: 0, count: 8),
            isInfinity: true
        )
    }

    // MARK: - Constants

    /// The prime field modulus p = 2^256 - 2^32 - 977
    static let fieldPrime: [UInt32] = [
        0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF,
        0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFE, 0xFFFFFC2F
    ]

    /// The order of the generator point G (scalar field order).
    /// n = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
    static let scalarOrder: [UInt32] = [
        0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFE,
        0xBAAEDCE6, 0xAF48A03B, 0xBFD25E8C, 0xD0364141
    ]

    /// Generator point G (x-coordinate)
    static let gx: [UInt32] = [
        0x79BE667E, 0xF9DCBBAC, 0x55A06295, 0xCE870B07,
        0x029BFCDB, 0x2DCE28D9, 0x59F2815B, 0x16F81798
    ]

    /// Generator point G (y-coordinate)
    static let gy: [UInt32] = [
        0x483ADA77, 0x26A3C465, 0x5DA4FBFC, 0x0E1108A8,
        0xFD17B448, 0xA6855419, 0x9C47D08F, 0xFB10D4B8
    ]

    /// The generator point G.
    static let generatorPoint = Point(x: gx, y: gy, isInfinity: false)

    // MARK: - BigInt Conversion

    /// Convert a byte array to a big-endian 8-limb UInt32 array.
    static func bytesToBigInt(_ bytes: [UInt8]) -> [UInt32] {
        var result = [UInt32](repeating: 0, count: 8)
        let padded: [UInt8]
        if bytes.count < 32 {
            padded = [UInt8](repeating: 0, count: 32 - bytes.count) + bytes
        } else if bytes.count > 32 {
            padded = Array(bytes.suffix(32))
        } else {
            padded = bytes
        }

        for i in 0..<8 {
            let offset = i * 4
            result[i] = (UInt32(padded[offset]) << 24)
                | (UInt32(padded[offset + 1]) << 16)
                | (UInt32(padded[offset + 2]) << 8)
                | UInt32(padded[offset + 3])
        }
        return result
    }

    /// Convert an 8-limb UInt32 array to a byte array.
    static func bigIntToBytes(_ value: [UInt32], length: Int = 32) -> [UInt8] {
        var result = [UInt8]()
        result.reserveCapacity(32)
        for limb in value {
            result.append(UInt8((limb >> 24) & 0xff))
            result.append(UInt8((limb >> 16) & 0xff))
            result.append(UInt8((limb >> 8) & 0xff))
            result.append(UInt8(limb & 0xff))
        }
        if result.count > length {
            return Array(result.suffix(length))
        }
        while result.count < length {
            result.insert(0, at: 0)
        }
        return result
    }

    // MARK: - Comparison

    /// Compare two big integers: returns -1, 0, or 1.
    static func compare(_ a: [UInt32], _ b: [UInt32]) -> Int {
        for i in 0..<8 {
            if a[i] < b[i] { return -1 }
            if a[i] > b[i] { return 1 }
        }
        return 0
    }

    /// Check if a big integer is zero.
    static func isZero(_ a: [UInt32]) -> Bool {
        return a.allSatisfy { $0 == 0 }
    }

    // MARK: - Modular Arithmetic (mod p)

    /// Add two 256-bit numbers modulo p.
    static func modAdd(_ a: [UInt32], _ b: [UInt32], mod p: [UInt32]) -> [UInt32] {
        var result = [UInt32](repeating: 0, count: 8)
        var carry: UInt64 = 0

        for i in stride(from: 7, through: 0, by: -1) {
            let sum = UInt64(a[i]) + UInt64(b[i]) + carry
            result[i] = UInt32(sum & 0xFFFFFFFF)
            carry = sum >> 32
        }

        if carry > 0 || compare(result, p) >= 0 {
            result = rawSubtract(result, p)
        }

        return result
    }

    /// Subtract two 256-bit numbers modulo p.
    static func modSub(_ a: [UInt32], _ b: [UInt32], mod p: [UInt32]) -> [UInt32] {
        if compare(a, b) >= 0 {
            return rawSubtract(a, b)
        } else {
            let bMinusA = rawSubtract(b, a)
            return rawSubtract(p, bMinusA)
        }
    }

    /// Raw subtraction a - b (assumes a >= b).
    private static func rawSubtract(_ a: [UInt32], _ b: [UInt32]) -> [UInt32] {
        var result = [UInt32](repeating: 0, count: 8)
        var borrow: Int64 = 0

        for i in stride(from: 7, through: 0, by: -1) {
            let diff = Int64(a[i]) - Int64(b[i]) - borrow
            if diff < 0 {
                result[i] = UInt32(diff + 0x100000000)
                borrow = 1
            } else {
                result[i] = UInt32(diff)
                borrow = 0
            }
        }

        return result
    }

    /// Multiply two 256-bit numbers modulo p.
    ///
    /// Uses 16-bit limbs internally to avoid overflow in UInt64 during
    /// schoolbook multiplication, then reduces using the secp256k1 identity
    /// `2^256 = 2^32 + 977 (mod p)`.
    static func modMul(_ a: [UInt32], _ b: [UInt32], mod p: [UInt32]) -> [UInt32] {
        let aLimbs = to16BitLimbs(a)
        let bLimbs = to16BitLimbs(b)

        var product = [UInt64](repeating: 0, count: 32)

        for i in 0..<16 {
            for j in 0..<16 {
                product[i + j] += UInt64(aLimbs[i]) * UInt64(bLimbs[j])
            }
        }

        // Propagate carries
        for i in 0..<31 {
            product[i + 1] += product[i] >> 16
            product[i] &= 0xFFFF
        }

        // Convert to bytes for reduction
        var productBytes = [UInt8](repeating: 0, count: 64)
        for i in 0..<32 {
            let limb = UInt16(product[31 - i] & 0xFFFF)
            productBytes[i * 2] = UInt8(limb >> 8)
            productBytes[i * 2 + 1] = UInt8(limb & 0xFF)
        }

        return barrettReduce(productBytes, mod: p)
    }

    /// Convert 8 x UInt32 (big-endian) to 16 x UInt16 (big-endian).
    private static func to16BitLimbs(_ a: [UInt32]) -> [UInt16] {
        var result = [UInt16](repeating: 0, count: 16)
        for i in 0..<8 {
            result[i * 2] = UInt16(a[i] >> 16)
            result[i * 2 + 1] = UInt16(a[i] & 0xFFFF)
        }
        return result
    }

    /// Reduce a 512-bit number modulo p.
    ///
    /// Uses the secp256k1 identity: `2^256 = 2^32 + 977 (mod p)`.
    /// Splits the 512-bit product into high and low 256-bit halves,
    /// then computes `low + high * (2^32 + 977) mod p`.
    private static func barrettReduce(_ bytes: [UInt8], mod p: [UInt32]) -> [UInt32] {
        let high = bytesToBigInt(Array(bytes[0..<32]))
        let low = bytesToBigInt(Array(bytes[32..<64]))

        let highShifted = shiftLeft32(high)
        let high977 = mul32(high, 977)

        var sum9 = [UInt64](repeating: 0, count: 9)
        for i in 0..<9 {
            sum9[i] = UInt64(highShifted[i]) + UInt64(high977[i])
        }

        for i in stride(from: 8, to: 0, by: -1) {
            sum9[i - 1] += sum9[i] >> 32
            sum9[i] &= 0xFFFFFFFF
        }

        var result = [UInt32](repeating: 0, count: 8)
        for i in 0..<8 {
            result[i] = UInt32(sum9[i + 1] & 0xFFFFFFFF)
        }

        result = modAdd(result, low, mod: p)

        var overflow = UInt64(sum9[0] & 0xFFFFFFFF)
        while overflow > 0 {
            let ov32 = overflow << 32
            let ov977 = overflow * 977
            let ovTotal = ov32 + ov977

            let ovHigh = UInt32((ovTotal >> 32) & 0xFFFFFFFF)
            let ovLow = UInt32(ovTotal & 0xFFFFFFFF)

            var carry: UInt64 = 0
            let s7 = UInt64(result[7]) + UInt64(ovLow) + carry
            result[7] = UInt32(s7 & 0xFFFFFFFF)
            carry = s7 >> 32

            let s6 = UInt64(result[6]) + UInt64(ovHigh) + carry
            result[6] = UInt32(s6 & 0xFFFFFFFF)
            carry = s6 >> 32

            var idx = 5
            while carry > 0 && idx >= 0 {
                let s = UInt64(result[idx]) + carry
                result[idx] = UInt32(s & 0xFFFFFFFF)
                carry = s >> 32
                idx -= 1
            }

            overflow = carry
        }

        while compare(result, p) >= 0 {
            result = rawSubtract(result, p)
        }

        return result
    }

    /// Shift a 256-bit number left by 32 bits, returning a 9-limb result.
    private static func shiftLeft32(_ a: [UInt32]) -> [UInt32] {
        var result = [UInt32](repeating: 0, count: 9)
        for i in 0..<8 {
            result[i] = a[i]
        }
        return result
    }

    /// Multiply a 256-bit number by a 32-bit value, returning a 9-limb result.
    private static func mul32(_ a: [UInt32], _ b: UInt32) -> [UInt32] {
        var result = [UInt32](repeating: 0, count: 9)
        var carry: UInt64 = 0
        let bVal = UInt64(b)

        for i in stride(from: 7, through: 0, by: -1) {
            let prod = UInt64(a[i]) * bVal + carry
            result[i + 1] = UInt32(prod & 0xFFFFFFFF)
            carry = prod >> 32
        }
        result[0] = UInt32(carry & 0xFFFFFFFF)

        return result
    }

    /// Modular multiplicative inverse using Fermat's little theorem:
    /// `a^(-1) = a^(p-2) mod p`
    static func modInverse(_ a: [UInt32], mod p: [UInt32]) -> [UInt32] {
        let pMinus2 = rawSubtract(p, [0, 0, 0, 0, 0, 0, 0, 2])
        return modPow(a, pMinus2, mod: p)
    }

    /// Modular exponentiation using square-and-multiply (LSB first).
    static func modPow(_ base: [UInt32], _ exp: [UInt32], mod p: [UInt32]) -> [UInt32] {
        var result: [UInt32] = [0, 0, 0, 0, 0, 0, 0, 1]
        var b = base

        // Process each bit from LSB to MSB
        for i in stride(from: 7, through: 0, by: -1) {
            for bit in 0..<32 {
                if (exp[i] >> bit) & 1 == 1 {
                    result = modMul(result, b, mod: p)
                }
                b = modMul(b, b, mod: p)
            }
        }

        return result
    }

    // MARK: - EC Point Operations

    /// Lift an x-only public key to a full point with even y-coordinate.
    ///
    /// Given x, compute `y = sqrt(x^3 + 7) mod p` and choose the even y.
    /// Returns nil if x is not a valid x-coordinate on the curve.
    static func liftX(_ xBytes: [UInt8]) -> Point? {
        let x = bytesToBigInt(xBytes)
        let p = fieldPrime

        guard compare(x, p) < 0 else { return nil }

        // c = x^3 + 7 mod p
        let x2 = modMul(x, x, mod: p)
        let x3 = modMul(x2, x, mod: p)
        let seven: [UInt32] = [0, 0, 0, 0, 0, 0, 0, 7]
        let c = modAdd(x3, seven, mod: p)

        // y = c^((p+1)/4) mod p  (valid since p = 3 mod 4)
        let pPlus1Over4 = computePPlus1Over4()
        let y = modPow(c, pPlus1Over4, mod: p)

        // Verify: y^2 mod p must equal c
        let y2 = modMul(y, y, mod: p)
        guard compare(y2, c) == 0 else { return nil }

        // Choose even y (last bit == 0)
        if (y[7] & 1) == 0 {
            return Point(x: x, y: y, isInfinity: false)
        } else {
            let yEven = rawSubtract(p, y)
            return Point(x: x, y: yEven, isInfinity: false)
        }
    }

    /// Precomputed (p + 1) / 4 for the secp256k1 field prime.
    private static func computePPlus1Over4() -> [UInt32] {
        // p + 1 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC30
        // (p + 1) / 4 = 0x3FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFBFFFFF0C
        return [
            0x3FFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF,
            0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xBFFFFF0C
        ]
    }

    /// Add two points on the secp256k1 curve (affine coordinates).
    static func pointAdd(_ p1: Point, _ p2: Point) -> Point? {
        let p = fieldPrime

        if p1.isInfinity { return p2 }
        if p2.isInfinity { return p1 }

        if compare(p1.x, p2.x) == 0 {
            if compare(p1.y, p2.y) == 0 {
                return pointDouble(p1)
            } else {
                return Point.infinity
            }
        }

        // lambda = (y2 - y1) / (x2 - x1) mod p
        let dy = modSub(p2.y, p1.y, mod: p)
        let dx = modSub(p2.x, p1.x, mod: p)
        let dxInv = modInverse(dx, mod: p)
        let lambda = modMul(dy, dxInv, mod: p)

        // x3 = lambda^2 - x1 - x2 mod p
        let lambda2 = modMul(lambda, lambda, mod: p)
        let x3temp = modSub(lambda2, p1.x, mod: p)
        let x3 = modSub(x3temp, p2.x, mod: p)

        // y3 = lambda * (x1 - x3) - y1 mod p
        let dx13 = modSub(p1.x, x3, mod: p)
        let y3temp = modMul(lambda, dx13, mod: p)
        let y3 = modSub(y3temp, p1.y, mod: p)

        return Point(x: x3, y: y3, isInfinity: false)
    }

    /// Double a point on the secp256k1 curve (a = 0).
    static func pointDouble(_ pt: Point) -> Point? {
        let p = fieldPrime

        if pt.isInfinity { return pt }

        // lambda = (3 * x^2) / (2 * y) mod p
        let x2 = modMul(pt.x, pt.x, mod: p)
        let three: [UInt32] = [0, 0, 0, 0, 0, 0, 0, 3]
        let numerator = modMul(three, x2, mod: p)

        let two: [UInt32] = [0, 0, 0, 0, 0, 0, 0, 2]
        let denominator = modMul(two, pt.y, mod: p)
        let denomInv = modInverse(denominator, mod: p)
        let lambda = modMul(numerator, denomInv, mod: p)

        // x3 = lambda^2 - 2*x mod p
        let lambda2 = modMul(lambda, lambda, mod: p)
        let twoX = modMul(two, pt.x, mod: p)
        let x3 = modSub(lambda2, twoX, mod: p)

        // y3 = lambda * (x - x3) - y mod p
        let dx = modSub(pt.x, x3, mod: p)
        let y3temp = modMul(lambda, dx, mod: p)
        let y3 = modSub(y3temp, pt.y, mod: p)

        return Point(x: x3, y: y3, isInfinity: false)
    }

    /// Scalar multiplication: compute k * G using double-and-add.
    static func scalarMultiplyBase(_ k: [UInt32]) -> Point {
        return scalarMultiply(k, generatorPoint)
    }

    /// Scalar multiplication: compute k * P using double-and-add (LSB first).
    static func scalarMultiply(_ k: [UInt32], _ point: Point) -> Point {
        var result = Point.infinity
        var current = point

        // Process each bit from LSB to MSB
        for i in stride(from: 7, through: 0, by: -1) {
            for bit in 0..<32 {
                if (k[i] >> bit) & 1 == 1 {
                    result = pointAdd(result, current) ?? Point.infinity
                }
                current = pointDouble(current) ?? Point.infinity
            }
        }

        return result
    }
}
