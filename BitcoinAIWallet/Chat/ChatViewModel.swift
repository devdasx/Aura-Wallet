// MARK: - ChatViewModel.swift
// Bitcoin AI Wallet
//
// Main business logic for the AI chat interface.
// V18 Language Brain Pipeline: seed check → reference resolution →
// multi-intent split → knowledge check → smart classification →
// smart flow → meaning-aware response → personality adaptation →
// memory update.
//
// Coordinates V18 systems:
// SmartIntentClassifier, ConversationMemory, ReferenceResolver,
// SmartConversationFlow, DynamicResponseBuilder, ResponseGenerator,
// MultiIntentHandler, PersonalityEngine, BitcoinKnowledgeEngine.
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
        lhs.id == rhs.id && lhs.content == rhs.content && lhs.isFromUser == rhs.isFromUser && lhs.responseType == rhs.responseType && lhs.isNew == rhs.isNew
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

    // MARK: - V18 Dependencies

    private let smartClassifier: SmartIntentClassifier
    let responseGenerator: ResponseGenerator
    private let responseBuilder: DynamicResponseBuilder
    private let smartFlow: SmartConversationFlow
    private let referenceResolver: ReferenceResolver
    private let multiIntentHandler: MultiIntentHandler
    private let personalityEngine: PersonalityEngine
    private let knowledgeEngine: BitcoinKnowledgeEngine
    private let entityExtractor: EntityExtractor
    let memory: ConversationMemory

    // MARK: - Conversation Persistence

    /// The conversation manager for SwiftData persistence.
    var conversationManager: ConversationManager?

    /// Whether the first user message has been sent (used for auto-titling).
    private var hasAutoTitled: Bool = false

    /// Guard against double-broadcast from rapid taps.
    private var isBroadcasting: Bool = false

    /// Tracks message IDs that have already played their typing animation.
    /// Prevents re-animation when SwiftUI recreates cells in LazyVStack.
    private(set) var animatedMessageIDs: Set<UUID> = []

    // MARK: - Wallet State (injected by parent)

    weak var walletState: WalletState?
    var walletBalance: Decimal = 0
    var fiatBalance: Decimal = 0
    var pendingBalance: Decimal = 0
    var utxoCount: Int = 0
    var currentReceiveAddress: String = ""
    var addressType: String = "SegWit"
    var currentFeeEstimates: (slow: Decimal, medium: Decimal, fast: Decimal)? {
        didSet {
            smartFlow.liveFeeEstimates = currentFeeEstimates
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
        let patternMatcher = PatternMatcher()
        let entityExtractor = EntityExtractor()
        let referenceResolver = ReferenceResolver()
        let responseGenerator = ResponseGenerator()
        let memory = ConversationMemory()

        self.smartClassifier = SmartIntentClassifier(
            patternMatcher: patternMatcher,
            entityExtractor: entityExtractor,
            referenceResolver: referenceResolver
        )
        self.responseGenerator = responseGenerator
        self.responseBuilder = DynamicResponseBuilder(responseGenerator: responseGenerator)
        self.smartFlow = SmartConversationFlow()
        self.referenceResolver = referenceResolver
        self.multiIntentHandler = MultiIntentHandler()
        self.personalityEngine = PersonalityEngine()
        self.knowledgeEngine = BitcoinKnowledgeEngine()
        self.entityExtractor = entityExtractor
        self.memory = memory
        addGreeting()
    }

    // MARK: - Public Actions

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // SECURITY: Detect if user typed a seed phrase and warn them (ALWAYS FIRST)
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

        // V18 Language Brain Pipeline
        // Step 1: Reference resolution
        let references = referenceResolver.resolve(text, memory: memory)
        let enrichedText = referenceResolver.enrichWithReferences(text, references)

        // Step 2: Multi-intent split
        let parts = multiIntentHandler.splitIfCompound(enrichedText)

        // Step 3-8: Process all parts
        Task { [weak self] in
            guard let self = self else { return }
            for part in parts {
                await self.processSmartPart(part, originalText: text)
            }
            self.isTyping = false
        }
    }

    /// Processes a single intent part through the V18 Language Brain pipeline.
    private func processSmartPart(_ text: String, originalText: String) async {
        // Step 3: Extract entities
        let entities = entityExtractor.extract(from: text)

        // Step 4: Bitcoin knowledge check (uses SentenceAnalyzer for meaning-aware filtering)
        let tempMeaning = SentenceAnalyzer().analyze(text, memory: memory)
        if let knowledge = knowledgeEngine.answer(meaning: tempMeaning, input: text) {
            memory.recordUserMessage(originalText, intent: .unknown(rawText: text), entities: entities)
            let adapted = personalityEngine.adapt(knowledge, memory: memory)
            try? await Task.sleep(nanoseconds: typingDelayNanoseconds)
            appendResponses([.text(adapted)])
            memory.recordAIResponse(adapted, shownData: nil)
            return
        }

        // Step 5: Smart classification (Language Engine primary, PatternMatcher fallback)
        let result = smartClassifier.classify(text, memory: memory)
        memory.recordUserMessage(originalText, intent: result.intent, entities: entities)
        memory.currentFlowState = conversationState

        // Step 6: Smart flow processing
        let action = smartFlow.processMessage(result.intent, meaning: result.meaning, memory: memory)

        // Show processing card for async intents
        let effectiveIntent = resolveIntentFromAction(action, result: result)
        if let processing = processingConfig(for: effectiveIntent) {
            activeProcessingState = processing
            processing.start()
            isTyping = false
        }

        // Fetch price if needed
        await fetchPriceIfNeeded(for: effectiveIntent)

        if activeProcessingState != nil {
            activeProcessingState?.completeCurrentStep()
        }

        try? await Task.sleep(nanoseconds: typingDelayNanoseconds)

        // Step 7: Build response based on flow action
        let context = buildContext()
        var responses: [ResponseType]

        switch action {
        case .advanceFlow(let newState):
            conversationState = newState
            responses = responseBuilder.buildResponse(for: result, context: context, memory: memory, flow: smartFlow)

        case .handleNormally(let intent):
            let normalResult = ClassificationResult(intent: intent, confidence: 0.9, needsClarification: false, alternatives: [], meaning: result.meaning)
            responses = responseBuilder.buildResponse(for: normalResult, context: context, memory: memory, flow: smartFlow)

        case .pauseAndHandle(let intent, let hint):
            let pauseResult = ClassificationResult(intent: intent, confidence: 0.9, needsClarification: false, alternatives: [], meaning: result.meaning)
            responses = responseBuilder.buildResponse(for: pauseResult, context: context, memory: memory, flow: smartFlow)
            responses.append(.text(hint))

        case .modifyFlow(let field, let newValue):
            responses = handleFlowModification(field: field, newValue: newValue, context: context)

        case .respondToMeaning(let meaning):
            let meaningResult = ClassificationResult(intent: result.intent, confidence: result.confidence, needsClarification: false, alternatives: [], meaning: meaning)
            responses = responseBuilder.buildResponse(for: meaningResult, context: context, memory: memory, flow: smartFlow)
        }

        // Step 8: Personality adaptation
        responses = personalityEngine.adaptAll(responses, memory: memory)

        // Complete remaining processing steps and dismiss
        if let processing = activeProcessingState {
            while !processing.isComplete && !processing.isFailed {
                processing.completeCurrentStep()
            }
            await dismissProcessingCard()
        }

        appendResponses(responses)

        // Step 9: Record AI response in memory
        let responseText = responses.compactMap { resp -> String? in
            if case .text(let t) = resp { return t }
            return nil
        }.joined(separator: "\n")
        let shownData = responseGenerator.extractShownData(from: responses, context: context)
        memory.recordAIResponse(responseText, shownData: shownData)

        // Handle side effects
        handleSideEffects(for: effectiveIntent)
    }

    /// Extracts the effective intent from a FlowAction for processing cards and side effects.
    private func resolveIntentFromAction(_ action: FlowAction, result: ClassificationResult) -> WalletIntent {
        switch action {
        case .advanceFlow: return result.intent
        case .handleNormally(let intent): return intent
        case .pauseAndHandle(let intent, _): return intent
        case .modifyFlow: return result.intent
        case .respondToMeaning: return result.intent
        }
    }

    /// Handles in-flight modifications to fee or amount during send flow.
    private func handleFlowModification(field: String, newValue: String, context: ConversationContext) -> [ResponseType] {
        guard let pending = smartFlow.pendingTransaction else {
            return [.text("Nothing to modify right now.")]
        }

        if field == "fee" {
            let newLevel: FeeLevel
            switch newValue {
            case "increase", "fast": newLevel = .fast
            case "decrease", "slow": newLevel = .slow
            default: newLevel = .medium
            }
            let feeRate = resolveFeeRate(level: newLevel, context: context)
            let feeBTC = (feeRate * Decimal(140)) / 100_000_000
            let estimatedTime = resolveEstimatedTime(level: newLevel)
            let remaining = max((context.walletBalance ?? 0) - pending.amount - feeBTC, 0)

            smartFlow.pendingTransaction = PendingTransactionInfo(
                toAddress: pending.toAddress, amount: pending.amount,
                fee: feeBTC, feeRate: feeRate, estimatedMinutes: estimatedTime
            )
            conversationState = .awaitingConfirmation(amount: pending.amount, address: pending.toAddress, fee: feeBTC)
            smartFlow.activeFlow = conversationState

            return [.sendConfirmCard(
                toAddress: pending.toAddress, amount: pending.amount,
                fee: feeBTC, feeRate: feeRate,
                estimatedTime: estimatedTime, remainingBalance: remaining
            )]
        }

        if field == "amount" {
            var newAmount = pending.amount
            switch newValue {
            case "half": newAmount = pending.amount / 2
            case "double": newAmount = pending.amount * 2
            case "increase": newAmount = pending.amount * Decimal(string: "1.5")!
            case "decrease": newAmount = pending.amount * Decimal(string: "0.75")!
            case "max": newAmount = max((context.walletBalance ?? 0) - pending.fee, 0)
            default: break
            }
            let remaining = max((context.walletBalance ?? 0) - newAmount - pending.fee, 0)

            smartFlow.pendingTransaction = PendingTransactionInfo(
                toAddress: pending.toAddress, amount: newAmount,
                fee: pending.fee, feeRate: pending.feeRate,
                estimatedMinutes: pending.estimatedMinutes
            )
            conversationState = .awaitingConfirmation(amount: newAmount, address: pending.toAddress, fee: pending.fee)
            smartFlow.activeFlow = conversationState

            return [.sendConfirmCard(
                toAddress: pending.toAddress, amount: newAmount,
                fee: pending.fee, feeRate: pending.feeRate,
                estimatedTime: pending.estimatedMinutes, remainingBalance: remaining
            )]
        }

        return [.text("What would you like to modify?")]
    }

    private func resolveFeeRate(level: FeeLevel, context: ConversationContext) -> Decimal {
        guard let estimates = context.currentFeeEstimates else { return 15 }
        switch level {
        case .slow: return estimates.slow
        case .fast: return estimates.fast
        case .medium, .custom: return estimates.medium
        }
    }

    private func resolveEstimatedTime(level: FeeLevel) -> Int {
        switch level {
        case .fast: return 10
        case .medium, .custom: return 20
        case .slow: return 60
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

        let _ = smartFlow.processMessage(.confirmAction, meaning: nil, memory: memory)

        guard let pending = smartFlow.pendingTransaction else {
            processing.failCurrentStep(error: L10n.Error.transactionFailed)
            smartFlow.markError(L10n.Error.transactionFailed)
            conversationState = .error(L10n.Error.transactionFailed)
            await dismissProcessingCard()
            let failText = ResponseTemplates.sendFailed(reason: L10n.Error.transactionFailed)
            messages.append(.ai(failText))
            conversationManager?.persistMessage(role: "assistant", content: failText)
            return
        }

        guard let walletState = walletState,
              let hdWallet = walletState.hdWallet else {
            processing.failCurrentStep(error: "Wallet not available")
            smartFlow.markError("Wallet not available")
            conversationState = .error("Wallet not available")
            await dismissProcessingCard()
            let failText = ResponseTemplates.sendFailed(reason: "Wallet not available. Please restart the app.")
            messages.append(.ai(failText))
            conversationManager?.persistMessage(role: "assistant", content: failText)
            return
        }

        do {
            // Step 1: Build transaction
            let amountSats = NSDecimalNumber(
                decimal: pending.amount * Constants.satoshisPerBTC
            ).uint64Value

            // Convert UTXOModel → UTXO (TransactionBuilder type)
            let spendableModels = walletState.utxoStore.spendableUTXOs()
            let utxos: [UTXO] = try spendableModels.compactMap { model in
                guard let path = model.derivationPath else { return nil }
                let scriptPubKey = try ScriptBuilder.scriptPubKey(for: model.address)
                guard let scriptType = ScriptType.from(address: model.address) else { return nil }
                return UTXO(
                    txid: model.txid,
                    vout: UInt32(model.vout),
                    amount: model.value,
                    amountSats: UInt64(model.valueSats),
                    scriptPubKey: scriptPubKey,
                    scriptType: scriptType,
                    address: model.address,
                    confirmations: model.confirmations,
                    derivationPath: path
                )
            }

            let changeAddress = try hdWallet.nextChangeAddress(
                type: walletState.preferredAddressType
            )

            let unsignedTx = try TransactionBuilder.build(
                utxos: utxos,
                toAddress: pending.toAddress,
                amount: amountSats,
                feeRate: pending.feeRate,
                changeAddress: changeAddress
            )

            processing.completeCurrentStep() // Step 1 done: "Building"

            // Step 2: Sign transaction
            var privateKeys: [String: Data] = [:]
            for input in unsignedTx.inputs {
                guard let path = input.utxo.derivationPath else {
                    throw TransactionError.signingFailed
                }
                privateKeys[path] = try hdWallet.privateKey(path: path)
            }

            let signedTx = try TransactionSigner.sign(
                transaction: unsignedTx,
                privateKeys: privateKeys
            )

            // Zero private key data after signing
            for key in privateKeys.keys {
                let count = privateKeys[key]?.count ?? 0
                privateKeys[key]?.resetBytes(in: 0..<count)
            }
            privateKeys.removeAll()

            processing.completeCurrentStep() // Step 2 done: "Signing"

            // Step 3: Broadcast
            let api = BlockbookAPI()
            let broadcastResult = try await api.sendTransaction(hex: signedTx.rawHex)
            let txid = broadcastResult.result

            processing.completeCurrentStep() // Step 3 done: "Broadcasting"

            // Success — mark flow completed
            smartFlow.markCompleted()
            conversationState = .completed

            // Mark consumed UTXOs as spent for immediate UI update
            for input in unsignedTx.inputs {
                walletState.utxoStore.markAsSpent(
                    txid: input.utxo.txid,
                    vout: Int(input.utxo.vout)
                )
            }

            await dismissProcessingCard()

            // Show success with real txid
            let successText = ResponseTemplates.sendSuccess(txid: txid)
            messages.append(.ai(successText))
            conversationManager?.persistMessage(role: "assistant", content: successText)
            let successCard = ChatMessage.aiCard(.successCard(
                txid: txid,
                amount: pending.amount,
                toAddress: pending.toAddress
            ))
            messages.append(successCard)
            conversationManager?.persistMessage(role: "assistant", content: successCard.content)

            // Record in memory
            var shownData = ShownData()
            shownData.sentTransaction = (txid: txid, amount: pending.amount, address: pending.toAddress, fee: Decimal(signedTx.fee) / Constants.satoshisPerBTC)
            memory.recordAIResponse(successText, shownData: shownData)

            // Trigger wallet refresh in background
            Task { await walletState.refresh() }

        } catch {
            // Handle any failure in build/sign/broadcast
            let reason = error.localizedDescription
            processing.failCurrentStep(error: reason)
            smartFlow.markError(reason)
            conversationState = .error(reason)
            await dismissProcessingCard()

            let failText = ResponseTemplates.sendFailed(reason: reason)
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
        smartFlow.markCompleted()
        conversationState = .completed
        let successText = ResponseTemplates.sendSuccess(txid: txid)
        messages.append(.ai(successText))
        conversationManager?.persistMessage(role: "assistant", content: successText)
        let card = ChatMessage.aiCard(.successCard(txid: txid, amount: amount, toAddress: toAddress))
        messages.append(card)
        conversationManager?.persistMessage(role: "assistant", content: card.content)
        isTyping = false

        // Record sent transaction in memory
        var shownData = ShownData()
        shownData.sentTransaction = (txid: txid, amount: amount, address: toAddress, fee: 0)
        memory.recordAIResponse(successText, shownData: shownData)
    }

    func handleTransactionFailure(reason: String) {
        smartFlow.markError(reason)
        conversationState = .error(reason)
        let failText = ResponseTemplates.sendFailed(reason: reason)
        messages.append(.ai(failText))
        conversationManager?.persistMessage(role: "assistant", content: failText)
        isTyping = false
    }

    func cancelTransaction() {
        smartFlow.reset()
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

    func openExplorer(txid: String) {
        guard let url = URL(string: Constants.blockExplorerURL + txid) else { return }
        UIApplication.shared.open(url)
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

    /// Marks a message as no longer new so its typing animation won't replay on scroll.
    /// Also tracks the ID in `animatedMessageIDs` as a bulletproof guard against
    /// SwiftUI recreating the cell with a stale `isNew` value.
    func markMessageAnimated(_ messageId: UUID) {
        animatedMessageIDs.insert(messageId)
        if let index = messages.firstIndex(where: { $0.id == messageId }) {
            messages[index].isNew = false
        }
    }

    func clearConversation() {
        messages.removeAll()
        smartFlow.reset()
        conversationState = .idle
        inputText = ""
        isTyping = false
        hasAutoTitled = false
        memory.reset()
        addGreeting()
    }

    // MARK: - Conversation Loading

    /// Loads messages from a conversation and sets it as current.
    func loadConversation(_ conversation: Conversation) {
        // Reset state
        messages.removeAll()
        smartFlow.reset()
        conversationState = .idle
        inputText = ""
        isTyping = false
        activeProcessingState = nil
        memory.reset()

        conversationManager?.switchTo(conversation)

        // Load persisted messages
        let persisted = conversationManager?.loadMessages() ?? []
        hasAutoTitled = persisted.contains(where: { $0.role == "user" })

        if persisted.isEmpty {
            // New/empty conversation — show greeting
            addGreeting()
        } else {
            // Reconstruct ChatMessage structs from persisted messages
            // isNew: false prevents typing animation on loaded history
            for msg in persisted {
                if msg.role == "user" {
                    messages.append(ChatMessage(
                        id: msg.id,
                        content: msg.content,
                        isFromUser: true,
                        timestamp: msg.timestamp,
                        isNew: false
                    ))
                } else {
                    messages.append(ChatMessage(
                        id: msg.id,
                        content: msg.content,
                        isFromUser: false,
                        timestamp: msg.timestamp,
                        responseType: .text(msg.content),
                        isNew: false
                    ))
                }
            }

            // Rebuild ConversationMemory from persisted messages
            // so reference resolution works in loaded conversations
            for msg in persisted {
                if msg.role == "user" {
                    let entities = entityExtractor.extract(from: msg.content)
                    let result = smartClassifier.classify(msg.content, memory: memory)
                    memory.recordUserMessage(msg.content, intent: result.intent, entities: entities)
                } else {
                    memory.recordAIResponse(msg.content, shownData: nil)
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
        let greetingText = ResponseTemplates.timeAwareGreeting()
        var greeting = ChatMessage.ai(greetingText)
        greeting.isNew = false  // Greeting shows instantly, no typing animation
        messages.append(greeting)
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

    func buildContext() -> ConversationContext {
        ConversationContext(
            walletBalance: walletBalance,
            fiatBalance: fiatBalance,
            pendingBalance: pendingBalance,
            utxoCount: utxoCount,
            pendingTransaction: smartFlow.pendingTransaction,
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
