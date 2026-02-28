// MARK: - BlockbookEndpoints.swift
// Bitcoin AI Wallet
//
// Defines all Blockbook API endpoint paths, HTTP methods, and query parameters.
// Each case maps to a single REST endpoint on the Blockbook server.
//
// Platform: iOS 17.0+
// Dependencies: Foundation

import Foundation

// MARK: - HTTPMethod

/// HTTP request methods used by the Blockbook API.
enum HTTPMethod: String, Sendable {
    case get  = "GET"
    case post = "POST"
}

// MARK: - BlockbookEndpoint

/// Enumerates every Blockbook REST API endpoint the app can call.
///
/// Each case carries the parameters needed to build the full request URL.
/// Use ``path``, ``method``, and ``queryItems`` to construct a `URLRequest`.
///
/// ```swift
/// let endpoint = BlockbookEndpoint.address("bc1q...", details: "txs", page: 1, pageSize: 25)
/// print(endpoint.path)       // "/api/v2/address/bc1q..."
/// print(endpoint.method)     // .get
/// ```
enum BlockbookEndpoint: Sendable {

    // MARK: - Cases

    /// Fetch address information.
    /// - Parameters:
    ///   - address: Bitcoin address string.
    ///   - details: Detail level (`"basic"`, `"tokens"`, `"tokenBalances"`, `"txids"`, `"txslight"`, `"txs"`).
    ///   - page: Page number for paginated transaction results.
    ///   - pageSize: Number of transactions per page.
    case address(String, details: String?, page: Int?, pageSize: Int?)

    /// Fetch unspent transaction outputs for an address.
    /// - Parameter address: Bitcoin address string.
    case utxo(String)

    /// Fetch a single transaction by its ID.
    /// - Parameter txid: The transaction hash.
    case transaction(String)

    /// Fetch extended public key (xpub/ypub/zpub) information.
    /// - Parameters:
    ///   - xpub: The extended public key string.
    ///   - details: Detail level (same options as ``address``).
    ///   - tokens: Token filter (`"used"`, `"nonzero"`, `"derived"`).
    ///   - gap: Address gap limit for discovery.
    case xpub(String, details: String?, tokens: String?, gap: Int?)

    /// Estimate the fee rate for confirmation within a target number of blocks.
    /// - Parameter blocks: Target number of blocks for confirmation.
    case estimateFee(blocks: Int)

    /// Broadcast a signed raw transaction to the network.
    case sendTransaction

    /// Fetch block information by hash or height.
    /// - Parameter hashOrHeight: Block hash (hex) or block height (numeric string).
    case block(String)

    /// Fetch balance history for an address over a time range.
    /// - Parameters:
    ///   - address: Bitcoin address string.
    ///   - from: Unix timestamp for the start of the range.
    ///   - to: Unix timestamp for the end of the range.
    ///   - groupBy: Grouping interval in seconds (e.g. 86400 for daily).
    case balanceHistory(String, from: Int?, to: Int?, groupBy: Int?)

    // MARK: - Path

    /// The URL path component for this endpoint, relative to the Blockbook base URL.
    var path: String {
        switch self {
        case .address(let address, _, _, _):
            return "/api/v2/address/\(address)"

        case .utxo(let address):
            return "/api/v2/utxo/\(address)"

        case .transaction(let txid):
            return "/api/v2/tx/\(txid)"

        case .xpub(let xpub, _, _, _):
            return "/api/v2/xpub/\(xpub)"

        case .estimateFee(let blocks):
            return "/api/v2/estimatefee/\(blocks)"

        case .sendTransaction:
            return "/api/v2/sendtx/"

        case .block(let hashOrHeight):
            return "/api/v2/block/\(hashOrHeight)"

        case .balanceHistory(let address, _, _, _):
            return "/api/v2/balancehistory/\(address)"
        }
    }

    // MARK: - HTTP Method

    /// The HTTP method required by this endpoint.
    var method: HTTPMethod {
        switch self {
        case .sendTransaction:
            return .post
        default:
            return .get
        }
    }

    // MARK: - Query Items

    /// Optional query string parameters for this endpoint.
    /// Returns `nil` when no query parameters are needed.
    var queryItems: [URLQueryItem]? {
        switch self {
        case .address(_, let details, let page, let pageSize):
            var items: [URLQueryItem] = []
            if let details { items.append(URLQueryItem(name: "details", value: details)) }
            if let page { items.append(URLQueryItem(name: "page", value: String(page))) }
            if let pageSize { items.append(URLQueryItem(name: "pageSize", value: String(pageSize))) }
            return items.isEmpty ? nil : items

        case .xpub(_, let details, let tokens, let gap):
            var items: [URLQueryItem] = []
            if let details { items.append(URLQueryItem(name: "details", value: details)) }
            if let tokens { items.append(URLQueryItem(name: "tokens", value: tokens)) }
            if let gap { items.append(URLQueryItem(name: "gap", value: String(gap))) }
            return items.isEmpty ? nil : items

        case .balanceHistory(_, let from, let to, let groupBy):
            var items: [URLQueryItem] = []
            if let from { items.append(URLQueryItem(name: "from", value: String(from))) }
            if let to { items.append(URLQueryItem(name: "to", value: String(to))) }
            if let groupBy { items.append(URLQueryItem(name: "groupBy", value: String(groupBy))) }
            return items.isEmpty ? nil : items

        case .utxo, .transaction, .estimateFee, .sendTransaction, .block:
            return nil
        }
    }
}
