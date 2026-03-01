// MARK: - SmartConversationFlow.swift
// Bitcoin AI Wallet
//
// Pausable, resumable, modifiable conversation flow.
// Replaces the rigid ConversationFlow with smart handling:
// - Pause: user asks "balance?" mid-send → pause, show balance, resume hint
// - Resume: user provides expected data → resume paused flow
// - Modify: "faster" / "cheaper" → modify fee in-flight
// - Evaluate: "too much" → let DynamicResponseBuilder handle
//
// Platform: iOS 17.0+

import Foundation

// MARK: - FlowAction

enum FlowAction {
    case advanceFlow(ConversationState)
    case handleNormally(WalletIntent)
    case pauseAndHandle(WalletIntent, resumeHint: String)
    case modifyFlow(field: String, newValue: String)
    case respondToMeaning(SentenceMeaning)
}

// MARK: - SmartConversationFlow

@MainActor
final class SmartConversationFlow: ObservableObject {
    @Published var activeFlow: ConversationState = .idle
    @Published var pausedFlow: ConversationState?
    @Published var pendingTransaction: PendingTransactionInfo?

    // MARK: - Constants

    private static let satoshisPerBTC: Decimal = 100_000_000
    private static let typicalVSize: Int = 140
    private static let defaultFeeRate: Decimal = 20

    var liveFeeEstimates: (slow: Decimal, medium: Decimal, fast: Decimal)?

    // MARK: - Public API

    func processMessage(_ intent: WalletIntent, meaning: SentenceMeaning?, memory: ConversationMemory) -> FlowAction {
        // Evaluation/question about last thing/emotional → let response builder handle
        if let m = meaning {
            // In awaitingFeeLevel, don't intercept evaluations — let fee parsing handle it
            // e.g., "normal is fine" should resolve to medium fee, not trigger evaluation
            let isAwaitingFee: Bool
            if case .awaitingFeeLevel = activeFlow { isAwaitingFee = true } else { isAwaitingFee = false }
            if m.type == .evaluation && !isAwaitingFee { return .respondToMeaning(m) }
            if m.type == .question && m.action == .explain && m.object == .lastMentioned { return .respondToMeaning(m) }
            if m.type == .emotional { return .respondToMeaning(m) }

            // Safety question in-flow: "Is this safe?" → answer without pausing
            if isInSendFlow(activeFlow) && m.type == .question && m.object == .wallet {
                return .respondToMeaning(m)
            }

            // Affordability question in-flow: "Can I afford this?" → answer without pausing
            if isInSendFlow(activeFlow) && m.action == .compare {
                return .respondToMeaning(m)
            }

            // "Wait" / "Hold on" during send flow → hesitation, NOT cancel.
            // Keep the flow active, just acknowledge.
            if isInSendFlow(activeFlow) && m.type == .command && m.action == .cancel {
                // Check if original word was "wait" / "hold" (not explicit "cancel" / "no")
                if !m.isNegated {
                    // Soft pause — return hesitation response without resetting flow
                    return .respondToMeaning(SentenceMeaning(
                        type: .emotional, action: nil, subject: nil, object: nil,
                        modifier: nil, emotion: .confusion, isNegated: false, confidence: 0.8
                    ))
                }
            }
        }

        // "?" during send flow → re-prompt, not pause for help
        if isInSendFlow(activeFlow), case .help = intent {
            return .advanceFlow(activeFlow) // Stay in current state, re-prompt
        }

        // In send flow + unrelated intent → PAUSE
        if isInSendFlow(activeFlow) && isUnrelated(intent) {
            pausedFlow = activeFlow
            let hint = buildResumeHint(activeFlow)
            activeFlow = .idle
            return .pauseAndHandle(intent, resumeHint: hint)
        }

        // In send flow + modification (comparative, quantifier)
        if isInSendFlow(activeFlow), let m = meaning, m.modifier != nil {
            return handleModification(m)
        }

        // Paused flow + resuming data → resume
        if let paused = pausedFlow, isResumingData(intent, for: paused) {
            activeFlow = paused
            pausedFlow = nil
            return .advanceFlow(processNormally(intent))
        }

        // Normal processing
        return .advanceFlow(processNormally(intent))
    }

    // MARK: - Flow State Queries

