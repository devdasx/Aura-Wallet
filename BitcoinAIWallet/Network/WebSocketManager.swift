// MARK: - WebSocketManager.swift
// Bitcoin AI Wallet
//
// Manages WebSocket connections to the Blockbook server for real-time
// notifications about new transactions, confirmations, and blocks.
// Uses URLSessionWebSocketTask for native WebSocket support with
// automatic reconnection, heartbeat pings, and address subscription
// management.
//
// Platform: iOS 17.0+
// Framework: Foundation, Combine
// Concurrency: Swift Concurrency (async/await) + MainActor for published state

import Foundation
import Combine
import os.log

// MARK: - WebSocketMessage

/// Represents a parsed real-time message received over the WebSocket connection.
///
/// Each case corresponds to a distinct notification type from the Blockbook
/// WebSocket API. The `.unknown` case catches any messages that do not match
/// a known format.
enum WebSocketMessage: Sendable {

    /// A new transaction affecting a subscribed address was detected in the mempool.
    ///
    /// - Parameters:
    ///   - txid: The transaction hash.
    ///   - address: The subscribed address involved in the transaction.
    case newTransaction(txid: String, address: String)

    /// A previously-seen transaction has received additional confirmations.
    ///
    /// - Parameters:
    ///   - txid: The transaction hash.
    ///   - confirmations: The current confirmation count.
    case confirmedTransaction(txid: String, confirmations: Int)

    /// A new block has been mined and appended to the blockchain.
    ///
    /// - Parameters:
    ///   - height: The block height.
    ///   - hash: The block hash (hex string).
    case blockNotification(height: Int, hash: String)

    /// A message that could not be parsed into any known type.
    ///
    /// - Parameter data: The raw message data for debugging.
    case unknown(data: Data)
}

// MARK: - WebSocketDelegate

/// Protocol for receiving WebSocket lifecycle and message events.
///
/// Implement this delegate to react to connection state changes and
/// incoming real-time messages. All delegate methods are called on
/// the main actor.
@MainActor
protocol WebSocketDelegate: AnyObject {

    /// Called when the WebSocket connection is successfully established.
    func webSocketDidConnect()

    /// Called when the WebSocket connection is closed.
    ///
    /// - Parameter error: The error that caused the disconnection, or `nil`
    ///   for a clean close.
    func webSocketDidDisconnect(error: Error?)

    /// Called when a parsed message is received over the WebSocket.
    ///
    /// - Parameter message: The parsed `WebSocketMessage`.
    func webSocketDidReceiveMessage(_ message: WebSocketMessage)
}

// MARK: - WebSocketConnectionState

/// Represents the current state of the WebSocket connection.
enum WebSocketConnectionState: Sendable, Equatable {

    /// Not connected and not attempting to connect.
    case disconnected

    /// Actively establishing a connection.
    case connecting

    /// Connection established and ready to send/receive messages.
    case connected

    /// Connection lost; will attempt to reconnect.
    case reconnecting(attempt: Int)
}

// MARK: - WebSocketManager

/// Manages a single WebSocket connection to a Blockbook server for
/// real-time transaction and block notifications.
///
/// The manager handles:
/// - Connection lifecycle (connect, disconnect, reconnect)
/// - Heartbeat pings to keep the connection alive
/// - Address subscription / unsubscription
/// - Block notification subscription
/// - Automatic reconnection with exponential backoff
/// - Message parsing and delegate dispatch
///
/// Usage:
/// ```swift
/// let manager = WebSocketManager.shared
/// manager.delegate = self
/// manager.connect()
/// manager.subscribe(address: "bc1q...")
/// ```
@MainActor
final class WebSocketManager: NSObject, ObservableObject {

    // MARK: - Singleton

    /// The shared WebSocket manager instance, configured for the default API.
    static let shared = WebSocketManager()

    // MARK: - Published State

    /// Whether the WebSocket is currently connected.
    @Published private(set) var isConnected: Bool = false

    /// The current detailed connection state.
    @Published private(set) var connectionState: WebSocketConnectionState = .disconnected

    // MARK: - Delegate

    /// Delegate for receiving WebSocket events. Set before calling `connect()`.
    weak var delegate: WebSocketDelegate?

    // MARK: - Private Properties

    /// The active WebSocket task.
    private var webSocketTask: URLSessionWebSocketTask?

