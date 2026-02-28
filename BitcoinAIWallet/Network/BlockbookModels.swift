// MARK: - BlockbookModels.swift
// Bitcoin AI Wallet
//
// Codable response models for every Blockbook REST API endpoint.
// All monetary values are represented as `String` in satoshi or BTC
// to avoid floating-point precision issues; convert to `Decimal` at
// the call-site when arithmetic is required.
//
// Platform: iOS 17.0+
// Dependencies: Foundation

import Foundation

// MARK: - Address

/// Response for the `/api/v2/address/<address>` endpoint.
///
/// Contains balance summaries and, depending on the `details` query parameter,
/// a paginated list of transactions associated with the address.
struct BlockbookAddress: Codable, Sendable {

    /// The queried Bitcoin address.
    let address: String

    /// Confirmed balance in satoshis.
    let balance: String

    /// Total amount ever received in satoshis.
    let totalReceived: String

    /// Total amount ever sent in satoshis.
    let totalSent: String

    /// Unconfirmed (mempool) balance in satoshis. May be negative.
    let unconfirmedBalance: String

    /// Number of unconfirmed transactions.
    let unconfirmedTxs: Int

    /// Total number of transactions involving this address.
    let txs: Int

    /// Paginated list of transactions. Present when `details=txs` or `details=txslight`.
    let transactions: [BlockbookTransaction]?

    /// Current page number (1-indexed).
    let page: Int?

    /// Total number of pages available.
    let totalPages: Int?

    /// Number of items returned on this page.
    let itemsOnPage: Int?
}

// MARK: - UTXO

/// A single unspent transaction output from the `/api/v2/utxo/<address>` endpoint.
///
/// Used for coin selection when building new transactions.
struct BlockbookUTXO: Codable, Sendable {

    /// Transaction hash that created this output.
    let txid: String

    /// Output index within the transaction.
    let vout: Int

    /// Value of the output in satoshis.
    let value: String

    /// Number of confirmations. Zero means the UTXO is in the mempool.
    let confirmations: Int

    /// Block height at which the creating transaction was confirmed.
    let height: Int?

    /// Whether this output is a coinbase (mining reward) output.
    let coinbase: Bool?

    /// Lock time of the creating transaction, if relevant.
    let lockTime: Int?

    /// The address that owns this UTXO.
    let address: String?

    /// BIP-44 derivation path (e.g. `"m/84'/0'/0'/0/3"`), present for xpub queries.
    let path: String?
}

// MARK: - Transaction

/// Full transaction data from the `/api/v2/tx/<txid>` endpoint.
///
/// Includes inputs, outputs, confirmation status, and size information.
struct BlockbookTransaction: Codable, Sendable {

    /// The transaction hash (TXID).
    let txid: String

    /// Transaction version number.
    let version: Int

    /// Transaction inputs.
    let vin: [BlockbookVin]

    /// Transaction outputs.
    let vout: [BlockbookVout]

    /// Hash of the block containing this transaction. `nil` if unconfirmed.
    let blockHash: String?

    /// Height of the block containing this transaction. `nil` or `-1` if unconfirmed.
    let blockHeight: Int?

    /// Number of confirmations. Zero for mempool transactions.
    let confirmations: Int

    /// Unix timestamp of the block (or first-seen time for unconfirmed).
    let blockTime: Int

    /// Total output value in satoshis.
    let value: String

    /// Total input value in satoshis.
    let valueIn: String

    /// Transaction fee in satoshis.
    let fees: String

    /// Raw transaction hex. Only present when explicitly requested.
    let hex: String?

    /// Transaction size in bytes.
    let size: Int?

    /// Virtual size in vBytes (accounts for SegWit discount).
    let vsize: Int?
}

// MARK: - Transaction Input

/// A single transaction input (vin).
struct BlockbookVin: Codable, Sendable {

    /// TXID of the output being spent.
    let txid: String

    /// Output index being spent.
    let vout: Int?

    /// Input sequence number.
    let sequence: Int

    /// Index of this input within the transaction.
    let n: Int

    /// Addresses associated with this input.
    let addresses: [String]?

    /// Whether the addresses field contains valid addresses.
    let isAddress: Bool

    /// Value of the spent output in satoshis.
    let value: String?

    /// ScriptSig or witness hex data.
    let hex: String?
}

// MARK: - Transaction Output

/// A single transaction output (vout).
struct BlockbookVout: Codable, Sendable {

    /// Output value in satoshis.
    let value: String

