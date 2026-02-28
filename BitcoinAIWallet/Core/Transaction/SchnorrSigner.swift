// MARK: - SchnorrSigner.swift
// Bitcoin AI Wallet
//
// BIP340 Schnorr signature implementation for Taproot (P2TR) transactions.
// Uses x-only public keys (32 bytes) and produces 64-byte signatures.
// Zero external dependencies -- system frameworks only (CryptoKit for SHA256).
//
// Reference: https://github.com/bitcoin/bips/blob/master/bip-0340.mediawiki
//
// Platform: iOS 17.0+
// Frameworks: Foundation, CryptoKit

import Foundation
import CryptoKit

// MARK: - SchnorrSigner

struct SchnorrSigner {

    // MARK: - Errors

    enum SchnorrError: Error, LocalizedError {
        case invalidPrivateKey
        case invalidHash
        case invalidNonce
        case signingFailed
        case invalidSignature
        case invalidPublicKey

        var errorDescription: String? {
            switch self {
            case .invalidPrivateKey: return "Invalid private key for Schnorr signing."
            case .invalidHash: return "Hash must be exactly 32 bytes."
            case .invalidNonce: return "Generated nonce is zero."
            case .signingFailed: return "Schnorr signing failed."
            case .invalidSignature: return "Invalid Schnorr signature."
            case .invalidPublicKey: return "Invalid x-only public key."
            }
        }
    }

    // MARK: - Sign (BIP340)

    /// Sign a 32-byte message hash with BIP340 Schnorr.
    ///
    /// Produces a 64-byte signature `(R.x || s)` where:
    /// - R is a curve point with even y-coordinate
    /// - s is a scalar such that `s*G = R + e*P`
    ///
    /// For `SIGHASH_DEFAULT` (0x00) in Taproot, no sighash byte is appended.
    /// For other sighash types, the caller appends the byte.
    ///
    /// - Parameters:
    ///   - hash: 32-byte message hash (BIP341 sighash).
    ///   - privateKey: 32-byte secp256k1 private key.
    /// - Returns: 64-byte Schnorr signature.
    static func sign(hash: Data, privateKey: Data) throws -> Data {
        guard hash.count == 32 else { throw SchnorrError.invalidHash }
        guard privateKey.count == 32, Secp256k1.isValidPrivateKey(privateKey) else {
            throw SchnorrError.invalidPrivateKey
        }

        let n = Secp256k1.n

        // Step 1: d' = int(privateKey)
        var dPrime = Secp256k1.toUInt64Array(privateKey)

        // Step 2: P = d' * G. If P has odd y, negate d' to get d.
        let P = Secp256k1.multiplyG(scalar: dPrime)
        guard !P.isInfinity else { throw SchnorrError.signingFailed }

        var d = dPrime
        if !Secp256k1.hasEvenY(P) {
            // d = n - d'
            d = Secp256k1.modSub(Secp256k1.zero, dPrime, mod: n)
        }

        let pBytes = Secp256k1.toData(P.x) // x-only public key (32 bytes)

        // Step 3: t = xor(bytes(d), tagged_hash("BIP0340/aux", rand))
        let auxRand = generateAuxRand()
        let auxHash = taggedHash(tag: "BIP0340/aux", data: auxRand)
        let dBytes = Secp256k1.toData(d)
        let t = xorBytes(dBytes, auxHash)

        // Step 4: rand = tagged_hash("BIP0340/nonce", t || bytes(P) || hash)
        let nonceInput = t + pBytes + hash
        let rand = taggedHash(tag: "BIP0340/nonce", data: nonceInput)

        // Step 5: k' = int(rand) mod n. Fail if k' = 0.
        var kPrime = Secp256k1.toUInt64Array(rand)
        kPrime = Secp256k1.reduceModN(kPrime)
        guard !Secp256k1.isZero(kPrime) else { throw SchnorrError.invalidNonce }

        // Step 6: R = k' * G. If R has odd y, negate k'.
        let R = Secp256k1.multiplyG(scalar: kPrime)
        guard !R.isInfinity else { throw SchnorrError.signingFailed }

        var k = kPrime
        if !Secp256k1.hasEvenY(R) {
            k = Secp256k1.modSub(Secp256k1.zero, kPrime, mod: n)
        }

        let rBytes = Secp256k1.toData(R.x)

        // Step 7: e = int(tagged_hash("BIP0340/challenge", bytes(R) || bytes(P) || hash)) mod n
        let challengeInput = rBytes + pBytes + hash
        let eHash = taggedHash(tag: "BIP0340/challenge", data: challengeInput)
        var e = Secp256k1.toUInt64Array(eHash)
        e = Secp256k1.reduceModN(e)

        // Step 8: sig = bytes(R) || bytes((k + e * d) mod n)
        let ed = Secp256k1.modMul(e, d, mod: n)
        let s = Secp256k1.modAdd(k, ed, mod: n)
        let sBytes = Secp256k1.toData(s)

        // Zero sensitive data
        dPrime = Secp256k1.zero
        d = Secp256k1.zero
        k = Secp256k1.zero
        kPrime = Secp256k1.zero
        _ = dPrime; _ = d; _ = k; _ = kPrime

        return rBytes + sBytes
    }

    // MARK: - Tagged Hash

