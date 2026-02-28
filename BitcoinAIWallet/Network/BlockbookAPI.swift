// MARK: - BlockbookAPI.swift
// Bitcoin AI Wallet
//
// Production client for interacting with the Blockbook REST API.
// All blockchain data fetching -- address info, UTXOs, transactions,
// fee estimation, broadcasting -- flows through this client.
//
// Built on top of HTTPClient and RequestBuilder, this layer adds
// Blockbook-specific request construction, domain error mapping,
// and strongly-typed response decoding.
//
// Platform: iOS 17.0+
// Dependencies: Foundation
// Concurrency: Swift Concurrency (async/await)

import Foundation
import os.log

// MARK: - BlockbookAPIProtocol

/// Public contract for all Blockbook API operations.
///
/// Conform to this protocol to provide mock or alternative implementations
/// for testing and SwiftUI previews.
///
/// ```swift
/// // Production
/// let api: BlockbookAPIProtocol = BlockbookAPI()
///
/// // Testing
/// let api: BlockbookAPIProtocol = MockBlockbookAPI()
/// ```
protocol BlockbookAPIProtocol: Sendable {

    /// Fetch address information including balance and optional transaction history.
    ///
    /// - Parameters:
    ///   - address: A valid Bitcoin address (any format: legacy, SegWit, Taproot).
    ///   - details: Detail level. Options: `"basic"`, `"tokens"`, `"tokenBalances"`,
    ///     `"txids"`, `"txslight"`, `"txs"`. Defaults to `nil` (basic).
    ///   - page: Page number for paginated results (1-indexed).
    ///   - pageSize: Number of transactions per page.
    /// - Returns: A ``BlockbookAddress`` with balance and optional transaction data.
    /// - Throws: ``BlockbookError`` on failure.
    func getAddress(
        _ address: String,
        details: String?,
        page: Int?,
        pageSize: Int?
    ) async throws -> BlockbookAddress

    /// Fetch all unspent transaction outputs (UTXOs) for an address.
    ///
    /// Returns an empty array if the address has no unspent outputs.
    ///
    /// - Parameter address: A valid Bitcoin address.
    /// - Returns: An array of ``BlockbookUTXO`` representing spendable outputs.
    /// - Throws: ``BlockbookError`` on failure.
    func getUTXOs(for address: String) async throws -> [BlockbookUTXO]

    /// Fetch full details of a single transaction by its ID.
    ///
    /// - Parameter txid: The transaction hash (64-character hex string).
    /// - Returns: A ``BlockbookTransaction`` with inputs, outputs, and confirmation data.
    /// - Throws: ``BlockbookError/transactionNotFound`` if the TXID does not exist.
    func getTransaction(_ txid: String) async throws -> BlockbookTransaction

    /// Fetch aggregate information for an extended public key (xpub/ypub/zpub).
    ///
    /// - Parameters:
    ///   - xpub: The extended public key string.
    ///   - details: Detail level for transactions.
    ///   - tokens: Token (address) filter (`"used"`, `"nonzero"`, `"derived"`).
    ///   - gap: Address gap limit for HD wallet discovery.
    /// - Returns: A ``BlockbookXpubInfo`` with aggregated balance and derived address details.
    /// - Throws: ``BlockbookError`` on failure.
    func getXpub(
        _ xpub: String,
        details: String?,
        tokens: String?,
        gap: Int?
    ) async throws -> BlockbookXpubInfo

    /// Estimate the fee rate needed for confirmation within a target number of blocks.
    ///
    /// - Parameter blocks: The target number of blocks (e.g. 1 for next-block, 6 for ~1 hour).
    /// - Returns: A ``BlockbookFeeEstimate`` containing the fee rate in BTC/kB.
    /// - Throws: ``BlockbookError`` on failure.
    func estimateFee(blocks: Int) async throws -> BlockbookFeeEstimate

    /// Broadcast a signed raw transaction to the Bitcoin network.
    ///
    /// - Parameter hex: The raw transaction hex string.
    /// - Returns: A ``BlockbookSendTxResult`` containing the broadcast TXID on success.
    /// - Throws: ``BlockbookError/broadcastFailed(message:)`` if the node rejects the transaction.
    func sendTransaction(hex: String) async throws -> BlockbookSendTxResult

    /// Fetch block metadata by hash or height.
    ///
    /// - Parameter blockHashOrHeight: A block hash (hex) or block height (numeric string).
    /// - Returns: A ``BlockbookBlock`` with hash, height, size, and transaction count.
    /// - Throws: ``BlockbookError`` on failure.
    func getBlockInfo(_ blockHashOrHeight: String) async throws -> BlockbookBlock

