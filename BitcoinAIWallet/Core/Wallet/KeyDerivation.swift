import Foundation
import CryptoKit

// MARK: - Key Derivation Errors

/// Errors that can occur during BIP32 key derivation
enum KeyDerivationError: LocalizedError {
    case invalidSeedLength
    case invalidKeyData
    case invalidChildIndex
    case invalidDerivationPath
    case hardenedPublicKeyDerivation
    case keyDerivationFailed
    case invalidPrivateKey
    case pointAtInfinity
    case invalidPublicKey

    var errorDescription: String? {
        switch self {
        case .invalidSeedLength:
            return "Seed must be between 16 and 64 bytes (BIP32)"
        case .invalidKeyData:
            return "Invalid key data produced during derivation"
        case .invalidChildIndex:
            return "Child index out of valid range"
        case .invalidDerivationPath:
            return "Invalid BIP32 derivation path format"
        case .hardenedPublicKeyDerivation:
            return "Cannot derive hardened child from public key"
        case .keyDerivationFailed:
            return "HMAC-SHA512 key derivation produced invalid result"
        case .invalidPrivateKey:
            return "Private key is not valid for secp256k1 curve"
        case .pointAtInfinity:
            return "Derived key resulted in point at infinity"
        case .invalidPublicKey:
            return "Could not compute valid public key"
        }
    }
}

// MARK: - secp256k1 Field Arithmetic

/// Minimal secp256k1 elliptic curve arithmetic implemented from scratch.
///
/// This provides the bare minimum needed for BIP32 key derivation:
/// - Scalar multiplication (private key -> public key)
/// - Point addition (for non-hardened child key derivation)
///
/// All arithmetic is done in the secp256k1 prime field (p = 2^256 - 2^32 - 977).
/// Points use Jacobian coordinates internally for efficiency.
private enum Secp256k1HD {

    // MARK: - Curve Constants

    /// The prime field order: p = 2^256 - 2^32 - 977
    static let p: [UInt64] = [
        0xFFFFFFFEFFFFFC2F, 0xFFFFFFFFFFFFFFFF,
        0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF
    ]

    /// The curve order n
    static let n: [UInt64] = [
        0xBFD25E8CD0364141, 0xBAAEDCE6AF48A03B,
        0xFFFFFFFFFFFFFFFE, 0xFFFFFFFFFFFFFFFF
    ]

    /// Generator point G (uncompressed, x-coordinate)
    static let gx: [UInt64] = [
        0x59F2815B16F81798, 0x029BFCDB2DCE28D9,
        0x55A06295CE870B07, 0x79BE667EF9DCBBAC
    ]

    /// Generator point G (y-coordinate)
    static let gy: [UInt64] = [
        0x9C47D08FFB10D4B8, 0xFD17B448A6855419,
        0x5DA4FBFC0E1108A8, 0x483ADA7726A3C465
    ]

    // MARK: - 256-bit Unsigned Integer Arithmetic

    /// A 256-bit unsigned integer represented as 4 x UInt64 in little-endian limb order.
    /// limbs[0] is the least significant 64 bits.
    typealias UInt256 = [UInt64]  // 4 limbs, little-endian

    /// Zero constant
    static let zero256: UInt256 = [0, 0, 0, 0]

    /// One constant
    static let one256: UInt256 = [1, 0, 0, 0]

    /// Compare: returns -1, 0, or 1
    static func cmp256(_ a: UInt256, _ b: UInt256) -> Int {
        for i in stride(from: 3, through: 0, by: -1) {
            if a[i] < b[i] { return -1 }
            if a[i] > b[i] { return 1 }
        }
        return 0
    }

    /// Addition with carry, returns (result, carry)
    static func add256(_ a: UInt256, _ b: UInt256) -> (UInt256, Bool) {
        var result: UInt256 = [0, 0, 0, 0]
        var carry: UInt64 = 0
        for i in 0..<4 {
            let (s1, c1) = a[i].addingReportingOverflow(b[i])
            let (s2, c2) = s1.addingReportingOverflow(carry)
            result[i] = s2
            carry = (c1 ? 1 : 0) + (c2 ? 1 : 0)
        }
        return (result, carry != 0)
    }

    /// Subtraction with borrow, returns (result, borrowed)
    static func sub256(_ a: UInt256, _ b: UInt256) -> (UInt256, Bool) {
        var result: UInt256 = [0, 0, 0, 0]
        var borrow: UInt64 = 0
        for i in 0..<4 {
            let (s1, b1) = a[i].subtractingReportingOverflow(b[i])
            let (s2, b2) = s1.subtractingReportingOverflow(borrow)
            result[i] = s2
            borrow = (b1 ? 1 : 0) + (b2 ? 1 : 0)
        }
        return (result, borrow != 0)
    }

    // MARK: - Modular Arithmetic (mod p)

    /// Reduce modulo p
    static func modP(_ a: UInt256) -> UInt256 {
        var result = a
        while cmp256(result, p) >= 0 {
            let (sub, _) = sub256(result, p)
            result = sub
        }
        return result
    }

    /// Modular addition: (a + b) mod p
    static func addModP(_ a: UInt256, _ b: UInt256) -> UInt256 {
        let (sum, carry) = add256(a, b)
        if carry || cmp256(sum, p) >= 0 {
            let (result, _) = sub256(sum, p)
            return result
        }
        return sum
    }

    /// Modular subtraction: (a - b) mod p
    static func subModP(_ a: UInt256, _ b: UInt256) -> UInt256 {
        let (diff, borrow) = sub256(a, b)
        if borrow {
            let (result, _) = add256(diff, p)
            return result
        }
        return diff
    }