    /// BIP340 tagged hash: `SHA256(SHA256(tag) || SHA256(tag) || msg)`.
    ///
    /// The double-hashed tag prefix acts as a domain separator, preventing
    /// collisions between different uses of SHA256 in the Bitcoin protocol.
    ///
    /// - Parameters:
    ///   - tag: The ASCII tag string (e.g., "BIP0340/challenge").
    ///   - data: The message data to hash.
    /// - Returns: 32-byte tagged hash.
    static func taggedHash(tag: String, data: Data) -> Data {
        let tagData = Data(tag.utf8)
        let tagHash = sha256(tagData)
        let preimage = tagHash + tagHash + data
        return sha256(preimage)
    }

    // MARK: - Verify

    /// Verify a BIP340 Schnorr signature.
    ///
    /// - Parameters:
    ///   - hash: 32-byte message hash.
    ///   - signature: 64-byte Schnorr signature `(R.x || s)`.
    ///   - publicKey: 32-byte x-only public key.
    /// - Returns: `true` if the signature is valid.
    static func verify(hash: Data, signature: Data, publicKey: Data) -> Bool {
        guard hash.count == 32 else { return false }
        guard signature.count == 64 else { return false }
        guard publicKey.count == 32 else { return false }

        let n = Secp256k1.n
        let p = Secp256k1.p

        // Parse signature
        let rBytes = Data(signature[signature.startIndex..<signature.startIndex + 32])
        let sBytes = Data(signature[signature.startIndex + 32..<signature.startIndex + 64])
        let r = Secp256k1.toUInt64Array(rBytes)
        let s = Secp256k1.toUInt64Array(sBytes)

        // Check r < p and s < n
        guard Secp256k1.compare(r, p) < 0 else { return false }
        guard Secp256k1.compare(s, n) < 0 else { return false }

        // Lift the x-only public key to a point (even y)
        guard let P = liftX(publicKey) else { return false }

        // e = int(tagged_hash("BIP0340/challenge", bytes(r) || bytes(P) || m)) mod n
        let challengeInput = rBytes + publicKey + hash
        let eHash = taggedHash(tag: "BIP0340/challenge", data: challengeInput)
        var e = Secp256k1.toUInt64Array(eHash)
        e = Secp256k1.reduceModN(e)

        // R = s*G - e*P
        let sG = Secp256k1.multiplyG(scalar: s)
        let eP = Secp256k1.multiply(point: P, scalarArray: e)
        let negEP = Secp256k1.negate(eP)
        let R = Secp256k1.add(sG, negEP)

        // Verify R is not infinity, has even y, and R.x == r
        guard !R.isInfinity else { return false }
        guard Secp256k1.hasEvenY(R) else { return false }
        guard R.x == r else { return false }

        return true
    }

    // MARK: - Helpers

    /// Lift an x-only public key (32 bytes) to a curve point with even y.
    ///
    /// Computes `y = sqrt(x^3 + 7) mod p` and picks the even root.
    ///
    /// - Parameter xData: 32-byte x-coordinate.
    /// - Returns: The curve point with even y, or `nil` if x is not on the curve.
    static func liftX(_ xData: Data) -> Secp256k1.Point? {
        let p = Secp256k1.p
        let x = Secp256k1.toUInt64Array(xData)

        guard Secp256k1.compare(x, p) < 0 else { return nil }

        // c = x^3 + 7 mod p
        let x2 = Secp256k1.modSqr(x, mod: p)
        let x3 = Secp256k1.modMul(x2, x, mod: p)
        let seven: [UInt64] = [0, 0, 0, 7]
        let c = Secp256k1.modAdd(x3, seven, mod: p)

        // y = c^((p+1)/4) mod p
        let pPlus1Div4 = Secp256k1.computePPlus1Div4()
        let y = Secp256k1.modExp(c, pPlus1Div4, mod: p)

        // Verify y^2 == c
        let y2 = Secp256k1.modSqr(y, mod: p)
        guard y2 == c else { return nil }

        // Choose even y
        let finalY: [UInt64]
        if y[3] & 1 == 0 {
            finalY = y
        } else {
            finalY = Secp256k1.modSub(Secp256k1.zero, y, mod: p)
        }

        return Secp256k1.Point(x: x, y: finalY)
    }

    /// Generate 32 bytes of auxiliary randomness for BIP340 nonce derivation.
    ///
    /// Uses the system's cryptographically secure random number generator.
    /// Falls back to zero bytes if the RNG fails (deterministic but less private).
    private static func generateAuxRand() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, 32, &bytes)
        if status == errSecSuccess {
            return Data(bytes)
        }
        // Fallback: zero aux rand (signing is still deterministic and secure,
        // just loses the privacy benefit of randomized nonces)
        return Data(repeating: 0, count: 32)
    }

    /// XOR two equal-length Data values byte-by-byte.
    /// Returns empty Data if lengths differ (defensive; should never happen).
    private static func xorBytes(_ a: Data, _ b: Data) -> Data {
        guard a.count == b.count else {
            AppLogger.error("SchnorrSigner.xorBytes: length mismatch (\(a.count) vs \(b.count))", category: .security)
            return Data(count: a.count)
        }
        var result = Data(count: a.count)
        for i in 0..<a.count {
            result[i] = a[a.startIndex + i] ^ b[b.startIndex + i]
        }
        return result
    }

    /// SHA-256 hash using CryptoKit.
    private static func sha256(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }
}