    func isInSendFlow(_ state: ConversationState) -> Bool {
        switch state {
        case .awaitingAmount, .awaitingAddress, .awaitingFeeLevel, .awaitingConfirmation:
            return true
        default:
            return false
        }
    }

    func reset() {
        activeFlow = .idle
        pausedFlow = nil
        pendingTransaction = nil
    }

    func markCompleted() {
        activeFlow = .completed
        pendingTransaction = nil
    }

    func markError(_ message: String) {
        activeFlow = .error(message)
        pendingTransaction = nil
    }

    // MARK: - Normal Processing (State Machine)

    private func processNormally(_ intent: WalletIntent) -> ConversationState {
        let newState: ConversationState

        switch (activeFlow, intent) {
        // Start a new send flow
        case (.idle, .send(let amount, let unit, let address, let feeLevel)):
            newState = handleNewSend(amount: amount, unit: unit, address: address, feeLevel: feeLevel)

        // Resolve missing amount
        case (.awaitingAmount(let address), .send(let amount, let unit, _, _)):
            if let amount = amount {
                let btcAmount = normalizeAmount(amount, unit: unit)
                newState = resolveAmount(btcAmount, address: address)
            } else {
                newState = activeFlow
            }

        case (.awaitingAmount(let address), .unknown(let rawText)):
            // Try EntityExtractor first (handles "0.0001 btc", "50000 sats", "$50")
            let extractor = EntityExtractor()
            let entities = extractor.extract(from: rawText)
            if let extractedAmount = entities.amount {
                let btcAmount = normalizeAmount(extractedAmount, unit: entities.unit)
                newState = resolveAmount(btcAmount, address: address)
            } else if let parsedAmount = Decimal(string: rawText.trimmingCharacters(in: .whitespacesAndNewlines)) {
                // Fallback: bare number parsing
                newState = resolveAmount(parsedAmount, address: address)
            } else {
                newState = activeFlow
            }

        // Resolve missing address
        case (.awaitingAddress(let amount), .send(_, _, let address, _)):
            if let address = address {
                newState = resolveAddress(address, amount: amount)
            } else {
                newState = activeFlow
            }

        case (.awaitingAddress(let amount), .unknown(let rawText)):
            let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            let validator = AddressValidator()
            if validator.isValid(trimmed) {
                newState = resolveAddress(trimmed, amount: amount)
            } else {
                newState = activeFlow
            }

        // Resolve fee level
        case (.awaitingFeeLevel(let amount, let address), .send(_, _, _, let feeLevel)):
            let level = feeLevel ?? .medium
            let fee = estimateFee(feeLevel: level)
            newState = .awaitingConfirmation(amount: amount, address: address, fee: fee)
            buildPendingTransaction(amount: amount, address: address, fee: fee, feeLevel: level)

        case (.awaitingFeeLevel(let amount, let address), .unknown(let rawText)):
            let level = parseFeeLevel(from: rawText)
            let fee = estimateFee(feeLevel: level)
            newState = .awaitingConfirmation(amount: amount, address: address, fee: fee)
            buildPendingTransaction(amount: amount, address: address, fee: fee, feeLevel: level)

        // Confirm/accept in awaitingFeeLevel → default to medium fee
        // Handles "normal is fine", "ok", "sure", "that's fine" when picking fee
        case (.awaitingFeeLevel(let amount, let address), .confirmAction):
            let fee = estimateFee(feeLevel: .medium)
            newState = .awaitingConfirmation(amount: amount, address: address, fee: fee)
            buildPendingTransaction(amount: amount, address: address, fee: fee, feeLevel: .medium)

        // Confirm
        case (.awaitingConfirmation, .confirmAction):
            newState = .processing

        // Cancel from any active state
        case (.awaitingConfirmation, .cancelAction):
            reset()
            return .idle

        case (_, .cancelAction):
            reset()
            return .idle

        // New send during active flow restarts
        case (_, .send(let amount, let unit, let address, let feeLevel))
            where activeFlow != .idle && activeFlow != .processing:
            newState = handleNewSend(amount: amount, unit: unit, address: address, feeLevel: feeLevel)

        // Pass-through
        default:
            newState = activeFlow
        }

        activeFlow = newState
        return newState
    }

    // MARK: - Modification Handling