    /// Modular multiplication: (a * b) mod p
    /// Uses schoolbook multiplication to a 512-bit intermediate, then Barrett-like reduction.
    static func mulModP(_ a: UInt256, _ b: UInt256) -> UInt256 {
        // Multiply to get 512-bit result (8 limbs)
        var product: [UInt64] = Array(repeating: 0, count: 8)

        for i in 0..<4 {
            var carry: UInt64 = 0
            for j in 0..<4 {
                let (hi, lo) = a[i].multipliedFullWidth(by: b[j])
                let (s1, c1) = product[i + j].addingReportingOverflow(lo)
                let (s2, c2) = s1.addingReportingOverflow(carry)
                product[i + j] = s2
                carry = hi + (c1 ? 1 : 0) + (c2 ? 1 : 0)
            }
            product[i + 4] = carry
        }

        // Reduce mod p using repeated subtraction with shifts
        // p = 2^256 - 2^32 - 977 = 2^256 - 4294968273
        // So 2^256 = 4294968273 mod p
        // We process from the top limbs down
        return reduce512ModP(product)
    }

    /// Reduce a 512-bit number modulo p.
    ///
    /// Uses the identity: 2^256 ≡ 0x1000003D1 (mod p)
    /// where 0x1000003D1 = 4294968273
    private static func reduce512ModP(_ product: [UInt64]) -> UInt256 {
        // Split into low 256 bits and high 256 bits
        var low: UInt256 = [product[0], product[1], product[2], product[3]]
        let high: UInt256 = [product[4], product[5], product[6], product[7]]

        // Multiply high by 0x1000003D1 and add to low
        // 0x1000003D1 = (1 << 32) + 0x3D1 = 4294968273
        let reduction: UInt64 = 0x1000003D1

        var carry: UInt64 = 0
        for i in 0..<4 {
            let (hi, lo) = high[i].multipliedFullWidth(by: reduction)
            let (s1, c1) = low[i].addingReportingOverflow(lo)
            let (s2, c2) = s1.addingReportingOverflow(carry)
            low[i] = s2
            carry = hi + (c1 ? 1 : 0) + (c2 ? 1 : 0)
        }

        // Handle remaining carry: multiply carry by reduction and add
        while carry > 0 {
            var newCarry: UInt64 = 0
            let (hi, lo) = carry.multipliedFullWidth(by: reduction)
            let (s1, c1) = low[0].addingReportingOverflow(lo)
            let (s2, c2) = s1.addingReportingOverflow(0)
            low[0] = s2
            newCarry = hi + (c1 ? 1 : 0) + (c2 ? 1 : 0)

            // Propagate carry through remaining limbs
            for i in 1..<4 {
                if newCarry == 0 { break }
                let (s, c) = low[i].addingReportingOverflow(newCarry)
                low[i] = s
                newCarry = c ? 1 : 0
            }

            carry = newCarry
        }

        // Final reduction if >= p
        while cmp256(low, p) >= 0 {
            let (sub, _) = sub256(low, p)
            low = sub
        }

        return low
    }

    /// Modular exponentiation: base^exp mod p (used for inversion)
    static func powModP(_ base: UInt256, _ exp: UInt256) -> UInt256 {
        var result = one256
        var b = base
        var e = exp

        while cmp256(e, zero256) != 0 {
            if e[0] & 1 == 1 {
                result = mulModP(result, b)
            }
            b = mulModP(b, b)
            // Right shift by 1
            for i in 0..<3 {
                e[i] = (e[i] >> 1) | (e[i + 1] << 63)
            }
            e[3] >>= 1
        }

        return result
    }

    /// Modular multiplicative inverse: a^(-1) mod p
    /// Uses Fermat's little theorem: a^(-1) = a^(p-2) mod p
    static func invModP(_ a: UInt256) -> UInt256 {
        let (pMinus2, _) = sub256(p, [2, 0, 0, 0])
        return powModP(a, pMinus2)
    }

    // MARK: - Modular Arithmetic (mod n)

    /// Reduce modulo n (curve order)
    static func modN(_ a: UInt256) -> UInt256 {
        var result = a
        while cmp256(result, n) >= 0 {
            let (sub, _) = sub256(result, n)
            result = sub
        }
        return result
    }

    /// Modular addition mod n: (a + b) mod n
    static func addModN(_ a: UInt256, _ b: UInt256) -> UInt256 {
        let (sum, carry) = add256(a, b)
        if carry {
            // Need to subtract n. Since sum overflowed, think of it as sum + 2^256
            // 2^256 mod n = 2^256 - n (since n < 2^256)
            // We have: real_value = sum + 2^256
            // real_value mod n = (sum + 2^256) mod n = (sum + (2^256 - n)) mod n
            let (nComplement, _) = sub256(zero256, n)  // 2^256 - n, wrapping
            let (result, _) = add256(sum, nComplement)
            return modN(result)
        }
        return modN(sum)
    }

    /// Check if a scalar is valid (0 < k < n)
    static func isValidPrivateKey(_ k: UInt256) -> Bool {
        cmp256(k, zero256) > 0 && cmp256(k, n) < 0
    }

    // MARK: - Elliptic Curve Point Operations (Jacobian Coordinates)

    /// A point on the secp256k1 curve in Jacobian coordinates (X, Y, Z).
    /// Affine coordinates are (X/Z^2, Y/Z^3).
    /// The point at infinity is represented by Z = 0.
    struct JacobianPoint {
        var x: UInt256
        var y: UInt256
        var z: UInt256

        static let infinity = JacobianPoint(x: zero256, y: one256, z: zero256)

        var isInfinity: Bool {
            cmp256(z, zero256) == 0
        }
    }

    /// Convert affine point to Jacobian
    static func toJacobian(x: UInt256, y: UInt256) -> JacobianPoint {
        JacobianPoint(x: x, y: y, z: one256)
    }

    /// Convert Jacobian point to affine (x, y)
    static func toAffine(_ point: JacobianPoint) -> (UInt256, UInt256)? {
        if point.isInfinity { return nil }

        let zInv = invModP(point.z)
        let zInv2 = mulModP(zInv, zInv)
        let zInv3 = mulModP(zInv2, zInv)

        let x = mulModP(point.x, zInv2)
        let y = mulModP(point.y, zInv3)

        return (x, y)
    }

