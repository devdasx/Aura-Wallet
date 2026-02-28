// MARK: - ECDSASigner.swift
// Bitcoin AI Wallet
//
// ECDSA signing for SegWit (P2WPKH) Bitcoin transactions on the secp256k1 curve.
// Implements RFC 6979 deterministic nonce generation and BIP62 low-S enforcement.
// Zero external dependencies -- system frameworks only (CryptoKit for HMAC-SHA256).
//
// Platform: iOS 17.0+
// Frameworks: Foundation, CryptoKit

import Foundation
import CryptoKit

// MARK: - ECDSASigner

struct ECDSASigner {

    // MARK: - Errors

    enum ECDSAError: Error, LocalizedError {
        case invalidPrivateKey
        case invalidHash
        case signingFailed
        case invalidSignature
        case invalidPublicKey

        var errorDescription: String? {
            switch self {
            case .invalidPrivateKey: return "Invalid private key."
            case .invalidHash: return "Hash must be exactly 32 bytes."
            case .signingFailed: return "ECDSA signing failed."
            case .invalidSignature: return "Invalid ECDSA signature."
            case .invalidPublicKey: return "Invalid public key."
            }
        }
    }

    // MARK: - Sign

    /// Sign a 32-byte message hash with ECDSA using the given private key.
    ///
    /// Returns a DER-encoded signature with the sighash type byte appended.
    ///
    /// - Parameters:
    ///   - hash: 32-byte message hash (e.g., BIP143 sighash).
    ///   - privateKey: 32-byte secp256k1 private key.
    ///   - sigHashType: Sighash type byte (default `SIGHASH_ALL = 0x01`).
    /// - Returns: DER-encoded ECDSA signature with sighash byte appended.
    static func sign(hash: Data, privateKey: Data, sigHashType: UInt8 = 0x01) throws -> Data {
        guard hash.count == 32 else { throw ECDSAError.invalidHash }
        guard privateKey.count == 32, Secp256k1.isValidPrivateKey(privateKey) else {
            throw ECDSAError.invalidPrivateKey
        }

        let z = Secp256k1.toUInt64Array(hash)
        let d = Secp256k1.toUInt64Array(privateKey)
        let n = Secp256k1.n

        // Generate deterministic k via RFC 6979
        let kData = deterministicK(hash: hash, privateKey: privateKey)
        var k = Secp256k1.toUInt64Array(kData)

        // Ensure k is in [1, n-1]
        k = Secp256k1.reduceModN(k)
        guard !Secp256k1.isZero(k) else { throw ECDSAError.signingFailed }

        // R = k * G
        let R = Secp256k1.multiplyG(scalar: k)
        guard !R.isInfinity else { throw ECDSAError.signingFailed }

        // r = R.x mod n
        var r = Secp256k1.reduceModN(R.x)
        guard !Secp256k1.isZero(r) else { throw ECDSAError.signingFailed }

        // s = k^(-1) * (z + r * d) mod n
        let kInv = Secp256k1.modInverse(k, mod: n)
        let rd = Secp256k1.modMul(r, d, mod: n)
        let zPlusRd = Secp256k1.modAdd(z, rd, mod: n)
        var s = Secp256k1.modMul(kInv, zPlusRd, mod: n)
        guard !Secp256k1.isZero(s) else { throw ECDSAError.signingFailed }

        // BIP62: Enforce low-S. If s > n/2, replace with n - s.
        if Secp256k1.compare(s, Secp256k1.halfN) > 0 {
            s = Secp256k1.modSub(Secp256k1.zero, s, mod: n)
        }

        // DER encode (r, s) and append sighash type
        let rData = Secp256k1.toData(r)
        let sData = Secp256k1.toData(s)

        var der = derEncode(r: rData, s: sData)
        der.append(sigHashType)
        return der
    }

    // MARK: - RFC 6979 Deterministic k

    /// Generate a deterministic nonce k per RFC 6979 using HMAC-SHA256 as the DRBG.
    ///
    /// This ensures that the same (hash, privateKey) pair always produces the same k,
    /// eliminating the need for a cryptographic random number generator during signing
    /// and preventing catastrophic nonce reuse.
    ///
    /// - Parameters:
    ///   - hash: 32-byte message hash.
    ///   - privateKey: 32-byte private key.
    /// - Returns: 32-byte deterministic nonce.
    private static func deterministicK(hash: Data, privateKey: Data) -> Data {
        let n = Secp256k1.n

        // Step a: h1 = hash (already provided)
        // Convert hash to integer z, reduce mod n if needed
        var z = Secp256k1.toUInt64Array(hash)
        z = Secp256k1.reduceModN(z)
        let zBytes = Secp256k1.toData(z)

        // Step b: V = 0x01 * 32
        var v = Data(repeating: 0x01, count: 32)

        // Step c: K = 0x00 * 32
        var kMac = Data(repeating: 0x00, count: 32)

        // Step d: K = HMAC_K(V || 0x00 || privkey || z)
        kMac = hmacSHA256(key: kMac, data: v + Data([0x00]) + privateKey + zBytes)

        // Step e: V = HMAC_K(V)
        v = hmacSHA256(key: kMac, data: v)

        // Step f: K = HMAC_K(V || 0x01 || privkey || z)
        kMac = hmacSHA256(key: kMac, data: v + Data([0x01]) + privateKey + zBytes)

        // Step g: V = HMAC_K(V)
        v = hmacSHA256(key: kMac, data: v)

        // Step h: Loop until we get a valid k
        for _ in 0..<1000 {
            // h1: V = HMAC_K(V)
            v = hmacSHA256(key: kMac, data: v)

            // h2: k candidate = V (already 32 bytes = 256 bits)
            let candidate = Secp256k1.toUInt64Array(v)

            // h3: Check 1 <= k < n
            if !Secp256k1.isZero(candidate) && Secp256k1.compare(candidate, n) < 0 {
                return v
            }

            // k was invalid, update and retry
            kMac = hmacSHA256(key: kMac, data: v + Data([0x00]))
            v = hmacSHA256(key: kMac, data: v)
        }

        // Should never reach here with valid inputs
        return v
    }

