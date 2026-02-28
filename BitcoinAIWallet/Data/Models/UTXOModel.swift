// MARK: - UTXOModel.swift
// Bitcoin AI Wallet
//
// Domain model representing a single Unspent Transaction Output (UTXO).
// UTXOs are the fundamental building blocks of Bitcoin transactions;
// each UTXO is an indivisible unit of bitcoin that can be consumed
// as an input to a new transaction.
//
// Platform: iOS 17.0+
// Framework: Foundation

import Foundation

// MARK: - UTXOModel

/// Domain model for an Unspent Transaction Output (UTXO).
///
/// A UTXO is uniquely identified by the combination of its originating
/// transaction ID (`txid`) and output index (`vout`). The `value` is
/// stored as `Decimal` for precision, with a parallel `valueSats` field
/// for integer-based satoshi calculations used in transaction building.
struct UTXOModel: Identifiable, Codable, Equatable {

    // MARK: - Identifiable

    /// Composite identifier formed from `txid:vout`.
    ///
    /// This mirrors the standard Bitcoin convention for referencing
    /// a specific output within a transaction.
    var id: String { "\(txid):\(vout)" }

    // MARK: - Properties

    /// The 64-character hex transaction ID that created this output.
    let txid: String

    /// The zero-based index of this output within its parent transaction.
    let vout: Int

    /// Value of this UTXO in BTC.
    ///
    /// Always use `Decimal` for Bitcoin amounts to avoid IEEE 754
    /// floating-point precision issues.
    let value: Decimal

    /// Value of this UTXO in satoshis (1 BTC = 100,000,000 satoshis).
    let valueSats: Int64

    /// Number of confirmations for the transaction that created this UTXO.
    let confirmations: Int

    /// The Bitcoin address that controls this UTXO.
    let address: String

    /// The hex-encoded scriptPubKey locking this output, or `nil` if unavailable.
    let scriptPubKey: String?

    /// Whether this UTXO has already been spent in a subsequent transaction.
    let isSpent: Bool

    /// The BIP-32 derivation path used to derive the key controlling this UTXO.
    ///
    /// Example: `"m/84'/0'/0'/0/3"` for the 4th receive address in a BIP-84 wallet.
    /// May be `nil` if the derivation path is unknown (e.g., imported addresses).
    let derivationPath: String?

    // MARK: - Computed Properties

    /// Whether this UTXO's parent transaction has at least one confirmation.
    var isConfirmed: Bool {
        confirmations > 0
    }

    /// Whether this UTXO can be used as an input in a new transaction.
    ///
    /// A UTXO is spendable when it has not been spent and has at least
    /// one confirmation. Unconfirmed UTXOs are excluded by default to
    /// avoid building transactions on top of potentially replaceable ones.
    var isSpendable: Bool {
        !isSpent && confirmations >= 1
    }

    /// Value formatted as a BTC string with 8 decimal places.
    var formattedValue: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 8
        formatter.maximumFractionDigits = 8
        formatter.groupingSeparator = ","
        formatter.decimalSeparator = "."
        return formatter.string(from: value as NSDecimalNumber) ?? "0.00000000"
    }

    /// Truncated transaction ID showing the first 8 and last 8 characters.
    var truncatedTxid: String {
        guard txid.count > 16 else { return txid }
        let start = txid.prefix(8)
        let end = txid.suffix(8)
        return "\(start)...\(end)"
    }

    /// Whether this is a change output (derived from the change path m/84'/0'/0'/1/...).
    var isChange: Bool {
        guard let path = derivationPath else { return false }
        // BIP-84 change path contains /1/ as the change indicator
        return path.contains("/1/")
    }

    /// The address truncated for compact display.
    var truncatedAddress: String {
        guard address.count > 16 else { return address }
        let start = address.prefix(8)
        let end = address.suffix(8)
        return "\(start)...\(end)"
    }
}
