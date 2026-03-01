// MARK: - ConversationFlow.swift
// Bitcoin AI Wallet
//
// Smart conversation state machine with:
// - Pausable flows (user can ask "what's my balance?" mid-send and resume)
// - Mid-flow modifications ("actually make it 0.05")
// - Graceful interruption handling
//
// Platform: iOS 17.0+
// Framework: Foundation, Combine (via ObservableObject)

import Foundation

// MARK: - ConversationState

/// The current state of a multi-step conversation flow.
enum ConversationState: Equatable {
    case idle
    case awaitingAmount(address: String)
    case awaitingAddress(amount: Decimal)
    case awaitingFeeLevel(amount: Decimal, address: String)
    case awaitingConfirmation(amount: Decimal, address: String, fee: Decimal)
    case processing
    case completed
    case error(String)

    static func == (lhs: ConversationState, rhs: ConversationState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.awaitingAmount(let a), .awaitingAmount(let b)): return a == b
        case (.awaitingAddress(let a), .awaitingAddress(let b)): return a == b
        case (.awaitingFeeLevel(let aAmt, let aAddr), .awaitingFeeLevel(let bAmt, let bAddr)):
            return aAmt == bAmt && aAddr == bAddr
        case (.awaitingConfirmation(let aAmt, let aAddr, let aFee),
              .awaitingConfirmation(let bAmt, let bAddr, let bFee)):
            return aAmt == bAmt && aAddr == bAddr && aFee == bFee
        case (.processing, .processing): return true
        case (.completed, .completed): return true
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - ConversationFlow

final class ConversationFlow: ObservableObject {

    // MARK: - FlowAction (scoped to ConversationFlow to avoid conflict with SmartConversationFlow)

    enum LegacyFlowAction {
        case advanceFlow(ConversationState)
        case pauseAndHandle(WalletIntent, resumeHint: String)
        case modifyFlow(ConversationState)
        case handleNormally(WalletIntent)
    }

    // MARK: - Published Properties

    @Published var state: ConversationState = .idle
    @Published var pendingTransaction: PendingTransactionInfo?

    /// A paused flow state that can be resumed after handling an interruption.
    @Published var pausedFlow: ConversationState?

    // MARK: - Constants

    private static let satoshisPerBTC: Decimal = 100_000_000
    private static let typicalVSize: Int = 140
    private static let defaultFeeRate: Decimal = 20

    /// Live fee estimates from the network.
    var liveFeeEstimates: (slow: Decimal, medium: Decimal, fast: Decimal)?

    // MARK: - Smart Flow API

    /// Processes a classified intent through the smart flow engine.
    /// Returns a FlowAction indicating how the ChatViewModel should handle it.
    @MainActor
    func processSmartIntent(_ intent: WalletIntent, memory: ConversationMemory) -> LegacyFlowAction {
        // If in an active send flow and user asks something unrelated → PAUSE
        if isInSendFlow(state) && isUnrelatedToSend(intent) {
            let hint = buildResumeHint(state)
            pausedFlow = state
            state = .idle
            return .pauseAndHandle(intent, resumeHint: hint)
        }

        // If there's a paused flow and user provides expected data → RESUME
        if let paused = pausedFlow, isResumingData(intent, for: paused) {
            state = paused
            pausedFlow = nil
            // Fall through to normal processing with the resumed state
        }

        // Normal processing
        let newState = processIntent(intent)
        return .advanceFlow(newState)
    }

    // MARK: - Legacy API

