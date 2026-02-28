// MARK: - EllipticCurve.swift
// Bitcoin AI Wallet
//
// Minimal secp256k1 elliptic curve operations built from scratch.
// Uses 256-bit unsigned integer arithmetic with [UInt64] (4 limbs).
// No external dependencies -- system frameworks only (CryptoKit for hashing).
//
// secp256k1 parameters:
//   p  = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F
//   n  = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
//   Gx = 0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798
//   Gy = 0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8
//
// Limb order: [UInt64] with index 0 = most significant 64 bits (big-endian).
//
// Platform: iOS 17.0+
// Frameworks: Foundation, CryptoKit

import Foundation
import CryptoKit

// MARK: - Secp256k1

enum Secp256k1 {

    // MARK: - Curve Constants (big-endian limb order: [0] = MSW)

    /// Field prime  p = 2^256 - 2^32 - 977
    static let p: [UInt64] = [
        0xFFFFFFFF_FFFFFFFF,
        0xFFFFFFFF_FFFFFFFF,
        0xFFFFFFFF_FFFFFFFF,
        0xFFFFFFFE_FFFFFC2F
    ]

    /// Group order
    static let n: [UInt64] = [
        0xFFFFFFFF_FFFFFFFF,
        0xFFFFFFFF_FFFFFFFE,
        0xBAAEDCE6_AF48A03B,
        0xBFD25E8C_D0364141
    ]

    /// Generator x-coordinate
    static let gx: [UInt64] = [
        0x79BE667E_F9DCBBAC,
        0x55A06295_CE870B07,
        0x029BFCDB_2DCE28D9,
        0x59F2815B_16F81798
    ]

    /// Generator y-coordinate
    static let gy: [UInt64] = [
        0x483ADA77_26A3C465,
        0x5DA4FBFC_0E1108A8,
        0xFD17B448_A6855419,
        0x9C47D08F_FB10D4B8
    ]

    /// Zero (additive identity)
    static let zero: [UInt64] = [0, 0, 0, 0]

    /// One
    static let one: [UInt64] = [0, 0, 0, 1]

    /// n / 2  (for low-S enforcement)
    static let halfN: [UInt64] = [
        0x7FFFFFFF_FFFFFFFF,
        0xFFFFFFFF_FFFFFFFF,
        0x5D576E73_57A4501D,
        0xDFE92F46_681B20A0
    ]

    // MARK: - Point

    /// A point on the secp256k1 curve (affine coordinates).
    struct Point: Equatable {
        let x: [UInt64]  // 4 x UInt64 = 256 bits, big-endian limb order
        let y: [UInt64]

        static let infinity = Point(x: [], y: [])

        var isInfinity: Bool { x.isEmpty || y.isEmpty }

        static func == (lhs: Point, rhs: Point) -> Bool {
            if lhs.isInfinity && rhs.isInfinity { return true }
            if lhs.isInfinity || rhs.isInfinity { return false }
            return lhs.x == rhs.x && lhs.y == rhs.y
        }
    }

    /// The generator point G.
    static let G = Point(x: gx, y: gy)

    // =========================================================================
    // MARK: - 256-bit Unsigned Integer Arithmetic
    // =========================================================================
    // All [UInt64] arrays have exactly 4 elements, big-endian limb order.

    /// Compare two 256-bit integers. Returns -1, 0, or 1.
    static func compare(_ a: [UInt64], _ b: [UInt64]) -> Int {
        for i in 0..<4 {
            if a[i] < b[i] { return -1 }
            if a[i] > b[i] { return 1 }
        }
        return 0
    }

    /// Whether a == 0
    static func isZero(_ a: [UInt64]) -> Bool {
        a[0] == 0 && a[1] == 0 && a[2] == 0 && a[3] == 0
    }

    /// Raw addition returning (result, carry). No modular reduction.
    static func rawAdd(_ a: [UInt64], _ b: [UInt64]) -> ([UInt64], Bool) {
        var result = [UInt64](repeating: 0, count: 4)
        var carry: UInt64 = 0
        for i in stride(from: 3, through: 0, by: -1) {
            let (sum1, c1) = a[i].addingReportingOverflow(b[i])
            let (sum2, c2) = sum1.addingReportingOverflow(carry)
            result[i] = sum2
            carry = (c1 ? 1 : 0) + (c2 ? 1 : 0)
        }
        return (result, carry != 0)
    }

    /// Raw subtraction returning (result, borrow). No modular reduction.
    static func rawSub(_ a: [UInt64], _ b: [UInt64]) -> ([UInt64], Bool) {
        var result = [UInt64](repeating: 0, count: 4)
        var borrow: UInt64 = 0
        for i in stride(from: 3, through: 0, by: -1) {
            let (diff1, b1) = a[i].subtractingReportingOverflow(b[i])
            let (diff2, b2) = diff1.subtractingReportingOverflow(borrow)
            result[i] = diff2
            borrow = (b1 ? 1 : 0) + (b2 ? 1 : 0)
        }
        return (result, borrow != 0)
    }