    /// Point doubling in Jacobian coordinates.
    /// Uses the standard formula for a = 0 (secp256k1 has a = 0).
    static func pointDouble(_ p: JacobianPoint) -> JacobianPoint {
        if p.isInfinity { return p }

        // A = Y^2
        let a = mulModP(p.y, p.y)
        // B = 4 * X * A
        let b = mulModP(mulModP([4, 0, 0, 0], p.x), a)
        // C = 8 * A^2
        let c = mulModP([8, 0, 0, 0], mulModP(a, a))
        // D = 3 * X^2  (since curve a = 0)
        let x2 = mulModP(p.x, p.x)
        let d = mulModP([3, 0, 0, 0], x2)

        // X3 = D^2 - 2*B
        let d2 = mulModP(d, d)
        let twoB = addModP(b, b)
        let x3 = subModP(d2, twoB)

        // Y3 = D * (B - X3) - C
        let y3 = subModP(mulModP(d, subModP(b, x3)), c)

        // Z3 = 2 * Y * Z
        let z3 = mulModP(mulModP([2, 0, 0, 0], p.y), p.z)

        return JacobianPoint(x: x3, y: y3, z: z3)
    }

    /// Point addition in Jacobian coordinates.
    static func pointAdd(_ p1: JacobianPoint, _ p2: JacobianPoint) -> JacobianPoint {
        if p1.isInfinity { return p2 }
        if p2.isInfinity { return p1 }

        let z1sq = mulModP(p1.z, p1.z)
        let z2sq = mulModP(p2.z, p2.z)

        let u1 = mulModP(p1.x, z2sq)
        let u2 = mulModP(p2.x, z1sq)

        let s1 = mulModP(p1.y, mulModP(p2.z, z2sq))
        let s2 = mulModP(p2.y, mulModP(p1.z, z1sq))

        if cmp256(u1, u2) == 0 {
            if cmp256(s1, s2) == 0 {
                return pointDouble(p1)
            } else {
                return JacobianPoint.infinity
            }
        }

        let h = subModP(u2, u1)
        let r = subModP(s2, s1)

        let h2 = mulModP(h, h)
        let h3 = mulModP(h2, h)
        let u1h2 = mulModP(u1, h2)

        // X3 = R^2 - H^3 - 2*U1*H^2
        let x3 = subModP(subModP(mulModP(r, r), h3), addModP(u1h2, u1h2))

        // Y3 = R * (U1*H^2 - X3) - S1*H^3
        let y3 = subModP(mulModP(r, subModP(u1h2, x3)), mulModP(s1, h3))

        // Z3 = H * Z1 * Z2
        let z3 = mulModP(h, mulModP(p1.z, p2.z))

        return JacobianPoint(x: x3, y: y3, z: z3)
    }

    /// Scalar multiplication: k * P using double-and-add.
    static func scalarMultiply(_ k: UInt256, _ point: JacobianPoint) -> JacobianPoint {
        var result = JacobianPoint.infinity
        var current = point

        var scalar = k
        while cmp256(scalar, zero256) != 0 {
            if scalar[0] & 1 == 1 {
                result = pointAdd(result, current)
            }
            current = pointDouble(current)
            // Right shift by 1
            for i in 0..<3 {
                scalar[i] = (scalar[i] >> 1) | (scalar[i + 1] << 63)
            }
            scalar[3] >>= 1
        }

        return result
    }

    // MARK: - Public API

    /// Compute the public key from a private key scalar.
    /// Returns the compressed public key (33 bytes: 0x02/0x03 prefix + 32-byte x).
    static func publicKeyFromPrivateKey(_ privateKeyData: Data) -> Data? {
        guard privateKeyData.count == 32 else { return nil }

        let k = dataToUInt256(privateKeyData)
        guard isValidPrivateKey(k) else { return nil }

        let g = toJacobian(x: gx, y: gy)
        let pubPoint = scalarMultiply(k, g)

        guard let (x, y) = toAffine(pubPoint) else { return nil }

        // Compressed format: prefix byte + x coordinate
        let prefix: UInt8 = (y[0] & 1 == 0) ? 0x02 : 0x03
        var result = Data([prefix])
        result.append(uint256ToData(x))
        return result
    }

    /// Add two private keys modulo n (for child key derivation).
    /// Returns nil if the result is zero or >= n.
    static func privateKeyAdd(_ key1: Data, _ key2: Data) -> Data? {
        guard key1.count == 32, key2.count == 32 else { return nil }

        let a = dataToUInt256(key1)
        let b = dataToUInt256(key2)
        let result = addModN(a, b)

        guard isValidPrivateKey(result) else { return nil }
        return uint256ToData(result)
    }

    /// Add a point (given as compressed public key) with k*G.
    /// Used for non-hardened public child key derivation.
    static func publicKeyAdd(_ compressedPubKey: Data, _ tweak: Data) -> Data? {
        guard compressedPubKey.count == 33, tweak.count == 32 else { return nil }

        // Decompress the public key
        guard let (px, py) = decompressPublicKey(compressedPubKey) else { return nil }

        let tweakScalar = dataToUInt256(tweak)
        guard isValidPrivateKey(tweakScalar) else { return nil }

        let g = toJacobian(x: gx, y: gy)
        let tweakPoint = scalarMultiply(tweakScalar, g)

        let pubJacobian = toJacobian(x: px, y: py)
        let resultPoint = pointAdd(pubJacobian, tweakPoint)

        guard let (rx, ry) = toAffine(resultPoint) else { return nil }

        let prefix: UInt8 = (ry[0] & 1 == 0) ? 0x02 : 0x03
        var result = Data([prefix])
        result.append(uint256ToData(rx))
        return result
    }

