// MARK: - ScriptType.swift
// Bitcoin AI Wallet
//
// Bitcoin script/address type definitions covering all standard output types.
// Used for address generation, derivation path selection, and fee estimation.
//
// Platform: iOS 17.0+
// Framework: Foundation

import Foundation

// MARK: - ScriptType

/// Enumerates the Bitcoin output script types supported by the wallet.
///
/// Each case corresponds to a specific address format and BIP derivation standard:
/// - `p2pkh`: Legacy pay-to-public-key-hash (BIP44), addresses starting with `1`.
/// - `p2sh`:  Pay-to-script-hash (BIP49), addresses starting with `3`.
/// - `p2wpkh`: Native SegWit pay-to-witness-public-key-hash (BIP84), addresses starting with `bc1q`.
/// - `p2tr`:  Taproot pay-to-taproot (BIP86), addresses starting with `bc1p`.
enum ScriptType: String, Codable, CaseIterable {
    case p2pkh  = "P2PKH"
    case p2sh   = "P2SH"
    case p2wpkh = "P2WPKH"
    case p2tr   = "P2TR"

    // MARK: - Display

    /// Human-readable name for the script type, suitable for UI display.
    var displayName: String {
        switch self {
        case .p2pkh:  return "Legacy"
        case .p2sh:   return "Script Hash"
        case .p2wpkh: return "Native SegWit"
        case .p2tr:   return "Taproot"
        }
    }

    // MARK: - SegWit Properties

    /// The SegWit witness version, if applicable.
    ///
    /// - `0` for P2WPKH (BIP141).
    /// - `1` for P2TR (BIP341).
    /// - `nil` for non-witness types (P2PKH, P2SH).
    var witnessVersion: Int? {
        switch self {
        case .p2wpkh: return 0
        case .p2tr:   return 1
        default:      return nil
        }
    }

    // MARK: - Derivation Paths

    /// The BIP-standard derivation path prefix for this script type.
    ///
    /// Follows the convention:
    /// - BIP44: `m/44'/0'/0'` (P2PKH)
    /// - BIP49: `m/49'/0'/0'` (P2SH-P2WPKH)
    /// - BIP84: `m/84'/0'/0'` (P2WPKH)
    /// - BIP86: `m/86'/0'/0'` (P2TR)
    var derivationPathPrefix: String {
        switch self {
        case .p2pkh:  return "m/44'/0'/0'"
        case .p2sh:   return "m/49'/0'/0'"
        case .p2wpkh: return "m/84'/0'/0'"
        case .p2tr:   return "m/86'/0'/0'"
        }
    }

    // MARK: - Fee Estimation

    /// Estimated input size in virtual bytes (vBytes) for fee calculation.
    ///
    /// These values represent the typical input size for each script type,
    /// accounting for witness discount where applicable:
    /// - P2PKH:  148 vB (no witness discount)
    /// - P2SH:    91 vB (wrapped SegWit)
    /// - P2WPKH:  68 vB (native SegWit, ~75% discount on witness data)
    /// - P2TR:    58 vB (Taproot key-path spend, most efficient)
    var estimatedInputVSize: Int {
        switch self {
        case .p2pkh:  return 148
        case .p2sh:   return 91
        case .p2wpkh: return 68
        case .p2tr:   return 58
        }
    }

    // MARK: - Address Detection

    /// Detect the script type from a Bitcoin address string.
    ///
    /// Supports both mainnet and testnet address prefixes:
    /// - Mainnet: `1...` (P2PKH), `3...` (P2SH), `bc1q...` (P2WPKH), `bc1p...` (P2TR)
    /// - Testnet: `m.../n...` (P2PKH), `2...` (P2SH), `tb1q...` (P2WPKH), `tb1p...` (P2TR)
    ///
    /// - Parameter address: The Bitcoin address string to classify.
    /// - Returns: The matching `ScriptType`, or `nil` if the format is unrecognized.
    static func from(address: String) -> ScriptType? {
        let lowercased = address.lowercased()

        if lowercased.hasPrefix("bc1p") || lowercased.hasPrefix("tb1p") {
            return .p2tr
        }
        if lowercased.hasPrefix("bc1q") || lowercased.hasPrefix("tb1q") {
            return .p2wpkh
        }
        if address.hasPrefix("3") || address.hasPrefix("2") {
            return .p2sh
        }
        if address.hasPrefix("1") || address.hasPrefix("m") || address.hasPrefix("n") {
            return .p2pkh
        }

        return nil
    }
}
