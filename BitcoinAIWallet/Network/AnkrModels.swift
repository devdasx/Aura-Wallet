// MARK: - AnkrModels.swift
// Bitcoin AI Wallet
//
// Codable response models for the Ankr multichain JSON-RPC API.
// Ankr serves as a secondary/backup data source alongside Blockbook.
// All monetary values are represented as `String` to avoid floating-point
// precision issues; convert to `Decimal` at the call-site for arithmetic.
//
// Platform: iOS 17.0+
// Dependencies: Foundation

import Foundation

// MARK: - JSON-RPC Envelope

/// Generic wrapper for an Ankr JSON-RPC 2.0 response.
///
/// The `T` parameter represents the shape of the `result` field, which
/// varies by method. When the server returns an error instead of a result,
/// the `error` field is populated and `result` is `nil`.
///
/// ```
/// {
///   "jsonrpc": "2.0",
///   "id": 1,
///   "result": { ... }
/// }
/// ```
struct AnkrRPCResponse<T: Decodable>: Decodable {

    /// JSON-RPC protocol version (always `"2.0"`).
    let jsonrpc: String

    /// Request identifier echoed back by the server.
    let id: Int

    /// The successful result payload. `nil` when the response carries an error.
    let result: T?

    /// The error payload. `nil` when the call succeeded.
    let error: AnkrRPCError?
}

// MARK: - JSON-RPC Error

/// Error payload returned inside an Ankr JSON-RPC response.
///
/// Conforms to `Error` so it can be thrown directly when the RPC
/// call returns a server-side failure.
struct AnkrRPCError: Decodable, Error, LocalizedError, Sendable {

    /// Numeric error code defined by the JSON-RPC spec or the Ankr backend.
    let code: Int

    /// Human-readable error description from the server.
    let message: String

    /// Optional additional error data (free-form string).
    let data: String?

    // MARK: - LocalizedError

    var errorDescription: String? {
        if let data = data, !data.isEmpty {
            return "Ankr RPC error \(code): \(message) (\(data))"
        }
        return "Ankr RPC error \(code): \(message)"
    }
}

// MARK: - Balance Response

/// Result payload for the `ankr_getAccountBalance` method.
///
/// Contains the aggregate USD balance and a per-asset breakdown
/// for the queried address across the requested blockchains.
struct AnkrBalanceResponse: Decodable, Sendable {

    /// Total balance across all assets expressed in USD (e.g. `"1234.56"`).
    let totalBalanceUsd: String?

    /// Individual asset balances. `nil` or empty when the address has no holdings.
    let assets: [AnkrAssetBalance]?
}

// MARK: - Asset Balance

/// A single asset balance entry returned inside ``AnkrBalanceResponse``.
struct AnkrAssetBalance: Decodable, Sendable {

    /// Blockchain identifier (e.g. `"btc"`, `"eth"`).
    let blockchain: String

    /// Human-readable token name (e.g. `"Bitcoin"`).
    let tokenName: String

    /// Token ticker symbol (e.g. `"BTC"`).
    let tokenSymbol: String

    /// Native balance as a decimal string (e.g. `"0.01234567"`).
    let balance: String

    /// Balance value in USD (e.g. `"1234.56"`). May be `nil` if pricing is unavailable.
    let balanceUsd: String?

    /// Per-unit price in USD (e.g. `"65000.00"`). May be `nil` if pricing is unavailable.
    let tokenPrice: String?
}

// MARK: - Transactions Response

/// Result payload for the `ankr_getTransactionsByAddress` method.
///
/// Contains a page of transactions and an optional continuation token
/// for fetching the next page.
struct AnkrTransactionsResponse: Decodable, Sendable {

    /// The list of transactions on this page. `nil` or empty when none exist.
    let transactions: [AnkrTransaction]?

    /// Opaque token used to fetch the next page of results. `nil` when this is the last page.
    let nextPageToken: String?
}

// MARK: - Transaction

/// A single transaction record returned by the Ankr transactions endpoint.
struct AnkrTransaction: Decodable, Sendable {

    /// Transaction hash (TXID).
    let hash: String

    /// Sender address.
    let from: String

    /// Recipient address.
    let to: String

    /// Transfer value as a decimal string in the native currency unit.
    let value: String

    /// Block number containing this transaction (as a string). `nil` if unconfirmed.
    let blockNumber: String?

    /// Unix timestamp of the block as a string (e.g. `"1700000000"`). `nil` if unconfirmed.
    let timestamp: String?

    /// Transaction status (`"1"` = success, `"0"` = failed). `nil` if unknown.
    let status: String?

    /// Amount of gas consumed by this transaction. `nil` for non-EVM chains.
    let gasUsed: String?

    /// Gas price in the chain's smallest unit. `nil` for non-EVM chains.
    let gasPrice: String?
}

// MARK: - Broadcast Response

/// Result payload after broadcasting a signed transaction through Ankr.
struct AnkrBroadcastResponse: Decodable, Sendable {

    /// The transaction hash of the successfully broadcast transaction.
    /// `nil` if the broadcast failed.
    let txHash: String?
}

// MARK: - Blockchain Stats

/// Result payload for the `ankr_getBlockchainStats` method.
///
/// Provides high-level metrics about a specific blockchain.
struct AnkrBlockchainStats: Decodable, Sendable {

    /// Blockchain identifier (e.g. `"btc"`). `nil` if not provided.
    let blockchain: String?

    /// Total number of transactions ever recorded on this chain. `nil` if unavailable.
    let totalTransactionsCount: Int?

    /// Height of the most recently confirmed block. `nil` if unavailable.
    let lastBlockNumber: Int?
}