    /// Fetch historical balance changes for an address over a time range.
    ///
    /// - Parameters:
    ///   - address: A valid Bitcoin address.
    ///   - from: Start of the range as a Unix timestamp. Pass `nil` for no lower bound.
    ///   - to: End of the range as a Unix timestamp. Pass `nil` for no upper bound.
    ///   - groupBy: Grouping interval in seconds (e.g. `86400` for daily).
    /// - Returns: An array of ``BlockbookBalanceHistory`` data points.
    /// - Throws: ``BlockbookError`` on failure.
    func getBalanceHistory(
        _ address: String,
        from: Int?,
        to: Int?,
        groupBy: Int?
    ) async throws -> [BlockbookBalanceHistory]
}

// MARK: - BlockbookAPI

/// Production implementation of ``BlockbookAPIProtocol``.
///
/// Delegates HTTP execution to ``HTTPClientProtocol`` and uses
/// ``RequestBuilder`` to construct requests from ``BlockbookEndpoint``
/// definitions. Responses are decoded via ``ResponseParser`` and
/// transport-level ``APIError`` values are mapped to domain-specific
/// ``BlockbookError`` cases.
///
/// ```swift
/// let api = BlockbookAPI()
/// let address = try await api.getAddress("bc1q...", details: "txs", page: 1, pageSize: 25)
/// print(address.balance)  // e.g. "123456789" (satoshis)
/// ```
final class BlockbookAPI: BlockbookAPIProtocol, @unchecked Sendable {

    // MARK: - Properties

    /// The HTTP transport used to execute requests. Retry and backoff are
    /// handled internally by the `HTTPClient`.
    private let httpClient: HTTPClientProtocol

    /// API configuration providing base URLs and timeout settings.
    private let configuration: APIConfiguration

    /// Logger for Blockbook API-level diagnostics.
    private let logger = Logger(subsystem: "com.bitcoinai.wallet", category: "BlockbookAPI")

    // MARK: - Initialization

    /// Creates a new Blockbook API client.
    ///
    /// - Parameters:
    ///   - httpClient: The HTTP transport to use. Defaults to ``HTTPClient/shared``.
    ///   - configuration: API configuration. Defaults to ``APIConfiguration/default`` (mainnet).
    init(
        httpClient: HTTPClientProtocol = HTTPClient.shared,
        configuration: APIConfiguration = .default
    ) {
        self.httpClient = httpClient
        self.configuration = configuration
    }

    // MARK: - Address

    func getAddress(
        _ address: String,
        details: String? = nil,
        page: Int? = nil,
        pageSize: Int? = nil
    ) async throws -> BlockbookAddress {
        let endpoint = BlockbookEndpoint.address(
            address,
            details: details,
            page: page,
            pageSize: pageSize
        )
        return try await performRequest(endpoint: endpoint)
    }

    // MARK: - UTXOs

    func getUTXOs(for address: String) async throws -> [BlockbookUTXO] {
        let endpoint = BlockbookEndpoint.utxo(address)
        return try await performRequest(endpoint: endpoint)
    }

    // MARK: - Transaction

    func getTransaction(_ txid: String) async throws -> BlockbookTransaction {
        let endpoint = BlockbookEndpoint.transaction(txid)
        return try await performRequest(endpoint: endpoint)
    }

    // MARK: - Extended Public Key

    func getXpub(
        _ xpub: String,
        details: String? = nil,
        tokens: String? = nil,
        gap: Int? = nil
    ) async throws -> BlockbookXpubInfo {
        let endpoint = BlockbookEndpoint.xpub(
            xpub,
            details: details,
            tokens: tokens,
            gap: gap
        )
        return try await performRequest(endpoint: endpoint)
    }

    // MARK: - Fee Estimation

    func estimateFee(blocks: Int) async throws -> BlockbookFeeEstimate {
        let endpoint = BlockbookEndpoint.estimateFee(blocks: blocks)
        return try await performRequest(endpoint: endpoint)
    }

    // MARK: - Broadcast Transaction

    func sendTransaction(hex: String) async throws -> BlockbookSendTxResult {
        let endpoint = BlockbookEndpoint.sendTransaction

        do {
            let request = try RequestBuilder.build(
                baseURL: configuration.blockbookBaseURL,
                endpoint: endpoint,
                body: hex.data(using: .utf8),
                timeout: configuration.requestTimeout
            )

            let (data, _) = try await httpClient.execute(request)
            return try ResponseParser.parse(BlockbookSendTxResult.self, from: data)

        } catch let apiError as APIError {
            throw mapToBlockbookError(apiError, endpoint: endpoint)
        } catch let blockbookError as BlockbookError {
            throw blockbookError
        } catch {
            throw BlockbookError.networkError(underlying: error)
        }
    }

