// MARK: - TransactionModel.swift
// Bitcoin AI Wallet
//
// Domain model representing a single Bitcoin transaction.
// Covers both sent and received transactions with full metadata
// including confirmation status, fee information, and address details.
//
// Platform: iOS 17.0+
// Framework: Foundation

import Foundation

// MARK: - TransactionModel

/// Domain model for a single Bitcoin transaction.
///
/// All monetary values are stored as `Decimal` to preserve satoshi-level
/// precision. The `id` property maps directly to the Bitcoin transaction
/// identifier (`txid`), ensuring natural deduplication in SwiftUI lists.
struct TransactionModel: Identifiable, Codable, Equatable {

    // MARK: - Properties

    /// Unique identifier, equal to the Bitcoin transaction ID (`txid`).
    let id: String

    /// The full 64-character hex transaction identifier.
    let txid: String

    /// Whether this transaction represents funds sent or received.
    let type: TransactionType

    /// Transaction amount in BTC (always positive regardless of type).
    let amount: Decimal

    /// Network fee paid for this transaction in BTC.
    let fee: Decimal

    /// Source addresses (inputs) for this transaction.
    let fromAddresses: [String]

    /// Destination addresses (outputs) for this transaction.
    let toAddresses: [String]

    /// Number of confirmations on the blockchain.
    let confirmations: Int

    /// Block height at which this transaction was mined, or `nil` if unconfirmed.
    let blockHeight: Int?

    /// Timestamp of the transaction (block time for confirmed, first-seen for unconfirmed).
    let timestamp: Date

    /// Raw transaction size in bytes, or `nil` if unavailable.
    let size: Int?

    /// Virtual transaction size in vbytes (for SegWit weight calculation), or `nil` if unavailable.
    let virtualSize: Int?

    /// Current status of the transaction.
    let status: TransactionStatus

    // MARK: - Transaction Type

    /// The direction of funds flow relative to the user's wallet.
    enum TransactionType: String, Codable, Equatable {
        /// Funds were sent from the wallet to an external address.
        case sent
        /// Funds were received into the wallet from an external source.
        case received
    }

    // MARK: - Transaction Status

    /// Lifecycle status of a transaction on the Bitcoin network.
    enum TransactionStatus: String, Codable, Equatable {
        /// Transaction is in the mempool but not yet included in a block.
        case pending
        /// Transaction has been included in at least one block.
        case confirmed
        /// Transaction was rejected or double-spent (rare).
        case failed
    }

    // MARK: - Computed Properties

    /// Whether the transaction is still pending confirmation.
    var isPending: Bool {
        status == .pending
    }

    /// Whether the transaction has reached the standard 6-confirmation threshold.
    ///
    /// Six confirmations is the widely accepted standard for considering
    /// a Bitcoin transaction irreversible.
    var isConfirmed: Bool {
        confirmations >= 6
    }

    /// Amount formatted as a signed BTC string with the appropriate prefix.
    ///
    /// Sent transactions are prefixed with `"-"`, received with `"+"`.
    /// Example: `"+0.00123456"` or `"-0.05000000"`.
    var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 8
        formatter.maximumFractionDigits = 8
        formatter.groupingSeparator = ","
        formatter.decimalSeparator = "."
        let formatted = formatter.string(from: amount as NSDecimalNumber) ?? "0.00000000"
        switch type {
        case .sent:
            return "-\(formatted)"
        case .received:
            return "+\(formatted)"
        }
    }

    /// Fee formatted as a BTC string.
    ///
    /// Example: `"0.00001234"`.
    var formattedFee: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 8
        formatter.maximumFractionDigits = 8
        formatter.groupingSeparator = ","
        formatter.decimalSeparator = "."
        return formatter.string(from: fee as NSDecimalNumber) ?? "0.00000000"
    }

    /// Human-readable date string.
    ///
    /// Uses relative formatting for recent transactions and a full date
    /// for older ones.
    var formattedDate: String {
        let now = Date()
        let interval = now.timeIntervalSince(timestamp)

        // Less than 1 minute
        if interval < 60 {
            return "Just now"
        }

        // Less than 1 hour
        if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) min ago"
        }

        // Less than 24 hours
        if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        }

        // Less than 7 days
        if interval < 604800 {
            let days = Int(interval / 86400)
            return "\(days) day\(days == 1 ? "" : "s") ago"
        }

        // Older than 7 days: show full date
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }

    /// Truncated transaction ID showing the first 8 and last 8 characters.
    ///
    /// Example: `"a1b2c3d4...w5x6y7z8"`.
    var truncatedTxid: String {
        guard txid.count > 16 else { return txid }
        let start = txid.prefix(8)
        let end = txid.suffix(8)
        return "\(start)...\(end)"
    }

    /// Amount in satoshis as an integer.
    var amountInSats: Int64 {
        let satoshis = amount * Decimal(100_000_000)
        return NSDecimalNumber(decimal: satoshis).int64Value
    }

    /// Fee in satoshis as an integer.
    var feeInSats: Int64 {
        let satoshis = fee * Decimal(100_000_000)
        return NSDecimalNumber(decimal: satoshis).int64Value
    }

    /// Fee rate in satoshis per virtual byte, or `nil` if virtual size is unknown.
    var feeRate: Decimal? {
        guard let vSize = virtualSize, vSize > 0 else { return nil }
        let feeSats = fee * Decimal(100_000_000)
        return feeSats / Decimal(vSize)
    }

    /// A confirmation description suitable for display in the UI.
    var confirmationDescription: String {
        switch confirmations {
        case 0:
            return "Unconfirmed"
        case 1:
            return "1 confirmation"
        case 2...5:
            return "\(confirmations) confirmations"
        default:
            return "\(confirmations)+ confirmations"
        }
    }
}