    /// Decompress a 33-byte compressed public key to (x, y) coordinates.
    static func decompressPublicKey(_ compressed: Data) -> (UInt256, UInt256)? {
        guard compressed.count == 33 else { return nil }

        let prefix = compressed[0]
        guard prefix == 0x02 || prefix == 0x03 else { return nil }

        let x = dataToUInt256(Data(compressed[1..<33]))

        // y^2 = x^3 + 7 (mod p)
        let x2 = mulModP(x, x)
        let x3 = mulModP(x2, x)
        let y2 = addModP(x3, [7, 0, 0, 0])

        // Compute square root: y = y2^((p+1)/4) mod p
        // Since p ≡ 3 (mod 4), this formula gives the square root
        var exp = p
        let (pPlus1, _) = add256(exp, [1, 0, 0, 0])
        exp = pPlus1
        // Divide by 4: right shift by 2
        for _ in 0..<2 {
            for i in stride(from: 3, through: 0, by: -1) {
                if i == 3 {
                    exp[i] >>= 1
                } else {
                    exp[i] = (exp[i] >> 1) | (exp[i + 1] << 63)
                    exp[i + 1] >>= 1
                }
            }
        }
        // Proper right shift by 2
        var pPlus1Div4 = pPlus1
        for _ in 0..<2 {
            for i in 0..<3 {
                pPlus1Div4[i] = (pPlus1Div4[i] >> 1) | (pPlus1Div4[i + 1] << 63)
            }
            pPlus1Div4[3] >>= 1
        }

        var y = powModP(y2, pPlus1Div4)

        // Verify the square root
        let ySquared = mulModP(y, y)
        guard cmp256(ySquared, y2) == 0 else { return nil }

        // Choose correct parity
        let isEven = (y[0] & 1) == 0
        let wantEven = (prefix == 0x02)

        if isEven != wantEven {
            let (negY, _) = sub256(p, y)
            y = negY
        }

        return (x, y)
    }

    // MARK: - Data Conversion

    /// Convert 32-byte big-endian Data to UInt256 (4 x UInt64, little-endian limbs).
    /// Data must be exactly 32 bytes; returns zero if length mismatch.
    static func dataToUInt256(_ data: Data) -> UInt256 {
        guard data.count == 32 else {
            AppLogger.error("dataToUInt256: expected 32 bytes, got \(data.count)", category: .security)
            return [0, 0, 0, 0]
        }
        let bytes = Array(data)
        var result: UInt256 = [0, 0, 0, 0]
        // bytes[0..7] is the most significant -> result[3]
        for i in 0..<4 {
            var limb: UInt64 = 0
            for j in 0..<8 {
                limb = (limb << 8) | UInt64(bytes[i * 8 + j])
            }
            result[3 - i] = limb
        }
        return result
    }

    /// Convert UInt256 to 32-byte big-endian Data
    static func uint256ToData(_ value: UInt256) -> Data {
        var bytes = Data(count: 32)
        for i in 0..<4 {
            let limb = value[3 - i]
            for j in 0..<8 {
                bytes[i * 8 + j] = UInt8((limb >> (56 - j * 8)) & 0xFF)
            }
        }
        return bytes
    }
}

// MARK: - Extended Key

/// BIP32 extended key containing a private key and chain code for hierarchical derivation.
///
/// Supports both hardened and normal child derivation. Hardened derivation
/// uses the private key directly, while normal derivation uses the public key.
struct ExtendedKey {

    // MARK: - Properties

    /// The 32-byte private key
    let privateKey: Data

    /// The 32-byte chain code
    let chainCode: Data

    /// Depth in the derivation hierarchy (0 for master)
    let depth: UInt8

    /// First 4 bytes of the parent key's identifier (0x00000000 for master)
    let fingerprint: Data

    /// The child index used to derive this key (0 for master)
    let childIndex: UInt32

    // MARK: - Computed Properties

    /// The compressed public key (33 bytes: prefix + x-coordinate).
    /// Returns nil only if the private key is invalid (should never happen
    /// with properly derived keys, but avoids a crash in production).
    var publicKey: Data {
        guard let pubKey = Secp256k1HD.publicKeyFromPrivateKey(privateKey) else {
            AppLogger.error("ExtendedKey: failed to compute public key from private key", category: .security)
            return Data(repeating: 0, count: 33)
        }
        return pubKey
    }

    /// The key identifier (Hash160 of the public key)
    var identifier: Data {
        let pubKey = publicKey
        let sha256Hash = Data(SHA256.hash(data: pubKey))
        return ripemd160(sha256Hash)
    }

    /// First 4 bytes of the identifier, used as parent fingerprint for children
    var fingerprintForChildren: Data {
        Data(identifier.prefix(4))
    }

    // MARK: - Master Key Generation

    /// Generate a master extended key from a BIP39 seed.
    ///
    /// Uses HMAC-SHA512 with the key "Bitcoin seed" as specified in BIP32.
    ///
    /// - Parameter seed: The BIP39 seed (typically 64 bytes)
    /// - Returns: The master `ExtendedKey`
    /// - Throws: `KeyDerivationError` if the seed is invalid or produces an invalid key
    static func masterKey(from seed: Data) throws -> ExtendedKey {
        guard seed.count >= 16, seed.count <= 64 else {
            throw KeyDerivationError.invalidSeedLength
        }

        let hmacKey = SymmetricKey(data: "Bitcoin seed".data(using: .utf8)!)
        let hmac = HMAC<SHA512>.authenticationCode(for: seed, using: hmacKey)
        let hmacData = Data(hmac)

        let privateKey = Data(hmacData[0..<32])
        let chainCode = Data(hmacData[32..<64])

        // Validate private key (must be non-zero and less than curve order n)
        let k = Secp256k1HD.dataToUInt256(privateKey)
        guard Secp256k1HD.isValidPrivateKey(k) else {
            throw KeyDerivationError.invalidPrivateKey
        }

        return ExtendedKey(
            privateKey: privateKey,
            chainCode: chainCode,
            depth: 0,
            fingerprint: Data([0x00, 0x00, 0x00, 0x00]),
            childIndex: 0
        )
    }

    // MARK: - Child Key Derivation