    // MARK: - HMAC-SHA256

    /// Compute HMAC-SHA256.
    private static func hmacSHA256(key: Data, data: Data) -> Data {
        let symmetricKey = SymmetricKey(data: key)
        let mac = HMAC<SHA256>.authenticationCode(for: data, using: symmetricKey)
        return Data(mac)
    }

    // MARK: - DER Encoding

    /// DER-encode an ECDSA signature (r, s).
    ///
    /// DER format:
    /// ```
    /// 0x30 <total_length>
    ///   0x02 <r_length> <r_bytes>
    ///   0x02 <s_length> <s_bytes>
    /// ```
    ///
    /// Values are encoded as signed big-endian integers:
    /// - Leading zero bytes are stripped (except one if needed for sign bit).
    /// - A 0x00 byte is prepended if the high bit is set (to keep the integer positive).
    static func derEncode(r: Data, s: Data) -> Data {
        let rEncoded = derEncodeInteger(r)
        let sEncoded = derEncodeInteger(s)

        var der = Data()
        der.append(0x30) // SEQUENCE tag
        der.append(UInt8(rEncoded.count + sEncoded.count))
        der.append(rEncoded)
        der.append(sEncoded)
        return der
    }

    /// DER-encode a single integer value.
    private static func derEncodeInteger(_ value: Data) -> Data {
        // Strip leading zero bytes
        var trimmed = value
        while trimmed.count > 1 && trimmed[trimmed.startIndex] == 0x00 {
            trimmed = trimmed.dropFirst()
        }

        // Prepend 0x00 if high bit is set (to indicate positive number)
        if let first = trimmed.first, first & 0x80 != 0 {
            trimmed = Data([0x00]) + trimmed
        }

        var encoded = Data()
        encoded.append(0x02) // INTEGER tag
        encoded.append(UInt8(trimmed.count))
        encoded.append(trimmed)
        return encoded
    }

    // MARK: - Verify

    /// Verify an ECDSA signature against a message hash and public key.
    ///
    /// - Parameters:
    ///   - hash: 32-byte message hash.
    ///   - signature: DER-encoded signature (without sighash byte) or DER + sighash byte.
    ///   - publicKey: 33-byte compressed or 65-byte uncompressed public key.
    /// - Returns: `true` if the signature is valid.
    static func verify(hash: Data, signature: Data, publicKey: Data) -> Bool {
        guard hash.count == 32 else { return false }

        // Parse the public key
        guard let pubPoint = parsePublicKey(publicKey) else { return false }

        // Parse DER signature (strip trailing sighash byte if present)
        guard let (r, s) = parseDERSignature(signature) else { return false }

        let n = Secp256k1.n
        let rArr = Secp256k1.toUInt64Array(r)
        let sArr = Secp256k1.toUInt64Array(s)
        let z = Secp256k1.toUInt64Array(hash)

        // Check r, s in [1, n-1]
        guard !Secp256k1.isZero(rArr), Secp256k1.compare(rArr, n) < 0 else { return false }
        guard !Secp256k1.isZero(sArr), Secp256k1.compare(sArr, n) < 0 else { return false }

        // w = s^(-1) mod n
        let w = Secp256k1.modInverse(sArr, mod: n)

        // u1 = z * w mod n
        let u1 = Secp256k1.modMul(z, w, mod: n)

        // u2 = r * w mod n
        let u2 = Secp256k1.modMul(rArr, w, mod: n)

        // Point = u1*G + u2*Q
        let p1 = Secp256k1.multiplyG(scalar: u1)
        let p2 = Secp256k1.multiply(point: pubPoint, scalarArray: u2)
        let point = Secp256k1.add(p1, p2)

        guard !point.isInfinity else { return false }

        // Verify: point.x mod n == r
        let xModN = Secp256k1.reduceModN(point.x)
        return xModN == rArr
    }

    // MARK: - Parsing Helpers

