// MARK: - AnkrAPI.swift
// Bitcoin AI Wallet
//
// Client for the Ankr multichain JSON-RPC API.
// Used as a secondary/backup data source alongside the primary Blockbook
// integration. All calls follow the JSON-RPC 2.0 specification:
//   POST body: {"jsonrpc":"2.0","method":"<method>","params":{...},"id":<id>}
//
// Platform: iOS 17.0+
// Dependencies: Foundation, os.log

import Foundation
import os.log

// MARK: - AnkrAPIProtocol

/// Abstraction over Ankr RPC operations.
///
/// Conform to this protocol in test doubles to avoid hitting the
/// real Ankr endpoint during unit tests.
protocol AnkrAPIProtocol: Sendable {

    /// Fetch the balance for a Bitcoin address.
    ///
    /// - Parameter address: A Bitcoin address (legacy, SegWit, or Taproot).
    /// - Returns: An ``AnkrBalanceResponse`` containing the aggregated balance and per-asset breakdown.
    /// - Throws: ``APIError`` or ``AnkrRPCError`` on failure.
    func getBalance(address: String) async throws -> AnkrBalanceResponse

    /// Fetch paginated transaction history for a Bitcoin address.
    ///
    /// - Parameters:
    ///   - address: A Bitcoin address.
    ///   - pageSize: Maximum number of transactions per page.
    ///   - pageToken: Opaque continuation token for fetching the next page. Pass `nil` for the first page.
    /// - Returns: An ``AnkrTransactionsResponse`` containing the transactions and an optional next-page token.
    /// - Throws: ``APIError`` or ``AnkrRPCError`` on failure.
    func getTransactions(address: String, pageSize: Int, pageToken: String?) async throws -> AnkrTransactionsResponse

    /// Broadcast a signed raw transaction through Ankr.
    ///
    /// - Parameter hex: The hex-encoded signed transaction.
    /// - Returns: An ``AnkrBroadcastResponse`` containing the resulting TXID.
    /// - Throws: ``APIError`` or ``AnkrRPCError`` on failure.
    func broadcastTransaction(hex: String) async throws -> AnkrBroadcastResponse

    /// Retrieve high-level blockchain statistics for Bitcoin.
    ///
    /// - Returns: An ``AnkrBlockchainStats`` with block height and transaction count.
    /// - Throws: ``APIError`` or ``AnkrRPCError`` on failure.
    func getBlockchainStats() async throws -> AnkrBlockchainStats
}

// MARK: - AnkrAPI

/// Production implementation of ``AnkrAPIProtocol``.
///
/// Communicates with the Ankr multichain JSON-RPC gateway. Each public
/// method constructs a JSON-RPC 2.0 request, sends it via ``HTTPClientProtocol``,
/// validates the HTTP response, and decodes the JSON-RPC envelope.
///
/// ```swift
/// let api = AnkrAPI()
/// let balance = try await api.getBalance(address: "bc1q...")
/// ```
final class AnkrAPI: AnkrAPIProtocol, @unchecked Sendable {

    // MARK: - Properties

    /// The HTTP transport used for all requests.
    private let httpClient: HTTPClientProtocol

    /// Base URL for the Ankr multichain JSON-RPC endpoint.
    private let baseURL: URL

    /// Logger for request/response diagnostics.
    private let logger = Logger(subsystem: "com.bitcoinai.wallet", category: "AnkrAPI")

    /// Thread-safe request ID counter.
    ///
    /// Each JSON-RPC call increments this value to ensure unique IDs
    /// across concurrent requests within the same `AnkrAPI` instance.
    private let requestIDLock = NSLock()
    private var _nextRequestID: Int = 1

    /// The blockchain identifier used in all Ankr requests for Bitcoin.
    private let blockchain = "btc"

    // MARK: - Initialization

    /// Create an Ankr API client.
    ///
    /// - Parameters:
    ///   - httpClient: The HTTP transport. Defaults to the shared singleton.
    ///   - baseURL: The Ankr RPC gateway URL. Defaults to the public multichain endpoint.
    init(
        httpClient: HTTPClientProtocol = HTTPClient.shared,
        // swiftlint:disable:next force_unwrapping
        baseURL: URL = URL(string: "https://rpc.ankr.com/multichain")! // Compile-time constant, always valid
    ) {
        self.httpClient = httpClient
        self.baseURL = baseURL
    }

    // MARK: - Public API

    /// Fetch the balance for a Bitcoin address via `ankr_getAccountBalance`.
    ///
    /// - Parameter address: A Bitcoin address (legacy, SegWit, or Taproot).
    /// - Returns: An ``AnkrBalanceResponse`` with the balance breakdown.
    /// - Throws: ``APIError`` or ``AnkrRPCError``.
    func getBalance(address: String) async throws -> AnkrBalanceResponse {
        logger.debug("Fetching balance for address: \(address.prefix(10))...")

        let params: [String: Any] = [
            "blockchain": [blockchain],
            "walletAddress": address
        ]

        let data = try await executeRPC(method: "ankr_getAccountBalance", params: params)
        let envelope = try decodeResponse(AnkrBalanceResponse.self, from: data)
        return envelope
    }