    /// Derive a child key at the given index.
    ///
    /// Indices >= 0x80000000 produce hardened keys (using private key in HMAC).
    /// Indices < 0x80000000 produce normal keys (using public key in HMAC).
    ///
    /// - Parameter index: The child index (use `| 0x80000000` for hardened)
    /// - Returns: The derived child `ExtendedKey`
    /// - Throws: `KeyDerivationError` if derivation fails
    func derived(at index: UInt32) throws -> ExtendedKey {
        let isHardened = index >= 0x80000000

        var data = Data()
        if isHardened {
            // Hardened: 0x00 || private_key || index
            data.append(0x00)
            data.append(privateKey)
        } else {
            // Normal: public_key || index
            data.append(publicKey)
        }
        withUnsafeBytes(of: index.bigEndian) { bytes in
            data.append(contentsOf: bytes)
        }

        let hmacKey = SymmetricKey(data: chainCode)
        let hmac = HMAC<SHA512>.authenticationCode(for: data, using: hmacKey)
        let hmacData = Data(hmac)

        let il = Data(hmacData[0..<32])
        let ir = Data(hmacData[32..<64])

        // Compute child private key: (il + parent_key) mod n
        guard let childPrivateKey = Secp256k1HD.privateKeyAdd(il, privateKey) else {
            throw KeyDerivationError.keyDerivationFailed
        }

        // Validate child key
        let k = Secp256k1HD.dataToUInt256(childPrivateKey)
        guard Secp256k1HD.isValidPrivateKey(k) else {
            throw KeyDerivationError.invalidPrivateKey
        }

        return ExtendedKey(
            privateKey: childPrivateKey,
            chainCode: ir,
            depth: depth + 1,
            fingerprint: fingerprintForChildren,
            childIndex: index
        )
    }

    // MARK: - Path Derivation

    /// Derive a key at a BIP32 path from a seed.
    ///
    /// Path format: "m/purpose'/coin_type'/account'/change/index"
    /// Apostrophe (') indicates hardened derivation.
    ///
    /// Examples:
    /// - "m/84'/0'/0'/0/0" - First SegWit receive address
    /// - "m/86'/0'/0'/0/0" - First Taproot receive address
    ///
    /// - Parameters:
    ///   - path: The BIP32 derivation path string
    ///   - seed: The BIP39 seed
    /// - Returns: The derived `ExtendedKey`
    /// - Throws: `KeyDerivationError` if the path is invalid or derivation fails
    static func derivePath(_ path: String, from seed: Data) throws -> ExtendedKey {
        let indices = try parseDerivationPath(path)
        var key = try masterKey(from: seed)

        for index in indices {
            key = try key.derived(at: index)
        }

        return key
    }

    /// Derive a child key from an existing extended key along a relative path.
    ///
    /// - Parameter path: Relative path (e.g., "0/0" for first receive address under an account)
    /// - Returns: The derived `ExtendedKey`
    /// - Throws: `KeyDerivationError` if derivation fails
    func deriveRelativePath(_ path: String) throws -> ExtendedKey {
        let components = path.split(separator: "/")
        var key = self

        for component in components {
            let str = String(component)
            let isHardened = str.hasSuffix("'") || str.hasSuffix("h")
            let indexStr = isHardened ? String(str.dropLast()) : str

            guard let index = UInt32(indexStr) else {
                throw KeyDerivationError.invalidDerivationPath
            }

            let finalIndex = isHardened ? (index | 0x80000000) : index
            key = try key.derived(at: finalIndex)
        }

        return key
    }

    // MARK: - Serialization

    /// Serialize the extended private key in Base58Check format (xprv).
    ///
    /// Format (78 bytes):
    /// - 4 bytes: version (0x0488ADE4 for mainnet xprv)
    /// - 1 byte: depth
    /// - 4 bytes: parent fingerprint
    /// - 4 bytes: child index
    /// - 32 bytes: chain code
    /// - 1 byte: 0x00 (padding)
    /// - 32 bytes: private key
    var serialized: String {
        var data = Data()
        // Version bytes for xprv (mainnet)
        data.append(contentsOf: [0x04, 0x88, 0xAD, 0xE4])
        data.append(depth)
        data.append(fingerprint)
        withUnsafeBytes(of: childIndex.bigEndian) { bytes in
            data.append(contentsOf: bytes)
        }
        data.append(chainCode)
        data.append(0x00)  // padding for private key
        data.append(privateKey)

        return base58CheckEncode(data)
    }

    /// Serialize the extended public key in Base58Check format (xpub).
    ///
    /// Format (78 bytes):
    /// - 4 bytes: version (0x0488B21E for mainnet xpub)
    /// - 1 byte: depth
    /// - 4 bytes: parent fingerprint
    /// - 4 bytes: child index
    /// - 32 bytes: chain code
    /// - 33 bytes: compressed public key
    var serializedPublic: String {
        serializedPublicWithVersion([0x04, 0x88, 0xB2, 0x1E])
    }

    /// Serialize the extended public key with custom version bytes.
    ///
    /// Used for zpub (BIP84), ypub (BIP49), or xpub (BIP44) serialization.
    ///
    /// - Parameter version: 4-byte version prefix
    /// - Returns: Base58Check-encoded extended public key string
    func serializedPublicWithVersion(_ version: [UInt8]) -> String {
        var data = Data()
        data.append(contentsOf: version)
        data.append(depth)
        data.append(fingerprint)
        withUnsafeBytes(of: childIndex.bigEndian) { bytes in
            data.append(contentsOf: bytes)
        }
        data.append(chainCode)
        data.append(publicKey)

        return base58CheckEncode(data)
    }

    // MARK: - Private Helpers

    /// Parse a BIP32 derivation path string into an array of child indices.
    private static func parseDerivationPath(_ path: String) throws -> [UInt32] {
        var pathStr = path.trimmingCharacters(in: .whitespaces)

        // Remove leading "m" or "m/"
        if pathStr.hasPrefix("m/") {
            pathStr = String(pathStr.dropFirst(2))
        } else if pathStr == "m" {
            return []
        }

        guard !pathStr.isEmpty else {
            return []
        }

        let components = pathStr.split(separator: "/")
        var indices = [UInt32]()
        indices.reserveCapacity(components.count)

        for component in components {
            let str = String(component)
            let isHardened = str.hasSuffix("'") || str.hasSuffix("h")
            let indexStr = isHardened ? String(str.dropLast()) : str

            guard let index = UInt32(indexStr) else {
                throw KeyDerivationError.invalidDerivationPath
            }

            guard index < 0x80000000 else {
                throw KeyDerivationError.invalidChildIndex
            }

            indices.append(isHardened ? (index | 0x80000000) : index)
        }

        return indices
    }
}

// MARK: - Derivation Path Constants