    /// Parse a compressed (33-byte) or uncompressed (65-byte) public key into a curve point.
    static func parsePublicKey(_ data: Data) -> Secp256k1.Point? {
        if data.count == 33 {
            // Compressed: 0x02 or 0x03 prefix
            let prefix = data[data.startIndex]
            guard prefix == 0x02 || prefix == 0x03 else { return nil }
            let xData = Data(data[data.startIndex + 1 ..< data.startIndex + 33])
            let x = Secp256k1.toUInt64Array(xData)

            // Compute y from x: y^2 = x^3 + 7 mod p
            let p = Secp256k1.p
            let x2 = Secp256k1.modSqr(x, mod: p)
            let x3 = Secp256k1.modMul(x2, x, mod: p)
            let seven: [UInt64] = [0, 0, 0, 7]
            let rhs = Secp256k1.modAdd(x3, seven, mod: p)

            // y = rhs^((p+1)/4) mod p  (works because p = 3 mod 4)
            // (p+1)/4
            let pPlus1Div4 = Secp256k1.computePPlus1Div4()
            let y = Secp256k1.modExp(rhs, pPlus1Div4, mod: p)

            // Verify y^2 == rhs
            let ySquared = Secp256k1.modSqr(y, mod: p)
            guard ySquared == rhs else { return nil }

            // Choose the correct y based on prefix parity
            let yIsEven = y[3] & 1 == 0
            let wantEven = prefix == 0x02
            let finalY = yIsEven == wantEven ? y : Secp256k1.modSub(Secp256k1.zero, y, mod: p)

            return Secp256k1.Point(x: x, y: finalY)

        } else if data.count == 65 {
            // Uncompressed: 0x04 prefix
            guard data[data.startIndex] == 0x04 else { return nil }
            let xData = Data(data[data.startIndex + 1 ..< data.startIndex + 33])
            let yData = Data(data[data.startIndex + 33 ..< data.startIndex + 65])
            return Secp256k1.Point(x: Secp256k1.toUInt64Array(xData),
                                   y: Secp256k1.toUInt64Array(yData))
        }
        return nil
    }

    /// Parse a DER-encoded ECDSA signature into (r, s) components.
    /// Handles optional trailing sighash type byte.
    static func parseDERSignature(_ data: Data) -> (r: Data, s: Data)? {
        var bytes = [UInt8](data)
        guard bytes.count >= 8 else { return nil } // Minimum DER sig size

        // Check for SEQUENCE tag
        guard bytes[0] == 0x30 else { return nil }
        let totalLen = Int(bytes[1])

        // The actual DER data may be followed by a sighash byte
        // Total DER content should be at positions 2 ..< 2+totalLen
        guard bytes.count >= 2 + totalLen else { return nil }

        var offset = 2

        // Parse r
        guard offset < bytes.count, bytes[offset] == 0x02 else { return nil }
        offset += 1
        guard offset < bytes.count else { return nil }
        let rLen = Int(bytes[offset])
        offset += 1
        guard offset + rLen <= bytes.count else { return nil }
        var r = Data(bytes[offset..<offset + rLen])
        offset += rLen

        // Strip leading zero used for sign encoding
        while r.count > 1 && r[r.startIndex] == 0x00 {
            r = r.dropFirst()
        }
        // Pad to 32 bytes
        if r.count < 32 {
            r = Data(repeating: 0, count: 32 - r.count) + r
        }

        // Parse s
        guard offset < bytes.count, bytes[offset] == 0x02 else { return nil }
        offset += 1
        guard offset < bytes.count else { return nil }
        let sLen = Int(bytes[offset])
        offset += 1
        guard offset + sLen <= bytes.count else { return nil }
        var s = Data(bytes[offset..<offset + sLen])

        // Strip leading zero
        while s.count > 1 && s[s.startIndex] == 0x00 {
            s = s.dropFirst()
        }
        // Pad to 32 bytes
        if s.count < 32 {
            s = Data(repeating: 0, count: 32 - s.count) + s
        }

        return (r, s)
    }
}

// MARK: - Secp256k1 Extension for sqrt helper

extension Secp256k1 {
    /// Compute (p + 1) / 4 for modular square root (p = 3 mod 4).
    static func computePPlus1Div4() -> [UInt64] {
        // p + 1 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC30
        // (p + 1) / 4 = right shift by 2
        // p + 1:
        //   limb 0: 0xFFFFFFFFFFFFFFFF
        //   limb 1: 0xFFFFFFFFFFFFFFFF
        //   limb 2: 0xFFFFFFFFFFFFFFFF
        //   limb 3: 0xFFFFFFFEFFFFFC30
        // Divide by 4 (right shift by 2):
        //   limb 0: 0x3FFFFFFFFFFFFFFF
        //   limb 1: 0xFFFFFFFFFFFFFFFF
        //   limb 2: 0xFFFFFFFFFFFFFFFF
        //   limb 3: 0xFFFFFFFFBFFFFF0C
        return [
            0x3FFFFFFF_FFFFFFFF,
            0xFFFFFFFF_FFFFFFFF,
            0xFFFFFFFF_FFFFFFFF,
            0xFFFFFFFF_BFFFFF0C
        ]
    }
}