    // MARK: - Block Info

    func getBlockInfo(_ blockHashOrHeight: String) async throws -> BlockbookBlock {
        let endpoint = BlockbookEndpoint.block(blockHashOrHeight)
        return try await performRequest(endpoint: endpoint)
    }

    // MARK: - Balance History

    func getBalanceHistory(
        _ address: String,
        from: Int? = nil,
        to: Int? = nil,
        groupBy: Int? = nil
    ) async throws -> [BlockbookBalanceHistory] {
        let endpoint = BlockbookEndpoint.balanceHistory(
            address,
            from: from,
            to: to,
            groupBy: groupBy
        )
        return try await performRequest(endpoint: endpoint)
    }

    // MARK: - Request Execution

    /// Execute a Blockbook API request and decode the response.
    ///
    /// Builds a `URLRequest` from the endpoint definition, delegates execution
    /// to the `HTTPClient` (which handles retry and backoff), and maps any
    /// transport errors to ``BlockbookError``.
    ///
    /// - Parameter endpoint: The ``BlockbookEndpoint`` to call.
    /// - Returns: The decoded response of type `T`.
    /// - Throws: ``BlockbookError`` describing the failure.
    private func performRequest<T: Decodable>(
        endpoint: BlockbookEndpoint
    ) async throws -> T {
        do {
            let request = try RequestBuilder.build(
                baseURL: configuration.blockbookBaseURL,
                endpoint: endpoint,
                timeout: configuration.requestTimeout
            )

            let (data, _) = try await httpClient.execute(request)
            return try ResponseParser.parse(T.self, from: data)

        } catch let apiError as APIError {
            throw mapToBlockbookError(apiError, endpoint: endpoint)
        } catch let blockbookError as BlockbookError {
            throw blockbookError
        } catch {
            throw BlockbookError.networkError(underlying: error)
        }
    }

    // MARK: - Error Mapping

    /// Map an ``APIError`` to the most specific ``BlockbookError`` variant.
    ///
    /// Uses the endpoint context to provide more meaningful error messages.
    /// For example, a 404 on a transaction endpoint becomes
    /// ``BlockbookError/transactionNotFound``, while a 404 on an address
    /// endpoint becomes ``BlockbookError/invalidAddress``.
    ///
    /// - Parameters:
    ///   - apiError: The transport-level error from `HTTPClient`.
    ///   - endpoint: The originating endpoint for contextual mapping.
    /// - Returns: A ``BlockbookError`` instance.
    private func mapToBlockbookError(
        _ apiError: APIError,
        endpoint: BlockbookEndpoint
    ) -> BlockbookError {
        switch apiError {
        case .httpError(let statusCode, let message):
            return mapHTTPError(
                statusCode: statusCode,
                message: message ?? "Unknown error",
                endpoint: endpoint
            )

        case .timeout, .noConnection:
            return .networkError(underlying: apiError)

        case .serverUnavailable:
            return .serverError(
                statusCode: 503,
                message: "The Blockbook server is temporarily unavailable."
            )

        case .rateLimited:
            return .rateLimited

        case .decodingError(let underlying):
            logger.error("Decoding failed for \(endpoint.path): \(underlying.localizedDescription)")
            return .decodingError(
                message: "Failed to decode response from \(endpoint.path)",
                underlying: underlying
            )

        case .invalidURL, .invalidRequest:
            return .invalidAddress

        case .invalidResponse:
            return .decodingError(
                message: "The server returned an invalid response for \(endpoint.path)",
                underlying: apiError
            )

        case .networkError(let underlying):
            return .networkError(underlying: underlying)

        case .unauthorized:
            return .serverError(statusCode: 401, message: "Unauthorized access to Blockbook API.")

        case .webSocketDisconnected, .webSocketMessageParsingFailed:
            return .networkError(underlying: apiError)

        case .unknown(let message):
            return .serverError(statusCode: 0, message: message)
        }
    }