    /// Index of this output within the transaction.
    let n: Int

    /// ScriptPubKey hex data.
    let hex: String?

    /// Addresses associated with this output.
    let addresses: [String]?

    /// Whether the addresses field contains valid addresses.
    let isAddress: Bool

    /// Whether this output has already been spent by another transaction.
    let spent: Bool?
}

// MARK: - Fee Estimate

/// Response from the `/api/v2/estimatefee/<blocks>` endpoint.
///
/// The `result` field contains the estimated fee rate in BTC per kilobyte.
/// Convert to sat/vByte: `Decimal(string: result)! * 100_000` (BTC/kB to sat/vB).
struct BlockbookFeeEstimate: Codable, Sendable {

    /// Estimated fee rate in BTC per kilobyte (e.g. `"0.00012345"`).
    let result: String
}

// MARK: - Send Transaction Result

/// Response from the `/api/v2/sendtx/` endpoint after broadcasting a transaction.
///
/// On success, `result` contains the TXID of the broadcast transaction.
struct BlockbookSendTxResult: Codable, Sendable {

    /// The transaction ID of the successfully broadcast transaction.
    let result: String
}

// MARK: - Extended Public Key Info

/// Response for the `/api/v2/xpub/<xpub>` endpoint.
///
/// Provides aggregate balance and token (address) information derived
/// from an extended public key.
struct BlockbookXpubInfo: Codable, Sendable {

    /// The queried xpub/ypub/zpub string.
    let address: String

    /// Aggregate confirmed balance in satoshis across all derived addresses.
    let balance: String

    /// Total amount ever received in satoshis across all derived addresses.
    let totalReceived: String

    /// Total amount ever sent in satoshis across all derived addresses.
    let totalSent: String

    /// Aggregate unconfirmed balance in satoshis.
    let unconfirmedBalance: String

    /// Number of unconfirmed transactions across all derived addresses.
    let unconfirmedTxs: Int

    /// Total number of transactions across all derived addresses.
    let txs: Int

    /// Paginated list of transactions, if requested via `details`.
    let transactions: [BlockbookTransaction]?

    /// Number of derived addresses that have been used (received at least one transaction).
    let usedTokens: Int?

    /// List of derived address tokens with balance and transfer information.
    let tokens: [BlockbookToken]?
}

// MARK: - Token (Derived Address)

/// Represents a single derived address from an xpub query.
///
/// In Blockbook terminology, "token" refers to a derived HD wallet address,
/// not a separate token protocol.
struct BlockbookToken: Codable, Sendable {

    /// Token type identifier (e.g. `"XPUBAddress"`).
    let type: String

    /// The derived Bitcoin address.
    let name: String

    /// BIP-44 derivation path (e.g. `"m/84'/0'/0'/0/0"`).
    let path: String

    /// Number of transactions involving this address.
    let transfers: Int

    /// Decimal precision. Typically `8` for Bitcoin.
    let decimals: Int?

    /// Current balance in satoshis.
    let balance: String?

    /// Total received in satoshis.
    let totalReceived: String?

    /// Total sent in satoshis.
    let totalSent: String?
}

// MARK: - Block

/// Response from the `/api/v2/block/<hashOrHeight>` endpoint.
///
/// Provides basic block metadata without the full list of transactions.
struct BlockbookBlock: Codable, Sendable {

    /// Block hash (hex string).
    let hash: String

    /// Block height.
    let height: Int

    /// Number of confirmations since this block was mined.
    let confirmations: Int

    /// Block size in bytes.
    let size: Int

    /// Block timestamp as Unix epoch seconds.
    let time: Int

    /// Number of transactions included in this block.
    let txCount: Int
}

// MARK: - Balance History

/// A single data point from the `/api/v2/balancehistory/<address>` endpoint.
///
/// Represents aggregated balance changes over a time interval.
struct BlockbookBalanceHistory: Codable, Sendable {

    /// Unix timestamp marking the start of this interval.
    let time: Int

    /// Number of transactions within this interval.
    let txs: Int

    /// Total received in satoshis during this interval.
    let received: String

    /// Total sent in satoshis during this interval.
    let sent: String

    /// Amount sent to the same address (self-transfer) in satoshis.
    let sentToSelf: String?
}

// MARK: - Blockbook Error Response

/// Error response body returned by the Blockbook API on failure.
///
/// Used internally to parse server error messages and surface them
/// through ``BlockbookError``.
struct BlockbookErrorResponse: Codable, Sendable {

    /// The error message from the server.
    let error: String
}