    /// The URL session used to create WebSocket tasks.
    /// Uses ephemeral configuration for privacy (no disk cache or cookies).
    /// Includes certificate pinning delegate for critical hosts.
    private nonisolated let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        config.waitsForConnectivity = true
        let pinningDelegate = CertificatePinningDelegate()
        return URLSession(configuration: config, delegate: pinningDelegate, delegateQueue: nil)
    }()

    /// The WebSocket server URL.
    private var serverURL: URL

    /// Addresses currently subscribed to transaction notifications.
    private var subscribedAddresses: Set<String> = []

    /// Whether block notifications are currently subscribed.
    private var isSubscribedToBlocks: Bool = false

    /// Current reconnection attempt count.
    private var reconnectAttempts: Int = 0

    /// Maximum number of consecutive reconnection attempts before giving up.
    private let maxReconnectAttempts: Int = 10

    /// Timer for sending periodic ping messages.
    private var pingTimer: Timer?

    /// Interval between heartbeat ping messages (in seconds).
    private let pingInterval: TimeInterval = 25

    /// Incrementing ID for JSON-RPC style messages.
    private var messageID: Int = 0

    /// Task handle for the background receive loop.
    private var receiveTask: Task<Void, Never>?

    /// Task handle for the reconnection delay.
    private var reconnectTask: Task<Void, Never>?

    /// Logger for WebSocket diagnostics.
    private nonisolated let logger = Logger(
        subsystem: "com.bitcoinai.wallet",
        category: "WebSocketManager"
    )

    // MARK: - Initialization

    /// Create a WebSocket manager targeting the given server URL.
    ///
    /// - Parameter url: The WebSocket server URL. Defaults to the mainnet
    ///   Blockbook WebSocket endpoint from `APIConfiguration.default`.
    init(url: URL = APIConfiguration.default.blockbookWebSocketURL) {
        self.serverURL = url
        super.init()
    }

    deinit {
        // Clean up timers and tasks synchronously
        pingTimer?.invalidate()
        pingTimer = nil
        receiveTask?.cancel()
        reconnectTask?.cancel()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
    }

    // MARK: - Connection Lifecycle

    /// Connect to the WebSocket server.
    ///
    /// If already connected, this method does nothing. If a previous
    /// connection exists, it is closed before opening a new one.
    ///
    /// - Parameter url: Optional URL override. If `nil`, uses the URL
    ///   provided at initialization.
    func connect(url: URL? = nil) {
        if let url = url {
            serverURL = url
        }

        // Tear down existing connection
        disconnectInternal(sendClose: false)

        logger.info("Connecting to WebSocket at \(self.serverURL.absoluteString)")
        connectionState = .connecting

        let task = session.webSocketTask(with: serverURL)
        task.maximumMessageSize = 1_048_576 // 1 MB
        self.webSocketTask = task
        task.resume()

        // Verify the connection is truly established by sending a ping.
        // Only mark as connected once we get a successful pong back.
        task.sendPing { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let error = error {
                    self.logger.error("Initial ping failed: \(error.localizedDescription)")
                    self.handleDisconnect(error: error)
                } else {
                    self.isConnected = true
                    self.connectionState = .connected
                    self.reconnectAttempts = 0

                    // Start heartbeat pings
                    self.startPingTimer()

                    // Notify delegate
                    self.delegate?.webSocketDidConnect()

                    // Re-subscribe to any previously subscribed addresses
                    self.resubscribeAll()
                }
            }
        }

        // Start receiving messages
        startReceiveLoop()
    }

    /// Disconnect from the WebSocket server.
    ///
    /// Cancels any pending reconnection and clears all subscriptions.
    func disconnect() {
        logger.info("Disconnecting from WebSocket (user-initiated).")
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempts = maxReconnectAttempts // Prevent auto-reconnect
        disconnectInternal(sendClose: true)
        subscribedAddresses.removeAll()
        isSubscribedToBlocks = false
    }

    // MARK: - Address Subscriptions

    /// Subscribe to real-time transaction notifications for a Bitcoin address.
    ///
    /// When a new transaction involving this address is detected in the mempool
    /// or confirmed in a block, the delegate will be notified.
    ///
    /// - Parameter address: A Bitcoin address (legacy, SegWit, or Taproot).
    func subscribe(address: String) {
        guard !address.isEmpty else { return }

        subscribedAddresses.insert(address)

        guard isConnected else {
            logger.debug("Queued subscription for \(address) (not connected).")
            return
        }

        sendSubscribeAddress(address)
    }

    /// Unsubscribe from transaction notifications for a Bitcoin address.
    ///
    /// - Parameter address: The address to unsubscribe from.
    func unsubscribe(address: String) {
        subscribedAddresses.remove(address)

        guard isConnected else { return }

        sendUnsubscribeAddress(address)
    }

    /// Subscribe to multiple addresses at once.
    ///
    /// - Parameter addresses: An array of Bitcoin addresses.
    func subscribe(addresses: [String]) {
        for address in addresses {
            subscribe(address: address)
        }
    }

    /// Unsubscribe from all currently-subscribed addresses.
    func unsubscribeAll() {
        let addresses = subscribedAddresses
        subscribedAddresses.removeAll()

        guard isConnected else { return }

        for address in addresses {
            sendUnsubscribeAddress(address)
        }
    }

    // MARK: - Block Subscriptions

    /// Subscribe to new block notifications.
    ///
    /// When a new block is mined, the delegate will receive a
    /// `.blockNotification` message.
    func subscribeToBlocks() {
        isSubscribedToBlocks = true

        guard isConnected else {
            logger.debug("Queued block subscription (not connected).")
            return
        }

        sendSubscribeBlocks()
    }

    /// Unsubscribe from new block notifications.
    func unsubscribeFromBlocks() {
        isSubscribedToBlocks = false
        // Blockbook does not have an explicit unsubscribe for blocks;
        // simply stop processing block messages.
    }

    // MARK: - Private: Internal Disconnect

    /// Close the WebSocket connection without affecting subscription state.
    ///
    /// - Parameter sendClose: Whether to send a close frame to the server.
    private func disconnectInternal(sendClose: Bool) {
        pingTimer?.invalidate()
        pingTimer = nil
        receiveTask?.cancel()
        receiveTask = nil

        if sendClose {
            webSocketTask?.cancel(with: .normalClosure, reason: "Client disconnect".data(using: .utf8))
        } else {
            webSocketTask?.cancel()
        }
        webSocketTask = nil

        if isConnected {
            isConnected = false
            connectionState = .disconnected
        }
    }

    // MARK: - Private: Receive Loop

    /// Start an asynchronous loop that continuously listens for incoming messages.
    private func startReceiveLoop() {
        receiveTask?.cancel()

        receiveTask = Task { [weak self] in
            guard let self = self else { return }

            while !Task.isCancelled {
                guard let task = self.webSocketTask else { break }

                do {
                    let message = try await task.receive()
                    self.handleReceivedMessage(message)
                } catch {
                    if !Task.isCancelled {
                        self.handleDisconnect(error: error)
                    }
                    break
                }
            }
        }
    }

    /// Process a received WebSocket message.
    ///
    /// - Parameter message: The raw `URLSessionWebSocketTask.Message`.
    private func handleReceivedMessage(_ message: URLSessionWebSocketTask.Message) {
        let data: Data

        switch message {
        case .data(let messageData):
            data = messageData

        case .string(let text):
            guard let textData = text.data(using: .utf8) else {
                logger.warning("Received non-UTF8 string message.")
                return
            }
            data = textData

        @unknown default:
            logger.warning("Received unknown WebSocket message type.")
            return
        }

        // Parse the message
        let parsed = parseMessage(data: data)
        delegate?.webSocketDidReceiveMessage(parsed)
    }

    // MARK: - Private: Message Parsing

    /// Parse raw WebSocket data into a `WebSocketMessage`.
    ///
    /// Blockbook WebSocket messages use a JSON-RPC-like format:
    /// ```json
    /// {
    ///   "id": "1",
    ///   "data": {
    ///     "address": "bc1q...",
    ///     "tx": { "txid": "abc123...", ... }
    ///   }
    /// }
    /// ```
    ///
    /// - Parameter data: The raw message bytes.
    /// - Returns: A parsed `WebSocketMessage`.
    private nonisolated func parseMessage(data: Data) -> WebSocketMessage {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .unknown(data: data)
        }

        // Handle Blockbook "subscribedAddresses" notification
        // Format: { "data": { "address": "...", "tx": { "txid": "...", ... } } }
        if let dataDict = json["data"] as? [String: Any] {

            // Transaction notification
            if let address = dataDict["address"] as? String,
               let tx = dataDict["tx"] as? [String: Any],
               let txid = tx["txid"] as? String {

                // Check if it has confirmations (confirmed tx) or not (new mempool tx)
                if let confirmations = tx["confirmations"] as? Int, confirmations > 0 {
                    return .confirmedTransaction(txid: txid, confirmations: confirmations)
                }
                return .newTransaction(txid: txid, address: address)
            }

            // Block notification
            // Format: { "data": { "height": 123456, "hash": "00000..." } }
            if let height = dataDict["height"] as? Int,
               let hash = dataDict["hash"] as? String {
                return .blockNotification(height: height, hash: hash)
            }
        }

        // Handle alternative Blockbook message formats
        // Some Blockbook implementations use "subscribeAddresses" response format
        if let method = json["method"] as? String {
            switch method {
            case "subscribeAddresses":
                if let params = json["params"] as? [String: Any],
                   let tx = params["tx"] as? [String: Any],
                   let txid = tx["txid"] as? String {
                    // Extract the first address from inputs/outputs
                    let address = extractAddressFromTransaction(tx)
                    if let confirmations = tx["confirmations"] as? Int, confirmations > 0 {
                        return .confirmedTransaction(txid: txid, confirmations: confirmations)
                    }
                    return .newTransaction(txid: txid, address: address)
                }

            case "subscribeNewBlock":
                if let params = json["params"] as? [String: Any],
                   let height = params["height"] as? Int,
                   let hash = params["hash"] as? String {
                    return .blockNotification(height: height, hash: hash)
                }

            default:
                break
            }
        }

        return .unknown(data: data)
    }

    /// Extract the first relevant address from a transaction JSON object.
    ///
    /// - Parameter tx: The transaction dictionary.
    /// - Returns: The first address found, or "unknown" if none.
    private nonisolated func extractAddressFromTransaction(_ tx: [String: Any]) -> String {
        // Check outputs first (vout)
        if let vout = tx["vout"] as? [[String: Any]] {
            for output in vout {
                if let addresses = output["addresses"] as? [String],
                   let first = addresses.first {
                    return first
                }
            }
        }

        // Check inputs (vin)
        if let vin = tx["vin"] as? [[String: Any]] {
            for input in vin {
                if let addresses = input["addresses"] as? [String],
                   let first = addresses.first {
                    return first
                }
            }
        }

        return "unknown"
    }

    // MARK: - Private: Send Messages

    /// Send a JSON message over the WebSocket connection.
    ///
    /// - Parameter json: A dictionary to serialize and send as a string message.
    private func sendJSON(_ json: [String: Any]) {
        guard let task = webSocketTask else {
            logger.warning("Cannot send message: WebSocket is not connected.")
            return
        }

        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let string = String(data: data, encoding: .utf8) else {
            logger.error("Failed to serialize WebSocket message to JSON.")
            return
        }

        task.send(.string(string)) { [weak self] error in
            if let error = error {
                self?.logger.error("Failed to send WebSocket message: \(error.localizedDescription)")
            }
        }
    }

    /// Generate the next unique message ID for JSON-RPC style requests.
    ///
    /// - Returns: A string representation of the incrementing ID.
    private func nextMessageID() -> String {
        messageID += 1
        return String(messageID)
    }

    /// Send a subscribe request for a single address.
    ///
    /// Blockbook subscribe format:
    /// ```json
    /// { "id": "1", "method": "subscribeAddresses", "params": { "addresses": ["bc1q..."] } }
    /// ```
    ///
    /// - Parameter address: The Bitcoin address to subscribe to.
    private func sendSubscribeAddress(_ address: String) {
        let message: [String: Any] = [
            "id": nextMessageID(),
            "method": "subscribeAddresses",
            "params": [
                "addresses": [address]
            ]
        ]

        logger.debug("Subscribing to address: \(address)")
        sendJSON(message)
    }

    /// Send an unsubscribe request for a single address.
    ///
    /// - Parameter address: The Bitcoin address to unsubscribe from.
    private func sendUnsubscribeAddress(_ address: String) {
        let message: [String: Any] = [
            "id": nextMessageID(),
            "method": "unsubscribeAddresses",
            "params": [
                "addresses": [address]
            ]
        ]

        logger.debug("Unsubscribing from address: \(address)")
        sendJSON(message)
    }

    /// Send a subscribe request for new block notifications.
    private func sendSubscribeBlocks() {
        let message: [String: Any] = [
            "id": nextMessageID(),
            "method": "subscribeNewBlock",
            "params": [String: Any]()
        ]

        logger.debug("Subscribing to new block notifications.")
        sendJSON(message)
    }

    /// Re-subscribe to all previously subscribed addresses and blocks.
    ///
    /// Called after a successful reconnection to restore the subscription state.
    private func resubscribeAll() {
        for address in subscribedAddresses {
            sendSubscribeAddress(address)
        }

        if isSubscribedToBlocks {
            sendSubscribeBlocks()
        }
    }

    // MARK: - Private: Ping / Heartbeat

    /// Start a repeating timer that sends WebSocket pings to keep the connection alive.
    private func startPingTimer() {
        pingTimer?.invalidate()

        pingTimer = Timer.scheduledTimer(
            withTimeInterval: pingInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sendPing()
            }
        }
    }

    /// Send a single ping message to the server.
    ///
    /// If the ping fails, the connection is considered lost and reconnection
    /// is triggered.
    private func sendPing() {
        guard let task = webSocketTask else { return }

        task.sendPing { [weak self] error in
            if let error = error {
                self?.logger.warning("Ping failed: \(error.localizedDescription)")
                Task { @MainActor [weak self] in
                    self?.handleDisconnect(error: error)
                }
            }
        }
    }

    // MARK: - Private: Reconnection

    /// Handle a WebSocket disconnection.
    ///
    /// If the disconnection was unexpected (not user-initiated), this method
    /// triggers automatic reconnection with exponential backoff.
    ///
    /// - Parameter error: The error that caused the disconnection, if any.
    private func handleDisconnect(error: Error?) {
        let wasConnected = isConnected
        disconnectInternal(sendClose: false)

        if wasConnected {
            delegate?.webSocketDidDisconnect(error: error)
        }

        // Attempt to reconnect if we haven't exceeded the maximum attempts
        guard reconnectAttempts < maxReconnectAttempts else {
            logger.error(
                "Maximum reconnect attempts (\(self.maxReconnectAttempts)) reached. Giving up."
            )
            connectionState = .disconnected
            return
        }

        reconnect()
    }

    /// Attempt to reconnect with exponential backoff.
    ///
    /// The delay between attempts follows the formula:
    /// `min(120, 2^attempt) + random(0, 1)` seconds.
    private func reconnect() {
        reconnectAttempts += 1
        connectionState = .reconnecting(attempt: reconnectAttempts)

        // Calculate delay: exponential backoff capped at 120 seconds, plus jitter
        let exponentialDelay = pow(2.0, Double(reconnectAttempts - 1))
        let cappedDelay = min(exponentialDelay, 120.0)
        let jitter = Double.random(in: 0...1)
        let delay = cappedDelay + jitter

        logger.info(
            "Reconnecting in \(delay, format: .fixed(precision: 1))s (attempt \(self.reconnectAttempts)/\(self.maxReconnectAttempts))."
        )

        reconnectTask?.cancel()

        reconnectTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

                guard !Task.isCancelled else { return }

                self?.connect()
            } catch {
                // Task was cancelled (e.g. user called disconnect())
            }
        }
    }
}

// MARK: - WebSocketManager + Notification Names

extension Notification.Name {

    /// Posted when a real-time transaction notification is received via WebSocket.
    /// The `userInfo` dictionary contains `"txid"` (String) and `"address"` (String).
    static let webSocketNewTransaction = Notification.Name(
        "com.bitcoinai.wallet.webSocketNewTransaction"
    )

    /// Posted when a transaction confirmation update is received via WebSocket.
    /// The `userInfo` dictionary contains `"txid"` (String) and `"confirmations"` (Int).
    static let webSocketConfirmedTransaction = Notification.Name(
        "com.bitcoinai.wallet.webSocketConfirmedTransaction"
    )

    /// Posted when a new block notification is received via WebSocket.
    /// The `userInfo` dictionary contains `"height"` (Int) and `"hash"` (String).
    static let webSocketNewBlock = Notification.Name(
        "com.bitcoinai.wallet.webSocketNewBlock"
    )

    /// Posted when the WebSocket connection state changes.
    /// The `userInfo` dictionary contains `"isConnected"` (Bool).
    static let webSocketConnectionStateChanged = Notification.Name(
        "com.bitcoinai.wallet.webSocketConnectionStateChanged"
    )
}