    /// Map an HTTP error status code to a context-aware ``BlockbookError``.
    ///
    /// - Parameters:
    ///   - statusCode: The HTTP status code.
    ///   - message: The error message from the server.
    ///   - endpoint: The originating endpoint.
    /// - Returns: A ``BlockbookError`` describing the failure.
    private func mapHTTPError(
        statusCode: Int,
        message: String,
        endpoint: BlockbookEndpoint
    ) -> BlockbookError {
        logger.error("HTTP \(statusCode) for \(endpoint.path): \(message)")

        switch statusCode {
        case 400:
            return mapErrorMessage(message, endpoint: endpoint)

        case 404:
            switch endpoint {
            case .transaction:
                return .transactionNotFound
            case .address, .utxo:
                return .invalidAddress
            default:
                return .serverError(statusCode: statusCode, message: message)
            }

        case 422:
            // Unprocessable entity -- typically a broadcast rejection
            if case .sendTransaction = endpoint {
                return .broadcastFailed(message: message)
            }
            return .serverError(statusCode: statusCode, message: message)

        case 429:
            return .rateLimited

        case 500 ..< 600:
            return .serverError(statusCode: statusCode, message: message)

        default:
            return .serverError(statusCode: statusCode, message: message)
        }
    }

    /// Map an error message string to the most specific ``BlockbookError`` variant.
    ///
    /// Examines common Blockbook error message patterns to determine the
    /// appropriate error case.
    ///
    /// - Parameters:
    ///   - message: The error message from the server.
    ///   - endpoint: The originating endpoint for context.
    /// - Returns: A ``BlockbookError`` matching the message semantics.
    private func mapErrorMessage(
        _ message: String,
        endpoint: BlockbookEndpoint
    ) -> BlockbookError {
        let lowered = message.lowercased()

        if lowered.contains("not found") {
            switch endpoint {
            case .transaction:
                return .transactionNotFound
            case .address, .utxo:
                return .invalidAddress
            default:
                return .serverError(statusCode: 404, message: message)
            }
        }

        if lowered.contains("invalid address") || lowered.contains("checksum") {
            return .invalidAddress
        }

        if lowered.contains("broadcast") || lowered.contains("rejected") ||
           lowered.contains("mempool") || lowered.contains("insufficient") ||
           lowered.contains("dust") || lowered.contains("too-long-mempool-chain") {
            return .broadcastFailed(message: message)
        }

        return .serverError(statusCode: 400, message: message)
    }
}

// MARK: - BlockbookError

/// Typed errors for Blockbook API failures.
///
/// Each case carries contextual information to help callers display
/// appropriate error messages or decide on recovery strategies.
///
/// ```swift
/// do {
///     let tx = try await api.getTransaction(txid)
/// } catch BlockbookError.transactionNotFound {
///     showAlert("Transaction not found on the blockchain.")
/// } catch let BlockbookError.networkError(underlying) {
///     showAlert("Network issue: \(underlying.localizedDescription)")
/// }
/// ```
enum BlockbookError: Error, LocalizedError, Sendable {

    /// The provided address is invalid or could not be found on the blockchain.
    case invalidAddress

    /// The requested transaction does not exist on the blockchain.
    case transactionNotFound

    /// The network rejected the broadcast transaction.
    /// - Parameter message: The rejection reason from the Bitcoin node
    ///   (e.g. "insufficient fee", "dust output", "mempool conflict").
    case broadcastFailed(message: String)

    /// The server returned an error HTTP status code.
    /// - Parameters:
    ///   - statusCode: The HTTP status code.
    ///   - message: The error message from the server.
    case serverError(statusCode: Int, message: String)

    /// The response body could not be decoded into the expected model.
    /// - Parameters:
    ///   - message: A description of what failed.
    ///   - underlying: The original decoding error.
    case decodingError(message: String, underlying: Error)

    /// A transport-level network error occurred (timeout, DNS failure, etc.).
    /// - Parameter underlying: The original networking error.
    case networkError(underlying: Error)

    /// The client has been rate-limited by the server (HTTP 429).
    case rateLimited

    // MARK: - LocalizedError

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return "The provided Bitcoin address is invalid or was not found."

        case .transactionNotFound:
            return "The requested transaction was not found on the blockchain."

        case .broadcastFailed(let message):
            return "Transaction broadcast failed: \(message)"

        case .serverError(let statusCode, let message):
            return "Server error (\(statusCode)): \(message)"

        case .decodingError(let message, _):
            return "Failed to parse server response: \(message)"

        case .networkError(let underlying):
            return "Network error: \(underlying.localizedDescription)"

        case .rateLimited:
            return "Too many requests. Please wait a moment and try again."
        }
    }

    // MARK: - Retry Eligibility

    /// Indicates whether the error is transient and the operation could
    /// succeed if retried after a delay.
    var isRetryable: Bool {
        switch self {
        case .networkError, .rateLimited:
            return true
        case .serverError(let statusCode, _):
            return statusCode >= 500
        case .invalidAddress, .transactionNotFound,
             .broadcastFailed, .decodingError:
            return false
        }
    }
}
