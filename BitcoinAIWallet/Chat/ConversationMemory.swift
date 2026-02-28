// MARK: - ConversationMemory.swift
// Bitcoin AI Wallet
//
// Tracks full conversation history, last mentioned entities, last shown data,
// and user behavior metrics. Foundation for reference resolution, context-aware
// classification, and dynamic response generation.
//
// Platform: iOS 17.0+
// Framework: Foundation

import Foundation

// MARK: - ConversationMemory

@MainActor
final class ConversationMemory {

    // MARK: - Full Conversation History

    /// All conversation turns in chronological order.
    private(set) var turns: [ConversationTurn] = []

    // MARK: - Last Mentioned Entities

    /// The most recently mentioned Bitcoin address (from user input or AI response).
    private(set) var lastAddress: String?

    /// The most recently mentioned amount.
    private(set) var lastAmount: Decimal?

    /// The most recently mentioned transaction ID.
    private(set) var lastTxid: String?

    /// The most recently mentioned fee level.
    private(set) var lastFeeLevel: FeeLevel?

    // MARK: - Last Shown Data

    /// The last balance shown to the user.
    var lastShownBalance: Decimal?

    /// The last fiat balance shown.
    var lastShownFiatBalance: Decimal?

    /// The last set of transactions shown.
    var lastShownTransactions: [TransactionDisplayItem]?

    /// The last fee estimates shown.
    var lastShownFeeEstimates: (slow: Decimal, medium: Decimal, fast: Decimal)?

    /// The last receive address shown.
    var lastShownReceiveAddress: String?

    /// The last successfully sent transaction.
    var lastSentTx: (txid: String, amount: Decimal, address: String, fee: Decimal)?

    // MARK: - Flow State (synced from ConversationFlow)

    /// The current conversation flow state — kept in sync by ChatViewModel.
    var currentFlowState: ConversationState = .idle

    // MARK: - User Behavior Metrics

    /// Whether the user tends to use emoji in messages.
    private(set) var userUsesEmoji: Bool = false

    /// Detected user language (heuristic).
    private(set) var userLanguage: String = "en"

    /// Running average of user message length.
    private(set) var averageMessageLength: Int = 0

    /// Whether the user tends to write short messages.
    var userIsTerse: Bool { averageMessageLength < 15 }

    // MARK: - Computed Helpers

    /// Total number of conversation turns.
    var turnCount: Int { turns.count }

    /// The last message sent by the user.
    var lastUserMessage: String? {
        turns.last(where: { $0.role == .user })?.text
    }

    /// The last response from the AI.
    var lastAIResponse: String? {
        turns.last(where: { $0.role == .assistant })?.text
    }

    /// The last intent detected from user input.
    var lastUserIntent: WalletIntent? {
        turns.last(where: { $0.role == .user })?.intent
    }

    /// The second-to-last user intent (for "again" detection).
    var previousUserIntent: WalletIntent? {
        let userTurns = turns.filter { $0.role == .user }
        guard userTurns.count >= 2 else { return nil }
        return userTurns[userTurns.count - 2].intent
    }

    // MARK: - Recording

    /// Records a user message and updates entity tracking.
    func recordUserMessage(_ text: String, intent: WalletIntent, entities: ParsedEntity) {
        turns.append(ConversationTurn(
            role: .user,
            text: text,
            intent: intent,
            entities: entities,
            timestamp: Date()
        ))

        // Update last mentioned entities
        if let addr = entities.address { lastAddress = addr }
        if let amt = entities.amount { lastAmount = amt }
        if let txid = entities.txid { lastTxid = txid }
        if let fee = entities.feeLevel { lastFeeLevel = fee }

        // Update behavior metrics
        updateBehaviorMetrics(text)
    }

    /// Records an AI response and updates shown data tracking.
    func recordAIResponse(_ text: String, shownData: ShownData?) {
        turns.append(ConversationTurn(
            role: .assistant,
            text: text,
            intent: nil,
            entities: ParsedEntity(),
            timestamp: Date()
        ))

        if let data = shownData {
            if let b = data.balance { lastShownBalance = b }
            if let f = data.fiatBalance { lastShownFiatBalance = f }
            if let txs = data.transactions { lastShownTransactions = txs }
            if let fees = data.feeEstimates { lastShownFeeEstimates = fees }
            if let addr = data.receiveAddress {
                lastShownReceiveAddress = addr
                lastAddress = addr
            }
            if let sent = data.sentTransaction {
                lastSentTx = sent
                lastAddress = sent.address
                lastAmount = sent.amount
            }
        }
    }

    /// Returns how many turns ago a condition was true.
    func turnsSinceLastSend() -> Int {
        guard lastSentTx != nil else { return Int.max }
        let reversed = turns.reversed()
        var count = 0
        for turn in reversed {
            if turn.role == .assistant, turn.text.contains("sent") || turn.text.contains("Success") {
                return count
            }
            count += 1
        }
        return Int.max
    }

    /// Clears all memory for a new conversation.
    func reset() {
        turns.removeAll()
        lastAddress = nil
        lastAmount = nil
        lastTxid = nil
        lastFeeLevel = nil
        lastShownBalance = nil
        lastShownFiatBalance = nil
        lastShownTransactions = nil
        lastShownFeeEstimates = nil
        lastShownReceiveAddress = nil
        lastSentTx = nil
        currentFlowState = .idle
        userUsesEmoji = false
        userLanguage = "en"
        averageMessageLength = 0
    }

    // MARK: - Private Helpers

    private func updateBehaviorMetrics(_ text: String) {
        // Track average message length
        let userTurns = turns.filter { $0.role == .user }
        let total = userTurns.count
        let sumLength = userTurns.reduce(0) { $0 + $1.text.count }
        averageMessageLength = total > 0 ? sumLength / total : text.count

        // Detect emoji usage
        if text.unicodeScalars.contains(where: { $0.properties.isEmoji && $0.value > 0x23F0 }) {
            userUsesEmoji = true
        }

        // Detect language (simple heuristic)
        if text.unicodeScalars.contains(where: { $0.value >= 0x0600 && $0.value <= 0x06FF }) {
            userLanguage = "ar"
        } else if text.contains("ñ") || text.contains("¿") || text.contains("¡") {
            userLanguage = "es"
        }
    }
}