    /// Modular addition: (a + b) mod m
    static func modAdd(_ a: [UInt64], _ b: [UInt64], mod m: [UInt64]) -> [UInt64] {
        let (sum, carry) = rawAdd(a, b)
        if carry || compare(sum, m) >= 0 {
            let (reduced, _) = rawSub(sum, m)
            return reduced
        }
        return sum
    }

    /// Modular subtraction: (a - b) mod m
    static func modSub(_ a: [UInt64], _ b: [UInt64], mod m: [UInt64]) -> [UInt64] {
        let (diff, borrow) = rawSub(a, b)
        if borrow {
            let (corrected, _) = rawAdd(diff, m)
            return corrected
        }
        return diff
    }

    /// Full 256x256 -> 512-bit multiplication (unsigned).
    /// Returns 8 limbs in big-endian order.
    private static func fullMul(_ a: [UInt64], _ b: [UInt64]) -> [UInt64] {
        // We treat each UInt64 as a single "digit" in base 2^64.
        // Result has at most 8 digits.
        var result = [UInt64](repeating: 0, count: 8)

        for i in stride(from: 3, through: 0, by: -1) {
            var carry: UInt64 = 0
            for j in stride(from: 3, through: 0, by: -1) {
                let ri = i + j + 1  // position in the 8-limb result (offset by 1 because result is 0..7)
                // Use the formula: high * 2^64 + low = a[i] * b[j]
                let (high, low) = a[i].multipliedFullWidth(by: b[j])

                let (s1, c1) = result[ri].addingReportingOverflow(low)
                let (s2, c2) = s1.addingReportingOverflow(carry)
                result[ri] = s2
                carry = high &+ (c1 ? 1 : 0) &+ (c2 ? 1 : 0)
            }
            result[i] = result[i] &+ carry
        }
        return result
    }

    /// Barrett-style reduction: given 512-bit product, compute mod m.
    /// This is a simple shift-and-subtract reduction for 256-bit moduli.
    private static func reduce512(_ product: [UInt64], mod m: [UInt64]) -> [UInt64] {
        // We'll do repeated shift-and-subtract. For correctness and simplicity,
        // we implement division via a 512-bit / 256-bit long division.
        // The remainder is what we need.

        // Work with an extended representation: 9 limbs for intermediate sums.
        // Use schoolbook long division approach: shift divisor left until aligned,
        // then subtract in a loop.

        // Simpler approach: since our moduli are close to 2^256, we can do
        // iterative subtraction from the high half.

        // Actually let's do a proper reduction. We have product = [p0..p7] (8 limbs, 512 bits).
        // We want product mod m.

        // Strategy: Use the identity that for each "high" 256-bit word h (bits 256..511),
        // h * 2^256 mod m = h * (2^256 - m) mod m   (since 2^256 = (2^256 - m) + m).
        // For secp256k1's p, 2^256 - p = 0x1000003D1 (fits in 64 bits).
        // For the order n, 2^256 - n = 0x14551231950B75FC4402DA1732FC9BEBF (fits in ~129 bits).

        // Generic approach that works for both p and n:
        // 1. Split product into high (p0..p3) and low (p4..p7).
        // 2. Compute high * (2^256 - m) as a 512-bit value.
        // 3. Add to low.
        // 4. Repeat if still >= 2^256 (which can happen for n).
        // 5. Final conditional subtraction.

        // Compute c = 2^256 - m  (this fits in 256 bits since m < 2^256)
        // c = -m mod 2^256
        let twoTo256MinusM: [UInt64] = {
            // 2^256 as a 5-limb number minus m
            // Easier: just negate m in 256-bit arithmetic and handle borrow from bit 256
            var result = [UInt64](repeating: 0, count: 4)
            var borrow: UInt64 = 0
            for i in stride(from: 3, through: 0, by: -1) {
                let (d1, b1) = UInt64(0).subtractingReportingOverflow(m[i])
                let (d2, b2) = d1.subtractingReportingOverflow(borrow)
                result[i] = d2
                borrow = (b1 ? 1 : 0) + (b2 ? 1 : 0)
            }
            // borrow should be 1 here (since we subtracted m > 0 from 0, conceptually from 2^256)
            return result
        }()

        var high: [UInt64] = Array(product[0..<4])
        var low: [UInt64] = Array(product[4..<8])

        // Iteratively reduce: while high != 0, multiply high by twoTo256MinusM and add to low
        // This may need up to 2 iterations because twoTo256MinusM * high can exceed 256 bits.
        for _ in 0..<3 {
            if isZero(high) { break }

            let product2 = fullMul(high, twoTo256MinusM)
            // product2 is 512 bits. Split again.
            let h2: [UInt64] = Array(product2[0..<4])
            let l2: [UInt64] = Array(product2[4..<8])

            // low = low + l2
            let (newLow, carry) = rawAdd(low, l2)
            low = newLow

            // high = h2 + carry
            if carry {
                let (newH2, _) = rawAdd(h2, one)
                high = newH2
            } else {
                high = h2
            }
        }

        // Final conditional subtractions (at most 2-3 needed)
        while compare(low, m) >= 0 {
            let (reduced, _) = rawSub(low, m)
            low = reduced
        }

        return low
    }

