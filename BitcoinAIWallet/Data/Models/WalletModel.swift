// MARK: - WalletModel.swift
// Bitcoin AI Wallet
//
// Domain model representing the wallet's aggregate state.
// Encapsulates balance information, address derivation indices,
// and metadata used throughout the UI and persistence layers.
//
// Platform: iOS 17.0+
// Framework: Foundation

import Foundation

// MARK: - WalletModel

/// Aggregate domain model for the user's Bitcoin wallet.
///
/// `WalletModel` is a value type that captures the wallet's current state
/// including balances (always stored as `Decimal` to avoid floating-point
/// precision loss), UTXO/transaction counts, and HD derivation indices.
struct WalletModel: Identifiable, Codable, Equatable {

    // MARK: - Properties

    /// Unique identifier for this wallet instance.
    let id: UUID

    /// User-facing display name for the wallet.
    var name: String

    /// Total balance (confirmed + unconfirmed) in BTC.
    var totalBalance: Decimal

    /// Confirmed balance in BTC.
    var confirmedBalance: Decimal

    /// Unconfirmed (pending) balance in BTC.
    var unconfirmedBalance: Decimal

    /// Number of unspent transaction outputs currently held.
    var utxoCount: Int

    /// Total number of transactions recorded for this wallet.
    var transactionCount: Int

    /// Timestamp of the last successful sync with the network.
    var lastUpdated: Date

    /// The preferred address type: `"segwit"` (BIP-84) or `"taproot"` (BIP-86).
    var addressType: String

    /// Current BIP-84/86 receive address derivation index.
    var currentReceiveIndex: UInt32

    /// Current BIP-84/86 change address derivation index.
    var currentChangeIndex: UInt32

    // MARK: - Static Defaults

    /// An empty wallet suitable for initial state or previews.
    static let empty = WalletModel(
        id: UUID(),
        name: "Main Wallet",
        totalBalance: 0,
        confirmedBalance: 0,
        unconfirmedBalance: 0,
        utxoCount: 0,
        transactionCount: 0,
        lastUpdated: Date(),
        addressType: "segwit",
        currentReceiveIndex: 0,
        currentChangeIndex: 0
    )

    // MARK: - Computed Properties

    /// Balance formatted as a BTC string with up to 8 decimal places.
    ///
    /// Examples: `"0.00000000"`, `"1.23456789"`, `"21000000.00000000"`.
    var formattedBalance: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 8
        formatter.maximumFractionDigits = 8
        formatter.groupingSeparator = ","
        formatter.decimalSeparator = "."
        return formatter.string(from: totalBalance as NSDecimalNumber) ?? "0.00000000"
    }

    /// Total balance converted to satoshis (1 BTC = 100,000,000 sats).
    ///
    /// Uses `Decimal` arithmetic to preserve precision before truncating
    /// to an `Int64` representation.
    var balanceInSats: Int64 {
        let satoshis = totalBalance * Decimal(100_000_000)
        return NSDecimalNumber(decimal: satoshis).int64Value
    }

    /// Human-readable time since last sync.
    var timeSinceLastUpdate: String {
        let interval = Date().timeIntervalSince(lastUpdated)
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }

    /// Whether the wallet has any balance at all.
    var hasBalance: Bool {
        totalBalance > 0
    }

    /// Whether there is any unconfirmed balance pending.
    var hasPendingBalance: Bool {
        unconfirmedBalance > 0
    }
}