    /// Process a parsed intent and advance the conversation state machine.
    @discardableResult
    func processIntent(_ intent: WalletIntent) -> ConversationState {
        let newState: ConversationState

        switch (state, intent) {

        // MARK: Start a new send flow
        case (.idle, .send(let amount, let unit, let address, let feeLevel)):
            newState = handleNewSend(amount: amount, unit: unit, address: address, feeLevel: feeLevel)

        // MARK: Resolve missing amount
        case (.awaitingAmount(let address), .send(let amount, let unit, _, _)):
            if let amount = amount {
                let btcAmount = normalizeAmount(amount, unit: unit)
                newState = resolveAmount(btcAmount, address: address)
            } else {
                newState = state
            }

        case (.awaitingAmount(let address), .unknown(let rawText)):
            if let parsedAmount = Decimal(string: rawText.trimmingCharacters(in: .whitespacesAndNewlines)) {
                newState = resolveAmount(parsedAmount, address: address)
            } else {
                newState = state
            }

        // MARK: Resolve missing address
        case (.awaitingAddress(let amount), .send(_, _, let address, _)):
            if let address = address {
                newState = resolveAddress(address, amount: amount)
            } else {
                newState = state
            }

        case (.awaitingAddress(let amount), .unknown(let rawText)):
            let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            let validator = AddressValidator()
            if validator.isValid(trimmed) {
                newState = resolveAddress(trimmed, amount: amount)
            } else {
                newState = state
            }

        // MARK: Resolve fee level
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

        // MARK: Confirm action
        case (.awaitingConfirmation, .confirmAction):
            newState = .processing

        // MARK: Cancel from any active state
        case (.awaitingConfirmation, .cancelAction):
            reset()
            return .idle

        case (_, .cancelAction):
            reset()
            return .idle

        // MARK: New send during an active flow restarts
        case (_, .send(let amount, let unit, let address, let feeLevel))
            where state != .idle && state != .processing:
            newState = handleNewSend(amount: amount, unit: unit, address: address, feeLevel: feeLevel)

        // MARK: Pass-through
        default:
            newState = state
        }

        state = newState
        return newState
    }

    /// Resets the flow to idle.
    func reset() {
        state = .idle
        pendingTransaction = nil
        pausedFlow = nil
    }

    func markCompleted() {
        state = .completed
        pendingTransaction = nil
    }

    func markError(_ message: String) {
        state = .error(message)
        pendingTransaction = nil
    }

    func normalizeAmount(_ amount: Decimal, unit: BitcoinUnit?) -> Decimal {
        guard let unit = unit else { return amount }
        switch unit {
        case .btc: return amount
        case .sats, .satoshis: return amount / Self.satoshisPerBTC
        }
    }

    // MARK: - Pause / Resume Helpers

    /// Whether the current state is part of an active send flow.
    private func isInSendFlow(_ flowState: ConversationState) -> Bool {
        switch flowState {
        case .awaitingAddress, .awaitingAmount, .awaitingFeeLevel, .awaitingConfirmation:
            return true
        default:
            return false
        }
    }

    /// Whether this intent is unrelated to a send flow (can be handled without breaking it).
    private func isUnrelatedToSend(_ intent: WalletIntent) -> Bool {
        switch intent {
        case .balance, .feeEstimate, .price, .history, .help, .about,
             .walletHealth, .networkStatus, .utxoList, .receive,
             .newAddress, .hideBalance, .showBalance, .refreshWallet,
             .exportHistory, .greeting, .explain:
            return true
        case .convertAmount:
            return true
        default:
            return false
        }
    }

    /// Whether this intent provides data expected by the paused flow.
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

    /// Builds a human-readable hint about the paused flow.
    func buildResumeHint(_ flowState: ConversationState) -> String {
        switch flowState {
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

    // MARK: - Private Helpers

    private func handleNewSend(
        amount: Decimal?, unit: BitcoinUnit?,
        address: String?, feeLevel: FeeLevel?
    ) -> ConversationState {
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

    private func estimateFee(feeLevel: FeeLevel) -> Decimal {
        let ratePerVB: Decimal
        if let live = liveFeeEstimates {
            switch feeLevel {
            case .slow:   ratePerVB = live.slow
            case .medium: ratePerVB = live.medium
            case .fast:   ratePerVB = live.fast
            case .custom: ratePerVB = live.medium
            }
        } else {
            switch feeLevel {
            case .slow:   ratePerVB = 5
            case .medium: ratePerVB = Self.defaultFeeRate
            case .fast:   ratePerVB = 30
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
}