/// Standard BIP32 derivation paths for Bitcoin.
enum DerivationPath {

    /// BIP84 - Native SegWit (bc1q...) path.
    ///
    /// Format: m/84'/0'/account'/change/index
    ///
    /// - Parameters:
    ///   - account: Account index (default: 0)
    ///   - change: 0 for receive, 1 for change (default: 0)
    ///   - index: Address index (default: 0)
    /// - Returns: The full derivation path string
    static func segwit(account: UInt32 = 0, change: UInt32 = 0, index: UInt32 = 0) -> String {
        "m/84'/0'/\(account)'/\(change)/\(index)"
    }

    /// BIP86 - Taproot (bc1p...) path.
    ///
    /// Format: m/86'/0'/account'/change/index
    ///
    /// - Parameters:
    ///   - account: Account index (default: 0)
    ///   - change: 0 for receive, 1 for change (default: 0)
    ///   - index: Address index (default: 0)
    /// - Returns: The full derivation path string
    static func taproot(account: UInt32 = 0, change: UInt32 = 0, index: UInt32 = 0) -> String {
        "m/86'/0'/\(account)'/\(change)/\(index)"
    }

    /// BIP44 - Legacy (1...) path for backward compatibility.
    ///
    /// Format: m/44'/0'/account'/change/index
    ///
    /// - Parameters:
    ///   - account: Account index (default: 0)
    ///   - change: 0 for receive, 1 for change (default: 0)
    ///   - index: Address index (default: 0)
    /// - Returns: The full derivation path string
    static func legacy(account: UInt32 = 0, change: UInt32 = 0, index: UInt32 = 0) -> String {
        "m/44'/0'/\(account)'/\(change)/\(index)"
    }

    /// BIP49 - Nested SegWit (3...) path.
    ///
    /// Format: m/49'/0'/account'/change/index
    ///
    /// - Parameters:
    ///   - account: Account index (default: 0)
    ///   - change: 0 for receive, 1 for change (default: 0)
    ///   - index: Address index (default: 0)
    /// - Returns: The full derivation path string
    static func nestedSegwit(account: UInt32 = 0, change: UInt32 = 0, index: UInt32 = 0) -> String {
        "m/49'/0'/\(account)'/\(change)/\(index)"
    }

    /// BIP84 account path (m/84'/0'/account')
    ///
    /// - Parameter account: Account index (default: 0)
    /// - Returns: The account-level derivation path
    static func segwitAccount(account: UInt32 = 0) -> String {
        "m/84'/0'/\(account)'"
    }

    /// BIP86 account path (m/86'/0'/account')
    ///
    /// - Parameter account: Account index (default: 0)
    /// - Returns: The account-level derivation path
    static func taprootAccount(account: UInt32 = 0) -> String {
        "m/86'/0'/\(account)'"
    }

    /// BIP44 account path (m/44'/0'/account')
    ///
    /// - Parameter account: Account index (default: 0)
    /// - Returns: The account-level derivation path
    static func legacyAccount(account: UInt32 = 0) -> String {
        "m/44'/0'/\(account)'"
    }

    /// BIP49 account path (m/49'/0'/account')
    ///
    /// - Parameter account: Account index (default: 0)
    /// - Returns: The account-level derivation path
    static func nestedSegwitAccount(account: UInt32 = 0) -> String {
        "m/49'/0'/\(account)'"
    }
}

// MARK: - RIPEMD-160 Implementation