    private func handleModification(_ meaning: SentenceMeaning) -> FlowAction {
        guard let modifier = meaning.modifier else { return .advanceFlow(activeFlow) }
        switch modifier {
        case .increase: return .modifyFlow(field: meaning.object == .fee ? "fee" : "amount", newValue: "increase")
        case .decrease: return .modifyFlow(field: meaning.object == .fee ? "fee" : "amount", newValue: "decrease")
        case .fastest: return .modifyFlow(field: "fee", newValue: "fast")
        case .cheapest: return .modifyFlow(field: "fee", newValue: "slow")
        case .half: return .modifyFlow(field: "amount", newValue: "half")
        case .double: return .modifyFlow(field: "amount", newValue: "double")
        case .all: return .modifyFlow(field: "amount", newValue: "max")
        default: return .advanceFlow(activeFlow)
        }
    }

    // MARK: - Resume Hint

    private func buildResumeHint(_ flow: ConversationState) -> String {
        switch flow {
        case .awaitingAmount(let addr):
            let truncated = addr.count > 16 ? "\(addr.prefix(8))...\(addr.suffix(6))" : addr
            return "\n\n{{dim:You were sending to \(truncated). Just tell me the amount when you're ready.}}"
        case .awaitingAddress(let amt):
            return "\n\n{{dim:You were about to send \(formatBTC(amt)) BTC. Give me the address when ready.}}"
        case .awaitingConfirmation(let amt, let addr, _):
            let truncated = addr.count > 16 ? "\(addr.prefix(8))...\(addr.suffix(6))" : addr
            return "\n\n{{dim:You have a pending send of \(formatBTC(amt)) BTC to \(truncated). Say **\"confirm\"** or **\"cancel\"**.}}"
        case .awaitingFeeLevel(let amt, let addr):
            let truncated = addr.count > 16 ? "\(addr.prefix(8))...\(addr.suffix(6))" : addr
            return "\n\n{{dim:Sending \(formatBTC(amt)) BTC to \(truncated). Pick a fee: **slow**, **medium**, or **fast**.}}"
        default:
            return ""
        }
    }

    // MARK: - Pause/Resume Helpers

    private func isUnrelated(_ intent: WalletIntent) -> Bool {
        switch intent {
        case .balance, .feeEstimate, .price, .history, .help, .about,
             .walletHealth, .networkStatus, .utxoList, .receive,
             .newAddress, .hideBalance, .showBalance, .refreshWallet,
             .exportHistory, .greeting:
            return true
        case .convertAmount:
            return true
        default:
            return false
        }
    }

    private func isResumingData(_ intent: WalletIntent, for paused: ConversationState) -> Bool {
        switch (paused, intent) {
        case (.awaitingAddress, .send(_, _, let addr, _)) where addr != nil:
            return true
        case (.awaitingAmount, .send(let amt, _, _, _)) where amt != nil:
            return true
        case (.awaitingConfirmation, .confirmAction):
            return true
        default:
            return false
        }
    }

    // MARK: - Send Flow Helpers

    private func handleNewSend(amount: Decimal?, unit: BitcoinUnit?, address: String?, feeLevel: FeeLevel?) -> ConversationState {
        let btcAmount: Decimal? = amount.map { normalizeAmount($0, unit: unit) }

        let validatedAddress: String?
        if let addr = address {
            let validator = AddressValidator()
            guard !validator.isTestnet(addr) else {
                return .error(L10n.Chat.testnetNotSupported)
            }
            validatedAddress = validator.isValid(addr) ? addr : nil
        } else {
            validatedAddress = nil
        }

        switch (btcAmount, validatedAddress) {
        case (.some(let amt), .some(let addr)):
            let level = feeLevel ?? .medium
            let fee = estimateFee(feeLevel: level)
            buildPendingTransaction(amount: amt, address: addr, fee: fee, feeLevel: level)
            return .awaitingConfirmation(amount: amt, address: addr, fee: fee)
        case (.some(let amt), .none):
            return .awaitingAddress(amount: amt)
        case (.none, .some(let addr)):
            return .awaitingAmount(address: addr)
        case (.none, .none):
            return .awaitingAddress(amount: 0)
        }
    }

    private func resolveAmount(_ amount: Decimal, address: String) -> ConversationState {
        guard amount > 0 else { return .error(L10n.Error.invalidAmount) }
        let fee = estimateFee(feeLevel: .medium)
        buildPendingTransaction(amount: amount, address: address, fee: fee, feeLevel: .medium)
        return .awaitingConfirmation(amount: amount, address: address, fee: fee)
    }

