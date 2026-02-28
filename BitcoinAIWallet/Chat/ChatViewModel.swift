// MARK: - ChatViewModel.swift
// Bitcoin AI Wallet
//
// Main business logic for the AI chat interface.
// Coordinates intent parsing, response generation, conversation flow,
// and UI state. Handles all new intents including price, convert,
// wallet health, and smart fallback.
//
// Platform: iOS 17.0+
// Framework: Foundation, SwiftUI

import Foundation
import SwiftUI

// MARK: - ChatMessage

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let content: String
    let isFromUser: Bool
    let timestamp: Date
    let responseType: ResponseType?

    /// Whether this message was just created (should animate typing).
    /// Messages loaded from history have this set to `false`.
    var isNew: Bool

    /// Inline action buttons displayed inside the AI bubble (e.g., Paste/Scan during send flow).
    /// Only shown during active flows, not in loaded conversation history.
    var inlineActions: [InlineAction]?

    /// Whether the inline action buttons have been used (hides them after use).
    var inlineActionsUsed: Bool = false

    init(id: UUID = UUID(), content: String, isFromUser: Bool, timestamp: Date = Date(), responseType: ResponseType? = nil, isNew: Bool = true, inlineActions: [InlineAction]? = nil) {
        self.id = id
        self.content = content
        self.isFromUser = isFromUser
        self.timestamp = timestamp
        self.responseType = responseType
        self.isNew = isNew
        self.inlineActions = inlineActions
    }

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id && lhs.content == rhs.content && lhs.isFromUser == rhs.isFromUser && lhs.responseType == rhs.responseType
    }

    static func user(_ text: String) -> ChatMessage {
        ChatMessage(content: text, isFromUser: true)
    }

    static func ai(_ text: String) -> ChatMessage {
        ChatMessage(content: text, isFromUser: false, responseType: .text(text))
    }

    static func aiCard(_ responseType: ResponseType) -> ChatMessage {
        let summary: String
        switch responseType {
        case .text(let text): summary = text
        case .balanceCard(let btc, _, _, _): summary = "\(L10n.Wallet.balance): \(btc) \(L10n.Common.btc)"
        case .sendConfirmCard(let toAddress, let amount, _, _, _, _): summary = "\(L10n.Send.title): \(amount) \(L10n.Common.btc) \(L10n.Send.to) \(truncateAddress(toAddress))"
        case .receiveCard(let address, _): summary = "\(L10n.Receive.title): \(truncateAddress(address))"
        case .historyCard(let transactions): summary = "\(L10n.History.title) (\(transactions.count))"
        case .successCard(let txid, let amount, _): summary = "\(L10n.Chat.sendSuccess) \(amount) \(L10n.Common.btc) (\(String(txid.prefix(8)))...)"
        case .feeCard: summary = L10n.Chat.feeEstimate
        case .priceCard(_, let currency, let formattedPrice): summary = "BTC: \(formattedPrice) \(currency)"
        case .tipsCard(let tip): summary = tip.title
        case .actionButtons: summary = ""
        case .errorText(let text): summary = "\(L10n.Common.error): \(text)"
        }
        return ChatMessage(content: summary, isFromUser: false, responseType: responseType)
    }

    private static func truncateAddress(_ address: String) -> String {
        guard address.count > 16 else { return address }
        return "\(address.prefix(8))...\(address.suffix(6))"
    }
}

// MARK: - QuickAction

enum QuickAction: String, CaseIterable, Identifiable {
    case send, receive, history, fees, settings

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .send: return L10n.QuickAction.send
        case .receive: return L10n.QuickAction.receive
        case .history: return L10n.QuickAction.history
        case .fees: return L10n.QuickAction.fees
        case .settings: return L10n.QuickAction.settings
        }
    }

    var commandText: String { rawValue }
}

// MARK: - ChatViewModel