/// Pure Swift RIPEMD-160 hash implementation.
///
/// Required for Bitcoin address generation (Hash160 = RIPEMD160(SHA256(data))).
/// This avoids any dependency on CommonCrypto.
func ripemd160(_ data: Data) -> Data {
    // RIPEMD-160 constants and functions
    let bytes = Array(data)

    // Initial hash values
    var h0: UInt32 = 0x67452301
    var h1: UInt32 = 0xEFCDAB89
    var h2: UInt32 = 0x98BADCFE
    var h3: UInt32 = 0x10325476
    var h4: UInt32 = 0xC3D2E1F0

    // Pre-processing: adding padding bits
    var message = bytes
    let originalLength = UInt64(bytes.count) * 8

    // Append bit '1' to message (byte 0x80)
    message.append(0x80)

    // Append zeros until message length ≡ 448 (mod 512) bits
    while message.count % 64 != 56 {
        message.append(0x00)
    }

    // Append original length in bits as 64-bit little-endian
    for i in 0..<8 {
        message.append(UInt8((originalLength >> (i * 8)) & 0xFF))
    }

    // Selection of message word
    let r1: [Int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
                     7, 4, 13, 1, 10, 6, 15, 3, 12, 0, 9, 5, 2, 14, 11, 8,
                     3, 10, 14, 4, 9, 15, 8, 1, 2, 7, 0, 6, 13, 11, 5, 12,
                     1, 9, 11, 10, 0, 8, 12, 4, 13, 3, 7, 15, 14, 5, 6, 2,
                     4, 0, 5, 9, 7, 12, 2, 10, 14, 1, 3, 8, 11, 6, 15, 13]

    let r2: [Int] = [5, 14, 7, 0, 9, 2, 11, 4, 13, 6, 15, 8, 1, 10, 3, 12,
                     6, 11, 3, 7, 0, 13, 5, 10, 14, 15, 8, 12, 4, 9, 1, 2,
                     15, 5, 1, 3, 7, 14, 6, 9, 11, 8, 12, 2, 10, 0, 4, 13,
                     8, 6, 4, 1, 3, 11, 15, 0, 5, 12, 2, 13, 9, 7, 10, 14,
                     12, 15, 10, 4, 1, 5, 8, 7, 6, 2, 13, 14, 0, 3, 9, 11]

    let s1: [UInt32] = [11, 14, 15, 12, 5, 8, 7, 9, 11, 13, 14, 15, 6, 7, 9, 8,
                        7, 6, 8, 13, 11, 9, 7, 15, 7, 12, 15, 9, 11, 7, 13, 12,
                        11, 13, 6, 7, 14, 9, 13, 15, 14, 8, 13, 6, 5, 12, 7, 5,
                        11, 12, 14, 15, 14, 15, 9, 8, 9, 14, 5, 6, 8, 6, 5, 12,
                        9, 15, 5, 11, 6, 8, 13, 12, 5, 12, 13, 14, 11, 8, 5, 6]

    let s2: [UInt32] = [8, 9, 9, 11, 13, 15, 15, 5, 7, 7, 8, 11, 14, 14, 12, 6,
                        9, 13, 15, 7, 12, 8, 9, 11, 7, 7, 12, 7, 6, 15, 13, 11,
                        9, 7, 15, 11, 8, 6, 6, 14, 12, 13, 5, 14, 13, 13, 7, 5,
                        15, 5, 8, 11, 14, 14, 6, 14, 6, 9, 12, 9, 12, 5, 15, 8,
                        8, 5, 12, 9, 12, 5, 14, 6, 8, 13, 6, 5, 15, 13, 11, 11]

    // Round constants
    let k1: [UInt32] = [0x00000000, 0x5A827999, 0x6ED9EBA1, 0x8F1BBCDC, 0xA953FD4E]
    let k2: [UInt32] = [0x50A28BE6, 0x5C4DD124, 0x6D703EF3, 0x7A6D76E9, 0x00000000]

    // Boolean functions
    func f(_ j: Int, _ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
        switch j {
        case 0..<16:  return x ^ y ^ z
        case 16..<32: return (x & y) | (~x & z)
        case 32..<48: return (x | ~y) ^ z
        case 48..<64: return (x & z) | (y & ~z)
        case 64..<80: return x ^ (y | ~z)
        default: return 0 // Unreachable for valid RIPEMD-160 round indices 0..<80
        }
    }

    // Rotate left
    func rotl(_ x: UInt32, _ n: UInt32) -> UInt32 {
        (x << n) | (x >> (32 - n))
    }

    // Process each 512-bit block
    let blockCount = message.count / 64
    for i in 0..<blockCount {
        let blockStart = i * 64

        // Parse block into 16 little-endian 32-bit words
        var x = [UInt32](repeating: 0, count: 16)
        for j in 0..<16 {
            let offset = blockStart + j * 4
            x[j] = UInt32(message[offset])
                | (UInt32(message[offset + 1]) << 8)
                | (UInt32(message[offset + 2]) << 16)
                | (UInt32(message[offset + 3]) << 24)
        }

        // Left round
        var al = h0, bl = h1, cl = h2, dl = h3, el = h4
        // Right round
        var ar = h0, br = h1, cr = h2, dr = h3, er = h4

        for j in 0..<80 {
            let round = j / 16

            // Left
            var t = al &+ f(j, bl, cl, dl) &+ x[r1[j]] &+ k1[round]
            t = rotl(t, s1[j]) &+ el
            al = el; el = dl; dl = rotl(cl, 10); cl = bl; bl = t

            // Right
            t = ar &+ f(79 - j, br, cr, dr) &+ x[r2[j]] &+ k2[round]
            t = rotl(t, s2[j]) &+ er
            ar = er; er = dr; dr = rotl(cr, 10); cr = br; br = t
        }

        let t = h1 &+ cl &+ dr
        h1 = h2 &+ dl &+ er
        h2 = h3 &+ el &+ ar
        h3 = h4 &+ al &+ br
        h4 = h0 &+ bl &+ cr
        h0 = t
    }

    // Produce the final hash (little-endian)
    var result = Data(count: 20)
    for (i, h) in [h0, h1, h2, h3, h4].enumerated() {
        result[i * 4 + 0] = UInt8(h & 0xFF)
        result[i * 4 + 1] = UInt8((h >> 8) & 0xFF)
        result[i * 4 + 2] = UInt8((h >> 16) & 0xFF)
        result[i * 4 + 3] = UInt8((h >> 24) & 0xFF)
    }

    return result
}

// MARK: - Base58Check Encoding

/// Base58 alphabet used in Bitcoin
private let base58Alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")

/// Encode data using Base58Check (with 4-byte SHA256d checksum).
///
/// - Parameter data: The data to encode
/// - Returns: Base58Check-encoded string
func base58CheckEncode(_ data: Data) -> String {
    // Double-SHA256 checksum
    let hash1 = SHA256.hash(data: data)
    let hash2 = SHA256.hash(data: Data(hash1))
    let checksum = Data(hash2).prefix(4)

    var payload = data
    payload.append(checksum)

    return base58Encode(payload)
}

/// Encode raw data in Base58.
///
/// - Parameter data: The data to encode
/// - Returns: Base58-encoded string
func base58Encode(_ data: Data) -> String {
    let bytes = Array(data)

    // Count leading zeros
    var leadingZeros = 0
    for byte in bytes {
        if byte == 0 { leadingZeros += 1 }
        else { break }
    }

    // Convert to base58 using big number division
    var num = [UInt32]()
    for byte in bytes {
        var carry = UInt32(byte)
        for i in 0..<num.count {
            carry += num[i] << 8
            num[i] = carry % 58
            carry /= 58
        }
        while carry > 0 {
            num.append(carry % 58)
            carry /= 58
        }
    }

    // Build result string
    var result = String(repeating: "1", count: leadingZeros)
    for digit in num.reversed() {
        result.append(base58Alphabet[Int(digit)])
    }

    return result
}

// MARK: - Bech32/Bech32m Address Encoding

/// Bech32 encoding for SegWit and Taproot addresses (BIP173, BIP350).
///
/// This is a self-contained implementation that handles both Bech32 (witness v0)
/// and Bech32m (witness v1+) encoding for Bitcoin address generation.
enum SegWitAddressEncoder {

    /// Encoding type
    private enum Encoding {
        /// BIP173 - SegWit v0 (bc1q...)
        case bech32
        /// BIP350 - SegWit v1+ / Taproot (bc1p...)
        case bech32m
    }

    /// The Bech32 character set
    private static let charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")

    /// Bech32 generator values for checksum computation
    private static let generator: [UInt32] = [
        0x3B6A57B2, 0x26508E6D, 0x1EA119FA, 0x3D4233DD, 0x2A1462B3
    ]