    /// Modular multiplication: (a * b) mod m
    static func modMul(_ a: [UInt64], _ b: [UInt64], mod m: [UInt64]) -> [UInt64] {
        let product = fullMul(a, b)
        return reduce512(product, mod: m)
    }

    /// Modular squaring: a^2 mod m (could be optimized but uses modMul for correctness)
    static func modSqr(_ a: [UInt64], mod m: [UInt64]) -> [UInt64] {
        modMul(a, a, mod: m)
    }

    /// Modular exponentiation: base^exp mod m  (binary method, right-to-left)
    static func modExp(_ base: [UInt64], _ exp: [UInt64], mod m: [UInt64]) -> [UInt64] {
        if isZero(exp) { return one }

        var result = one
        var b = base
        // Process each bit of exp from LSB to MSB
        // Limb 3 contains bits 0-63, limb 0 contains bits 192-255
        for limbIndex in stride(from: 3, through: 0, by: -1) {
            var word = exp[limbIndex]
            for _ in 0..<64 {
                if word & 1 == 1 {
                    result = modMul(result, b, mod: m)
                }
                b = modSqr(b, mod: m)
                word >>= 1
            }
        }
        return result
    }

    /// Modular inverse using Fermat's little theorem: a^(m-2) mod m
    /// Requires m to be prime.
    static func modInverse(_ a: [UInt64], mod m: [UInt64]) -> [UInt64] {
        // m - 2
        let exp = rawSub(m, [0, 0, 0, 2]).0
        return modExp(a, exp, mod: m)
    }

    // =========================================================================
    // MARK: - Elliptic Curve Point Operations
    // =========================================================================

    /// Add two points on secp256k1.
    static func add(_ p1: Point, _ p2: Point) -> Point {
        if p1.isInfinity { return p2 }
        if p2.isInfinity { return p1 }

        if p1.x == p2.x {
            if p1.y == p2.y {
                // Points are equal -> double
                return double(p1)
            } else {
                // Points are inverses -> infinity
                return .infinity
            }
        }

        // lambda = (y2 - y1) / (x2 - x1) mod p
        let dy = modSub(p2.y, p1.y, mod: p)
        let dx = modSub(p2.x, p1.x, mod: p)
        let dxInv = modInverse(dx, mod: p)
        let lambda = modMul(dy, dxInv, mod: p)

        // x3 = lambda^2 - x1 - x2 mod p
        let lambda2 = modSqr(lambda, mod: p)
        let x3 = modSub(modSub(lambda2, p1.x, mod: p), p2.x, mod: p)

        // y3 = lambda * (x1 - x3) - y1 mod p
        let y3 = modSub(modMul(lambda, modSub(p1.x, x3, mod: p), mod: p), p1.y, mod: p)

        return Point(x: x3, y: y3)
    }

    /// Double a point on secp256k1.
    static func double(_ pt: Point) -> Point {
        if pt.isInfinity { return .infinity }
        // If y == 0, doubling gives infinity (tangent is vertical)
        if isZero(pt.y) { return .infinity }

        // lambda = (3 * x^2 + a) / (2 * y) mod p
        // For secp256k1, a = 0, so lambda = 3*x^2 / (2*y)
        let x2 = modSqr(pt.x, mod: p)
        let three_x2 = modAdd(modAdd(x2, x2, mod: p), x2, mod: p) // 3 * x^2
        let two_y = modAdd(pt.y, pt.y, mod: p) // 2 * y
        let two_y_inv = modInverse(two_y, mod: p)
        let lambda = modMul(three_x2, two_y_inv, mod: p)

        // x3 = lambda^2 - 2*x mod p
        let lambda2 = modSqr(lambda, mod: p)
        let two_x = modAdd(pt.x, pt.x, mod: p)
        let x3 = modSub(lambda2, two_x, mod: p)

        // y3 = lambda * (x - x3) - y mod p
        let y3 = modSub(modMul(lambda, modSub(pt.x, x3, mod: p), mod: p), pt.y, mod: p)

        return Point(x: x3, y: y3)
    }