    /// Fetch paginated transaction history via `ankr_getTransactionsByAddress`.
    ///
    /// - Parameters:
    ///   - address: A Bitcoin address.
    ///   - pageSize: Maximum number of transactions to return (1...100).
    ///   - pageToken: Continuation token for the next page. `nil` for the first request.
    /// - Returns: An ``AnkrTransactionsResponse`` with transactions and an optional next-page token.
    /// - Throws: ``APIError`` or ``AnkrRPCError``.
    func getTransactions(
        address: String,
        pageSize: Int = 10,
        pageToken: String? = nil
    ) async throws -> AnkrTransactionsResponse {
        logger.debug("Fetching transactions for address: \(address.prefix(10))... (pageSize=\(pageSize))")

        let clampedPageSize = min(max(pageSize, 1), 100)

        var params: [String: Any] = [
            "blockchain": [blockchain],
            "address": [address],
            "pageSize": clampedPageSize,
            "descOrder": true
        ]

        if let pageToken = pageToken, !pageToken.isEmpty {
            params["pageToken"] = pageToken
        }

        let data = try await executeRPC(method: "ankr_getTransactionsByAddress", params: params)
        let envelope = try decodeResponse(AnkrTransactionsResponse.self, from: data)
        return envelope
    }

    /// Broadcast a signed raw transaction via `ankr_sendRawTransaction`.
    ///
    /// - Parameter hex: The hex-encoded signed transaction bytes.
    /// - Returns: An ``AnkrBroadcastResponse`` containing the TXID on success.
    /// - Throws: ``APIError`` or ``AnkrRPCError``.
    func broadcastTransaction(hex: String) async throws -> AnkrBroadcastResponse {
        logger.info("Broadcasting transaction (\(hex.count / 2) bytes)")

        let params: [String: Any] = [
            "blockchain": blockchain,
            "rawTransaction": hex
        ]

        let data = try await executeRPC(method: "ankr_sendRawTransaction", params: params)
        let envelope = try decodeResponse(AnkrBroadcastResponse.self, from: data)

        if let txHash = envelope.txHash {
            logger.info("Transaction broadcast succeeded: \(txHash.prefix(16))...")
        }

        return envelope
    }

    /// Retrieve high-level blockchain statistics via `ankr_getBlockchainStats`.
    ///
    /// - Returns: An ``AnkrBlockchainStats`` containing block height and transaction count.
    /// - Throws: ``APIError`` or ``AnkrRPCError``.
    func getBlockchainStats() async throws -> AnkrBlockchainStats {
        logger.debug("Fetching blockchain stats for \(self.blockchain)")

        let params: [String: Any] = [
            "blockchain": blockchain
        ]

        let data = try await executeRPC(method: "ankr_getBlockchainStats", params: params)
        let envelope = try decodeResponse(AnkrBlockchainStats.self, from: data)
        return envelope
    }

    // MARK: - Private Helpers

    /// Generate a unique, monotonically-increasing JSON-RPC request ID.
    ///
    /// - Returns: The next available integer ID.
    private func nextRequestID() -> Int {
        requestIDLock.lock()
        defer { requestIDLock.unlock() }
        let id = _nextRequestID
        _nextRequestID += 1
        return id
    }

    /// Build a JSON-RPC 2.0 request body.
    ///
    /// - Parameters:
    ///   - method: The RPC method name (e.g. `"ankr_getAccountBalance"`).
    ///   - params: The method parameters as a dictionary.
    /// - Returns: Serialized JSON `Data`, or `nil` if serialization fails.
    private func buildRPCRequest(method: String, params: [String: Any]) -> Data? {
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params,
            "id": nextRequestID()
        ]

        guard JSONSerialization.isValidJSONObject(body) else {
            logger.error("Invalid JSON-RPC body for method: \(method)")
            return nil
        }

        do {
            return try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            logger.error("Failed to serialize JSON-RPC body: \(error.localizedDescription)")
            return nil
        }
    }

    /// Execute a JSON-RPC call: serialize the request, POST it, validate the HTTP response.
    ///
    /// - Parameters:
    ///   - method: The RPC method name.
    ///   - params: The method parameters.
    /// - Returns: The raw response `Data`.
    /// - Throws: ``APIError`` for transport or HTTP-level failures.
    private func executeRPC(method: String, params: [String: Any]) async throws -> Data {
        guard let body = buildRPCRequest(method: method, params: params) else {
            throw APIError.invalidRequest
        }

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let (data, httpResponse) = try await httpClient.execute(request)

        // Validate the HTTP status code using the shared ResponseParser
        try ResponseParser.validate(response: httpResponse, data: data)

        return data
    }

    /// Decode an Ankr JSON-RPC response envelope and extract the result.
    ///
    /// If the envelope carries an ``AnkrRPCError``, it is thrown directly.
    /// If the `result` field is missing, an ``APIError.invalidResponse`` is thrown.
    ///
    /// - Parameters:
    ///   - type: The expected `Decodable` result type.
    ///   - data: The raw response body data.
    /// - Returns: The decoded result of type `T`.
    /// - Throws: ``AnkrRPCError`` for server-side RPC errors, ``APIError`` for decoding or structural failures.
    private func decodeResponse<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let envelope: AnkrRPCResponse<T>

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .useDefaultKeys
            envelope = try decoder.decode(AnkrRPCResponse<T>.self, from: data)
        } catch {
            logger.error("Failed to decode Ankr RPC envelope: \(error.localizedDescription)")
            throw APIError.decodingError(underlying: error)
        }

        // Check for RPC-level error
        if let rpcError = envelope.error {
            logger.error("Ankr RPC error \(rpcError.code): \(rpcError.message)")
            throw rpcError
        }

        // Extract the result
        guard let result = envelope.result else {
            logger.error("Ankr RPC response has neither result nor error")
            throw APIError.invalidResponse
        }

        return result
    }
}