    /// Compute the polymod checksum
    private static func polymod(_ values: [UInt8]) -> UInt32 {
        var chk: UInt32 = 1
        for v in values {
            let b = chk >> 25
            chk = ((chk & 0x1FFFFFF) << 5) ^ UInt32(v)
            for i in 0..<5 {
                if (b >> i) & 1 != 0 {
                    chk ^= generator[i]
                }
            }
        }
        return chk
    }

    /// Expand the human-readable part for checksum computation
    private static func hrpExpand(_ hrp: String) -> [UInt8] {
        let chars = Array(hrp.utf8)
        var result = chars.map { $0 >> 5 }
        result.append(0)
        result.append(contentsOf: chars.map { $0 & 31 })
        return result
    }

    /// Create a checksum for the given HRP and data
    private static func createChecksum(_ hrp: String, _ data: [UInt8], _ encoding: Encoding) -> [UInt8] {
        let values = hrpExpand(hrp) + data + [0, 0, 0, 0, 0, 0]
        let constant: UInt32 = encoding == .bech32 ? 1 : 0x2BC830A3
        let polymodValue = polymod(values) ^ constant
        var checksum = [UInt8]()
        for i in 0..<6 {
            checksum.append(UInt8((polymodValue >> (5 * (5 - i))) & 31))
        }
        return checksum
    }

    /// Encode a witness program into a Bech32/Bech32m address.
    ///
    /// Automatically selects Bech32 for witness version 0 (SegWit)
    /// and Bech32m for witness version 1+ (Taproot).
    ///
    /// - Parameters:
    ///   - hrp: Human-readable part ("bc" for mainnet, "tb" for testnet)
    ///   - witnessVersion: Witness version (0 for SegWit, 1 for Taproot)
    ///   - witnessProgram: The witness program data
    /// - Returns: The Bech32/Bech32m encoded address, or nil if invalid
    static func encode(hrp: String, witnessVersion: UInt8, witnessProgram: Data) -> String? {
        // Validate witness program length
        guard witnessProgram.count >= 2, witnessProgram.count <= 40 else { return nil }
        guard witnessVersion <= 16 else { return nil }

        // SegWit v0 must be exactly 20 or 32 bytes
        if witnessVersion == 0 {
            guard witnessProgram.count == 20 || witnessProgram.count == 32 else { return nil }
        }

        // Convert witness program to 5-bit groups
        guard let converted = convertBits(data: Array(witnessProgram), fromBits: 8, toBits: 5, pad: true) else {
            return nil
        }

        let data = [witnessVersion] + converted
        let encoding: Encoding = witnessVersion == 0 ? .bech32 : .bech32m
        let checksum = createChecksum(hrp, data, encoding)

        var result = hrp + "1"
        for d in data + checksum {
            result.append(charset[Int(d)])
        }

        return result
    }

    /// Convert between bit groups (e.g., 8-bit to 5-bit for Bech32)
    private static func convertBits(data: [UInt8], fromBits: Int, toBits: Int, pad: Bool) -> [UInt8]? {
        var acc: UInt32 = 0
        var bits: Int = 0
        var result = [UInt8]()
        let maxv: UInt32 = (1 << toBits) - 1

        for value in data {
            let v = UInt32(value)
            guard v >> fromBits == 0 else { return nil }

            acc = (acc << fromBits) | v
            bits += fromBits

            while bits >= toBits {
                bits -= toBits
                result.append(UInt8((acc >> bits) & maxv))
            }
        }

        if pad {
            if bits > 0 {
                result.append(UInt8((acc << (toBits - bits)) & maxv))
            }
        } else if bits >= fromBits {
            return nil
        } else if (acc << (toBits - bits)) & maxv != 0 {
            return nil
        }

        return result
    }
}

// MARK: - Taproot Key Tweaking

/// BIP341/BIP86 Taproot key tweaking utilities.
///
/// Provides public key tweaking for Taproot address generation.
/// These functions bridge the private secp256k1 implementation to
/// the public HDWallet API.
enum TaprootTweaker {

    /// Compute the BIP86 tweaked output key x-coordinate from a compressed public key.
    ///
    /// Implements BIP341 key-path-only tweaking (no script tree):
    /// 1. Extract x-only internal key from the compressed public key
    /// 2. Compute tweak: t = tagged_hash("TapTweak", internal_key_x)
    /// 3. Compute output point: Q = P_even + t * G
    /// 4. Return x(Q) as 32 bytes
    ///
    /// - Parameter compressedPublicKey: 33-byte compressed public key (0x02/0x03 prefix)
    /// - Returns: 32-byte x-only tweaked output key, or nil on failure
    static func tweakedOutputKeyX(from compressedPublicKey: Data) -> Data? {
        guard compressedPublicKey.count == 33 else { return nil }

        let prefix = compressedPublicKey[0]
        guard prefix == 0x02 || prefix == 0x03 else { return nil }

        // x-only internal key (32 bytes)
        let internalKeyX = Data(compressedPublicKey[1..<33])

        // BIP341 tagged hash: tagged_hash("TapTweak", internal_key_x)
        // tagged_hash(tag, msg) = SHA256(SHA256(tag) || SHA256(tag) || msg)
        // Safe: ASCII string always encodes to UTF-8
        let tagData = Data("TapTweak".utf8)
        let tagHash = Data(SHA256.hash(data: tagData))

        var tweakInput = Data()
        tweakInput.reserveCapacity(64 + 32)
        tweakInput.append(tagHash)
        tweakInput.append(tagHash)
        tweakInput.append(internalKeyX)

        let tweak = Data(SHA256.hash(data: tweakInput))

        // Use the even-y variant of the internal key for BIP86
        var evenCompressedKey = compressedPublicKey
        if prefix == 0x03 {
            var mutable = Data(compressedPublicKey)
            mutable[0] = 0x02
            evenCompressedKey = mutable
        }

        // Q = P_even + tweak * G
        guard let outputKey = Secp256k1HD.publicKeyAdd(evenCompressedKey, tweak) else {
            return nil
        }

        // Return x-only (32 bytes, drop prefix)
        return Data(outputKey[1..<33])
    }
}