    private func resolveAddress(_ address: String, amount: Decimal) -> ConversationState {
        let validator = AddressValidator()
        guard !validator.isTestnet(address) else {
            return .error(L10n.Chat.testnetNotSupported)
        }
        guard validator.isValid(address) else {
            return .error(L10n.Chat.invalidAddress)
        }
        if amount > 0 {
            let fee = estimateFee(feeLevel: .medium)
            buildPendingTransaction(amount: amount, address: address, fee: fee, feeLevel: .medium)
            return .awaitingConfirmation(amount: amount, address: address, fee: fee)
        } else {
            return .awaitingAmount(address: address)
        }
    }

    func normalizeAmount(_ amount: Decimal, unit: BitcoinUnit?) -> Decimal {
        guard let unit = unit else { return amount }
        switch unit {
        case .btc: return amount
        case .sats, .satoshis: return amount / Self.satoshisPerBTC
        }
    }

    // MARK: - Fee Estimation

    private func estimateFee(feeLevel: FeeLevel) -> Decimal {
        let ratePerVB: Decimal
        if let live = liveFeeEstimates {
            switch feeLevel {
            case .slow: ratePerVB = live.slow
            case .medium: ratePerVB = live.medium
            case .fast: ratePerVB = live.fast
            case .custom: ratePerVB = live.medium
            }
        } else {
            switch feeLevel {
            case .slow: ratePerVB = 8
            case .medium: ratePerVB = Self.defaultFeeRate
            case .fast: ratePerVB = 40
            case .custom: ratePerVB = Self.defaultFeeRate
            }
        }
        return (ratePerVB * Decimal(Self.typicalVSize)) / Self.satoshisPerBTC
    }

    private func estimatedMinutes(for level: FeeLevel) -> Int {
        switch level {
        case .fast: return 10
        case .medium, .custom: return 20
        case .slow: return 60
        }
    }

    private func feeRate(for level: FeeLevel) -> Decimal {
        if let live = liveFeeEstimates {
            switch level {
            case .slow: return live.slow
            case .medium, .custom: return live.medium
            case .fast: return live.fast
            }
        }
        switch level {
        case .slow: return 8
        case .medium, .custom: return Self.defaultFeeRate
        case .fast: return 40
        }
    }

    private func buildPendingTransaction(amount: Decimal, address: String, fee: Decimal, feeLevel: FeeLevel) {
        pendingTransaction = PendingTransactionInfo(
            toAddress: address, amount: amount, fee: fee,
            feeRate: feeRate(for: feeLevel),
            estimatedMinutes: estimatedMinutes(for: feeLevel)
        )
    }

    private func parseFeeLevel(from text: String) -> FeeLevel {
        let lowered = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let fastKeys = ["fast", "priority", "urgent", "high", "rush", "asap", "quick"]
        let slowKeys = ["slow", "low", "economy", "cheap", "saver", "eco"]
        for kw in fastKeys where lowered.contains(kw) { return .fast }
        for kw in slowKeys where lowered.contains(kw) { return .slow }
        return .medium
    }

    private func formatBTC(_ amount: Decimal) -> String {
        let handler = NSDecimalNumberHandler(
            roundingMode: .plain, scale: 8,
            raiseOnExactness: false, raiseOnOverflow: false,
            raiseOnUnderflow: false, raiseOnDivideByZero: false
        )
        return NSDecimalNumber(decimal: amount).rounding(accordingToBehavior: handler).stringValue
    }

    // MARK: - Error Recovery

    func handleSendError(_ error: String, memory: ConversationMemory) -> [ResponseType] {
        var responses: [ResponseType] = [.errorText(error)]

        if error.lowercased().contains("insufficient") || error.lowercased().contains("not enough") {
            let bal = memory.lastShownBalance ?? 0
            responses.append(.text("You have **\(formatBTC(bal))** available. Want to send a smaller amount?"))
        } else if error.lowercased().contains("network") || error.lowercased().contains("connection") {
            responses.append(.text("Check your connection and try again. Nothing was sent — your funds are safe."))
        } else if error.lowercased().contains("invalid address") {
            responses.append(.text("That address doesn't look right. Double-check it and try again."))
        } else {
            responses.append(.text("Want to try again, or do something else?"))
        }
        return responses
    }
}