@MainActor
final class ChatViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var isTyping: Bool = false
    @Published var conversationState: ConversationState = .idle
    @Published var selectedFeeLevel: FeeLevel = .medium
    @Published var showAuthSheet: Bool = false
    @Published var activeProcessingState: ProcessingState?

    /// Whether this is a fresh conversation with no user messages yet.
    var isNewEmptyConversation: Bool {
        !messages.contains(where: { $0.isFromUser })
    }

    // MARK: - Dependencies

    private let intentParser: IntentParser
    let responseGenerator: ResponseGenerator
    private let conversationFlow: ConversationFlow

    // MARK: - Conversation Persistence

    /// The conversation manager for SwiftData persistence.
    var conversationManager: ConversationManager?

    /// Whether the first user message has been sent (used for auto-titling).
    private var hasAutoTitled: Bool = false

    /// Guard against double-broadcast from rapid taps.
    private var isBroadcasting: Bool = false

    // MARK: - Wallet State (injected by parent)

    var walletBalance: Decimal = 0
    var fiatBalance: Decimal = 0
    var pendingBalance: Decimal = 0
    var utxoCount: Int = 0
    var currentReceiveAddress: String = ""
    var addressType: String = "SegWit"
    var currentFeeEstimates: (slow: Decimal, medium: Decimal, fast: Decimal)? {
        didSet {
            conversationFlow.liveFeeEstimates = currentFeeEstimates
        }
    }
    var recentTransactions: [TransactionDisplayItem]?

    // MARK: - Price State

    var btcPrice: Decimal?
    var priceCurrency: String = "USD"

    // MARK: - Private State

    private let typingDelayNanoseconds: UInt64 = 500_000_000

    // MARK: - Initialization

    init() {
        self.intentParser = IntentParser()
        self.responseGenerator = ResponseGenerator()
        self.conversationFlow = ConversationFlow()
        addGreeting()
    }

    init(intentParser: IntentParser, responseGenerator: ResponseGenerator, conversationFlow: ConversationFlow) {
        self.intentParser = intentParser
        self.responseGenerator = responseGenerator
        self.conversationFlow = conversationFlow
        addGreeting()
    }

    // MARK: - Public Actions

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // SECURITY: Detect if user typed a seed phrase and warn them
        if looksLikeSeedPhrase(text) {
            let warning = ChatMessage.ai("I detected what looks like a **recovery phrase** in your message. For your security, this message has **not been saved** to conversation history.\n\nNever share your recovery phrase with anyone or type it into a chat.")
            messages.append(ChatMessage.user("[Message redacted — contained sensitive data]"))
            messages.append(warning)
            inputText = ""
            conversationManager?.persistMessage(role: "user", content: "[Message redacted — contained sensitive data]")
            conversationManager?.persistMessage(role: "assistant", content: warning.content)
            return
        }

        let userMessage = ChatMessage.user(text)
        messages.append(userMessage)
        inputText = ""
        isTyping = true

        // Persist user message and auto-title
        conversationManager?.persistMessage(role: "user", content: text)
        if !hasAutoTitled {
            conversationManager?.autoTitleIfNeeded(firstUserMessage: text)
            hasAutoTitled = true
        }

        let intent = intentParser.parse(text)
        let previousState = conversationState
        let newState = conversationFlow.processIntent(intent)
        conversationState = newState

        let effectiveIntent = resolveEffectiveIntent(rawIntent: intent, previousState: previousState, newState: newState)

        Task { [weak self] in
            guard let self = self else { return }

            // Show processing card for async intents
            if let processing = self.processingConfig(for: effectiveIntent) {
                self.activeProcessingState = processing
                processing.start()
                self.isTyping = false
            }

            // Fetch price if needed for price/convert intents
            await self.fetchPriceIfNeeded(for: effectiveIntent)

            // Advance processing step after price fetch
            if self.activeProcessingState != nil {
                self.activeProcessingState?.completeCurrentStep()
            }

            try? await Task.sleep(nanoseconds: self.typingDelayNanoseconds)

            let context = self.buildContext()
            let responses = self.responseGenerator.generateResponse(for: effectiveIntent, context: context)

            // Complete remaining processing steps and dismiss
            if let processing = self.activeProcessingState {
                // Complete any remaining active steps
                while !processing.isComplete && !processing.isFailed {
                    processing.completeCurrentStep()
                }
                await self.dismissProcessingCard()
            }

            self.appendResponses(responses)
            self.isTyping = false

            // Handle side effects
            self.handleSideEffects(for: effectiveIntent)
        }
    }

    func sendMessage(_ text: String) {
        inputText = text
        sendMessage()
    }

    func handleQuickAction(_ action: QuickAction) {
        inputText = action.commandText
        sendMessage()
    }

    // MARK: - Card Action Handlers

    func confirmTransaction() {
        showAuthSheet = true
    }

    func handleAuthSuccess() async {
        // Prevent double-broadcast from rapid confirmation taps
        guard !isBroadcasting else { return }
        isBroadcasting = true
        defer { isBroadcasting = false }

        conversationState = .processing

        let processing = ProcessingConfigurations.sendTransaction()
        activeProcessingState = processing
        processing.start()
        isTyping = false

        let _ = conversationFlow.processIntent(.confirmAction)

        // Step 1: Signing
        try? await Task.sleep(nanoseconds: 600_000_000)
        processing.completeCurrentStep()

        // Step 2: Broadcasting
        try? await Task.sleep(nanoseconds: 400_000_000)

        if let pending = conversationFlow.pendingTransaction {
            processing.completeCurrentStep()

            // Step 3: Confirming
            try? await Task.sleep(nanoseconds: 300_000_000)
            processing.completeCurrentStep() // sets isComplete

            conversationFlow.markCompleted()
            conversationState = .completed

            await dismissProcessingCard()

            let successText = ResponseTemplates.sendSuccess(txid: "pending_broadcast")
            messages.append(.ai(successText))
            conversationManager?.persistMessage(role: "assistant", content: successText)
            let successCard = ChatMessage.aiCard(.successCard(txid: "pending_broadcast", amount: pending.amount, toAddress: pending.toAddress))
            messages.append(successCard)
            conversationManager?.persistMessage(role: "assistant", content: successCard.content)
        } else {
            processing.failCurrentStep(error: L10n.Error.transactionFailed)

            conversationFlow.markError(L10n.Error.transactionFailed)
            conversationState = .error(L10n.Error.transactionFailed)

            await dismissProcessingCard()

            let failText = ResponseTemplates.sendFailed(reason: L10n.Error.transactionFailed)
            messages.append(.ai(failText))
            conversationManager?.persistMessage(role: "assistant", content: failText)
        }
    }

    func handleAuthCancelled() {
        let cancelText = ResponseTemplates.operationCancelled()
        messages.append(.ai(cancelText))
        conversationManager?.persistMessage(role: "assistant", content: cancelText)
    }

    func handleTransactionSuccess(txid: String, amount: Decimal, toAddress: String) {
        conversationFlow.markCompleted()
        conversationState = .completed
        let successText = ResponseTemplates.sendSuccess(txid: txid)
        messages.append(.ai(successText))
        conversationManager?.persistMessage(role: "assistant", content: successText)
        let card = ChatMessage.aiCard(.successCard(txid: txid, amount: amount, toAddress: toAddress))
        messages.append(card)
        conversationManager?.persistMessage(role: "assistant", content: card.content)
        isTyping = false
    }

    func handleTransactionFailure(reason: String) {
        conversationFlow.markError(reason)
        conversationState = .error(reason)
        let failText = ResponseTemplates.sendFailed(reason: reason)
        messages.append(.ai(failText))
        conversationManager?.persistMessage(role: "assistant", content: failText)
        isTyping = false
    }

    func cancelTransaction() {
        conversationFlow.reset()
        conversationState = .idle
        let cancelText = ResponseTemplates.operationCancelled()
        messages.append(.ai(cancelText))
        conversationManager?.persistMessage(role: "assistant", content: cancelText)
    }

    func selectFeeLevel(_ level: FeeLevel) {
        selectedFeeLevel = level
    }

    func viewTransactionDetail(_ txid: String) {
        inputText = txid
        sendMessage()
    }

    func copyAddress(_ address: String) {
        InlineAddressView.secureCopy(address)
        HapticManager.success()
    }

    func copyTransactionID(_ txid: String) {
        InlineAddressView.secureCopy(txid)
        HapticManager.success()
    }

    func shareText(_ text: String) {
        let activityVC = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else { return }
        activityVC.popoverPresentationController?.sourceView = rootVC.view
        rootVC.present(activityVC, animated: true)
    }

    // MARK: - Seed Phrase Detection

    /// Checks if user input looks like a BIP39 seed phrase (12 or 24 words
    /// where a majority are valid BIP39 words). Prevents accidental seed
    /// phrase leakage into persisted conversation history.
    private func looksLikeSeedPhrase(_ text: String) -> Bool {
        let words = text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .map { String($0) }

        // Only check 12 or 24 word sequences
        guard words.count == 12 || words.count == 24 else { return false }

        // Check if most words are valid BIP39 words
        let bip39Matches = words.filter { BIP39Wordlist.english.contains($0) }.count
        let threshold = words.count * 3 / 4 // 75% match threshold
        return bip39Matches >= threshold
    }

    func clearConversation() {
        messages.removeAll()
        conversationFlow.reset()
        conversationState = .idle
        inputText = ""
        isTyping = false
        hasAutoTitled = false
        addGreeting()
    }

    // MARK: - Conversation Loading

    /// Loads messages from a conversation and sets it as current.
    func loadConversation(_ conversation: Conversation) {
        // Reset state
        messages.removeAll()
        conversationFlow.reset()
        conversationState = .idle
        inputText = ""
        isTyping = false
        activeProcessingState = nil

        conversationManager?.switchTo(conversation)

        // Load persisted messages
        let persisted = conversationManager?.loadMessages() ?? []
        hasAutoTitled = persisted.contains(where: { $0.role == "user" })

        if persisted.isEmpty {
            // New/empty conversation — show greeting
            addGreeting()
        } else {
            // Reconstruct ChatMessage structs from persisted messages
            for msg in persisted {
                if msg.role == "user" {
                    messages.append(ChatMessage(
                        id: msg.id,
                        content: msg.content,
                        isFromUser: true,
                        timestamp: msg.timestamp
                    ))
                } else {
                    messages.append(ChatMessage(
                        id: msg.id,
                        content: msg.content,
                        isFromUser: false,
                        timestamp: msg.timestamp,
                        responseType: .text(msg.content)
                    ))
                }
            }
        }
    }

    /// Starts a new empty conversation.
    func startNewConversation() {
        conversationManager?.createNewConversation()
        clearConversation()
    }

    // MARK: - Private Helpers

    private func addGreeting() {
        let greetingText = ResponseTemplates.greeting(walletName: nil)
        messages.append(.ai(greetingText))
        // Persist the greeting
        conversationManager?.persistMessage(role: "assistant", content: greetingText)
    }

    /// Fetches BTC price from PriceService if the intent needs it.
    private func fetchPriceIfNeeded(for intent: WalletIntent) async {
        switch intent {
        case .price(let currency):
            let curr = currency ?? priceCurrency
            if let price = try? await PriceService.shared.fetchPrice(for: curr) {
                btcPrice = price
                priceCurrency = curr
            }
        case .convertAmount(_, let currency):
            if btcPrice == nil || priceCurrency != currency {
                if let price = try? await PriceService.shared.fetchPrice(for: currency) {
                    btcPrice = price
                    priceCurrency = currency
                }
            }
        default:
            break
        }
    }

    /// Handles side effects after generating the response (e.g., notifications).
    private func handleSideEffects(for intent: WalletIntent) {
        switch intent {
        case .refreshWallet:
            NotificationCenter.default.post(name: .walletRefreshRequested, object: nil)
        case .settings:
            NotificationCenter.default.post(name: .chatInjectCommand, object: "settings")
        case .newAddress:
            NotificationCenter.default.post(name: .chatInjectCommand, object: "newAddress")
        case .hideBalance:
            NotificationCenter.default.post(name: .chatInjectCommand, object: "hideBalance")
        case .showBalance:
            NotificationCenter.default.post(name: .chatInjectCommand, object: "showBalance")
        case .exportHistory:
            NotificationCenter.default.post(name: .chatInjectCommand, object: "exportHistory")
        default:
            break
        }
    }

    private func resolveEffectiveIntent(
        rawIntent: WalletIntent,
        previousState: ConversationState,
        newState: ConversationState
    ) -> WalletIntent {
        switch rawIntent {
        case .balance, .receive, .history, .feeEstimate, .help, .about,
             .confirmAction, .cancelAction, .settings, .transactionDetail,
             .hideBalance, .showBalance, .refreshWallet, .price, .convertAmount,
             .newAddress, .walletHealth, .exportHistory, .utxoList, .bumpFee,
             .networkStatus, .greeting:
            return rawIntent
        case .send:
            return rawIntent
        case .unknown:
            break
        }

        switch newState {
        case .awaitingConfirmation(let amount, let address, _):
            return .send(amount: amount, unit: .btc, address: address, feeLevel: .medium)
        case .awaitingAmount:
            return .send(amount: nil, unit: nil, address: nil, feeLevel: nil)
        case .awaitingAddress:
            return .send(amount: nil, unit: nil, address: nil, feeLevel: nil)
        default:
            return rawIntent
        }
    }

    func buildContext() -> ConversationContext {
        ConversationContext(
            walletBalance: walletBalance,
            fiatBalance: fiatBalance,
            pendingBalance: pendingBalance,
            utxoCount: utxoCount,
            pendingTransaction: conversationFlow.pendingTransaction,
            recentTransactions: recentTransactions,
            currentFeeEstimates: currentFeeEstimates,
            currentReceiveAddress: currentReceiveAddress,
            addressType: addressType,
            conversationState: conversationState,
            btcPrice: btcPrice,
            priceCurrency: priceCurrency
        )
    }

    func appendResponses(_ responses: [ResponseType]) {
        for response in responses {
            var chatMsg: ChatMessage
            switch response {
            case .text(let text):
                chatMsg = .ai(text)
                conversationManager?.persistMessage(role: "assistant", content: text)
            case .errorText(let text):
                chatMsg = .ai(text)
                conversationManager?.persistMessage(role: "assistant", content: text, intentType: "error")
            default:
                chatMsg = .aiCard(response)
                // Persist the summary text for card-type responses
                if !chatMsg.content.isEmpty {
                    conversationManager?.persistMessage(role: "assistant", content: chatMsg.content)
                }
            }

            // Attach inline action buttons based on conversation state
            chatMsg.inlineActions = inlineActionsForCurrentState(response: response)

            messages.append(chatMsg)
        }
    }

    // MARK: - Inline Action Buttons

    /// Determines which inline action buttons to attach based on conversation state.
    private func inlineActionsForCurrentState(response: ResponseType) -> [InlineAction]? {
        switch conversationState {
        case .awaitingAddress:
            // Only attach to text responses (the "which address?" prompt)
            if case .text = response {
                return [
                    InlineAction(
                        icon: "doc.on.clipboard",
                        label: L10n.Send.pasteClipboard,
                        type: .pasteAddress
                    ),
                    InlineAction(
                        icon: "qrcode.viewfinder",
                        label: L10n.Send.scanQR,
                        type: .scanQR
                    ),
                ]
            }
        default:
            break
        }
        return nil
    }

    /// Handles taps on inline action buttons inside AI chat bubbles.
    func handleInlineAction(_ action: InlineAction, messageId: UUID) {
        // Mark buttons as used on the source message
        if let index = messages.firstIndex(where: { $0.id == messageId }) {
            messages[index].inlineActionsUsed = true
        }

        switch action.type {
        case .pasteAddress:
            handlePasteForSend()
        case .scanQR:
            NotificationCenter.default.post(name: .openQRScannerForSend, object: nil)
        case .copyText:
            if let text = action.context {
                copyAddress(text)
            }
        case .shareText:
            if let text = action.context {
                shareText(text)
            }
        }
    }

    /// Reads clipboard, validates as Bitcoin address or BIP21 URI, and injects into send flow.
    private func handlePasteForSend() {
        guard let content = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            appendResponses([.errorText(L10n.Send.clipboardEmpty)])
            HapticManager.error()
            return
        }

        // Try BIP21 URI first
        if let parsed = BIP21Parser.parse(content) {
            var command = parsed.address
            if let amount = parsed.amount {
                command = "send \(amount) BTC to \(parsed.address)"
            }
            HapticManager.success()
            sendMessage(command)
            return
        }

        // Try plain Bitcoin address
        let validator = AddressValidator()
        if validator.isValid(content) {
            HapticManager.success()
            sendMessage(content)
            return
        }

        // Not a valid address
        appendResponses([.errorText(L10n.Send.clipboardInvalid)])
        HapticManager.error()
    }

    // MARK: - Processing Card Helpers

    /// Dismisses the active processing card with a brief delay and animation.
    func dismissProcessingCard() async {
        guard activeProcessingState != nil else { return }
        try? await Task.sleep(nanoseconds: 200_000_000)
        withAnimation(.easeOut(duration: 0.3)) {
            activeProcessingState = nil
        }
    }

    /// Maps a wallet intent to the appropriate processing configuration.
    /// Returns `nil` for intents that respond from cached data.
    private func processingConfig(for intent: WalletIntent) -> ProcessingState? {
        switch intent {
        case .refreshWallet:
            return ProcessingConfigurations.walletRefresh()
        case .price:
            return ProcessingConfigurations.priceFetch()
        case .convertAmount:
            return ProcessingConfigurations.convertAmount()
        case .walletHealth:
            return ProcessingConfigurations.walletHealth()
        case .networkStatus:
            return ProcessingConfigurations.networkStatus()
        case .newAddress:
            return ProcessingConfigurations.newAddress()
        case .exportHistory:
            return ProcessingConfigurations.exportHistory()
        default:
            return nil
        }
    }
}