    /// Negate a point: -(x, y) = (x, p - y)
    static func negate(_ pt: Point) -> Point {
        if pt.isInfinity { return .infinity }
        return Point(x: pt.x, y: modSub(zero, pt.y, mod: p))
    }

    /// Check if a point has an even y-coordinate.
    static func hasEvenY(_ pt: Point) -> Bool {
        guard !pt.isInfinity else { return false }
        return pt.y[3] & 1 == 0
    }

    /// Scalar multiplication using double-and-add (constant-time-ish via Montgomery ladder would be better,
    /// but for a wallet app this is acceptable; we use a simple left-to-right binary method).
    static func multiply(point pt: Point, scalar k: Data) -> Point {
        let kArr = toUInt64Array(k)
        return multiply(point: pt, scalarArray: kArr)
    }

    /// Scalar multiplication with [UInt64] scalar.
    static func multiply(point pt: Point, scalarArray k: [UInt64]) -> Point {
        if isZero(k) { return .infinity }
        if pt.isInfinity { return .infinity }

        var result = Point.infinity
        var current = pt

        // Process bits from LSB to MSB
        for limbIndex in stride(from: 3, through: 0, by: -1) {
            var word = k[limbIndex]
            for _ in 0..<64 {
                if word & 1 == 1 {
                    result = add(result, current)
                }
                current = double(current)
                word >>= 1
            }
        }
        return result
    }

    /// Multiply the generator G by scalar k.
    static func multiply(scalar k: Data) -> Point {
        multiply(point: G, scalar: k)
    }

    /// Multiply the generator G by scalar array.
    static func multiplyG(scalar k: [UInt64]) -> Point {
        multiply(point: G, scalarArray: k)
    }

    // =========================================================================
    // MARK: - Key Derivation
    // =========================================================================

    /// Compute compressed public key (33 bytes: 0x02/0x03 prefix + x-coordinate).
    static func publicKey(from privateKey: Data) -> Data {
        let pt = multiply(scalar: privateKey)
        guard !pt.isInfinity else { return Data() }
        let xData = toData(pt.x)
        let prefix: UInt8 = hasEvenY(pt) ? 0x02 : 0x03
        var result = Data([prefix])
        result.append(xData)
        return result
    }

    /// Compute x-only public key (32 bytes) for Taproot (BIP340).
    /// If the full public key has odd y, the private key must be negated (caller handles this).
    static func xOnlyPublicKey(from privateKey: Data) -> Data {
        let pt = multiply(scalar: privateKey)
        guard !pt.isInfinity else { return Data() }
        return toData(pt.x)
    }

    // =========================================================================
    // MARK: - Data <-> [UInt64] Conversion
    // =========================================================================

    /// Convert 32-byte big-endian Data to [UInt64] (4 limbs, big-endian order).
    static func toUInt64Array(_ data: Data) -> [UInt64] {
        // Ensure contiguous bytes indexed from 0
        let bytes: [UInt8]
        if data.count < 32 {
            bytes = [UInt8](repeating: 0, count: 32 - data.count) + [UInt8](data)
        } else if data.count > 32 {
            bytes = [UInt8](data.suffix(32))
        } else {
            bytes = [UInt8](data)
        }

        var result = [UInt64](repeating: 0, count: 4)
        for i in 0..<4 {
            let offset = i * 8
            var value: UInt64 = 0
            for j in 0..<8 {
                value = (value << 8) | UInt64(bytes[offset + j])
            }
            result[i] = value
        }
        return result
    }

    /// Convert [UInt64] (4 limbs, big-endian order) to 32-byte big-endian Data.
    static func toData(_ array: [UInt64]) -> Data {
        var data = Data(capacity: 32)
        for limb in array {
            for shift in stride(from: 56, through: 0, by: -8) {
                data.append(UInt8((limb >> shift) & 0xFF))
            }
        }
        return data
    }

    // =========================================================================
    // MARK: - Bit Manipulation Helpers
    // =========================================================================

    /// XOR two 256-bit values.
    static func xor(_ a: [UInt64], _ b: [UInt64]) -> [UInt64] {
        [a[0] ^ b[0], a[1] ^ b[1], a[2] ^ b[2], a[3] ^ b[3]]
    }

    /// Check if scalar is within valid range [1, n-1].
    static func isValidPrivateKey(_ key: Data) -> Bool {
        let k = toUInt64Array(key)
        if isZero(k) { return false }
        if compare(k, n) >= 0 { return false }
        return true
    }

    /// Reduce a scalar modulo n.
    static func reduceModN(_ k: [UInt64]) -> [UInt64] {
        var result = k
        while compare(result, n) >= 0 {
            let (sub, _) = rawSub(result, n)
            result = sub
        }
        return result
    }
}
