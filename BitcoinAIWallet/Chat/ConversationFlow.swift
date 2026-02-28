// MARK: - ConversationFlow.swift
// Bitcoin AI Wallet
//
// Manages the multi-step conversation state machine for the chat engine.
// Tracks where the user is in a multi-turn flow (e.g., building a send
// transaction step by step) and resolves missing information as the user
// provides it across multiple messages.
//
// Platform: iOS 17.0+
// Framework: Foundation, Combine (via ObservableObject)

import Foundation

// MARK: - ConversationState

/// The current state of a multi-step conversation flow.
///
/// The chat engine uses this to know which piece of information to request next
/// and how to interpret the user's follow-up messages.
enum ConversationState: Equatable {

    /// No active multi-step flow. The user can issue any command.
    case idle

    /// Waiting for the user to provide a send amount.
    /// The destination address has already been captured.
    case awaitingAmount(address: String)

    /// Waiting for the user to provide a destination address.
    /// The send amount has already been captured.
    case awaitingAddress(amount: Decimal)

    /// Waiting for the user to select a fee level.
    /// Both amount and address have been captured.
    case awaitingFeeLevel(amount: Decimal, address: String)

    /// Waiting for the user to confirm the transaction.
    /// All transaction parameters are known.
    case awaitingConfirmation(amount: Decimal, address: String, fee: Decimal)

    /// A transaction is being signed and broadcast.
    case processing

    /// The flow completed successfully.
    case completed

    /// The flow ended with an error.
    case error(String)

    // MARK: - Equatable

    static func == (lhs: ConversationState, rhs: ConversationState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle):
            return true
        case (.awaitingAmount(let a), .awaitingAmount(let b)):
            return a == b
        case (.awaitingAddress(let a), .awaitingAddress(let b)):
            return a == b
        case (.awaitingFeeLevel(let aAmt, let aAddr), .awaitingFeeLevel(let bAmt, let bAddr)):
            return aAmt == bAmt && aAddr == bAddr
        case (.awaitingConfirmation(let aAmt, let aAddr, let aFee),
              .awaitingConfirmation(let bAmt, let bAddr, let bFee)):
            return aAmt == bAmt && aAddr == bAddr && aFee == bFee
        case (.processing, .processing):
            return true
        case (.completed, .completed):
            return true
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - ConversationFlow

/// Manages the multi-step conversation state machine.
///
/// The flow object is owned by the ``ChatViewModel`` and updated each time
/// the user sends a message. It determines whether a new intent starts a
/// fresh flow or contributes missing information to an in-progress flow.
///
/// ```swift
/// let flow = ConversationFlow()
/// let intent = WalletIntent.send(amount: nil, unit: nil, address: "bc1q...", feeLevel: nil)
/// let next = flow.processIntent(intent)
/// // next == .awaitingAmount(address: "bc1q...")
/// ```
final class ConversationFlow: ObservableObject {

    // MARK: - Published Properties

    /// The current conversation state, observed by the UI for display updates.
    @Published var state: ConversationState = .idle

    /// Details of the transaction being built, populated once all parameters are known.
    @Published var pendingTransaction: PendingTransactionInfo?

    // MARK: - Constants

    /// Number of satoshis in one BTC.
    private static let satoshisPerBTC: Decimal = 100_000_000

    /// Typical transaction virtual size in vBytes, used for fee estimation.
    private static let typicalVSize: Int = 140

    /// Default medium fee rate (sat/vB) when estimates are unavailable.
    private static let defaultFeeRate: Decimal = 15

    /// Live fee estimates from the network, set by ChatViewModel.
    /// When available, these override the hardcoded defaults.
    var liveFeeEstimates: (slow: Decimal, medium: Decimal, fast: Decimal)?

    // MARK: - Public API

    /// Process a parsed intent and advance the conversation state machine.
    ///
    /// The method inspects both the current state and the incoming intent to
    /// decide the next state. For non-send intents, the state passes through
    /// unchanged (the caller handles them statelessly).
    ///
    /// - Parameter intent: The parsed ``WalletIntent`` from user input.
    /// - Returns: The new ``ConversationState`` after processing.
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
                // User said something but did not provide an amount — stay in same state
                newState = state
            }

        // MARK: Resolve missing amount from bare number input
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

        // MARK: Resolve missing address from bare address input
        case (.awaitingAddress(let amount), .unknown(let rawText)):
            let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            let validator = AddressValidator()
            if validator.isValid(trimmed) {
                newState = resolveAddress(trimmed, amount: amount)
            } else {
                newState = state
            }

        // MARK: Resolve fee level selection
        case (.awaitingFeeLevel(let amount, let address), .send(_, _, _, let feeLevel)):
            if let level = feeLevel {
                let fee = estimateFee(feeLevel: level)
                newState = .awaitingConfirmation(amount: amount, address: address, fee: fee)
                buildPendingTransaction(amount: amount, address: address, fee: fee, feeLevel: level)
            } else {
                // Default to medium if user doesn't specify
                let fee = estimateFee(feeLevel: .medium)
                newState = .awaitingConfirmation(amount: amount, address: address, fee: fee)
                buildPendingTransaction(amount: amount, address: address, fee: fee, feeLevel: .medium)
            }

        // MARK: Resolve fee level from bare text
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

        // MARK: Pass-through for non-send intents
        default:
            newState = state
        }

        state = newState
        return newState
    }

    /// Resets the flow to the idle state, clearing any pending transaction.
    func reset() {
        state = .idle
        pendingTransaction = nil
    }

    /// Marks the flow as completed after a successful broadcast.
    func markCompleted() {
        state = .completed
        pendingTransaction = nil
    }

    /// Marks the flow as failed with an error message.
    ///
    /// - Parameter message: A human-readable error description.
    func markError(_ message: String) {
        state = .error(message)
        pendingTransaction = nil
    }

    // MARK: - Amount Normalization

    /// Converts an amount from its declared unit to BTC.
    ///
    /// - Parameters:
    ///   - amount: The raw numeric amount.
    ///   - unit: The declared unit, or `nil` (treated as BTC).
    /// - Returns: The amount in BTC.
    func normalizeAmount(_ amount: Decimal, unit: BitcoinUnit?) -> Decimal {
        guard let unit = unit else { return amount }
        switch unit {
        case .btc:
            return amount
        case .sats, .satoshis:
            return amount / Self.satoshisPerBTC
        }
    }

    // MARK: - Private Helpers

    /// Handles the start of a new send flow, determining which piece of info is missing.
    private func handleNewSend(
        amount: Decimal?,
        unit: BitcoinUnit?,
        address: String?,
        feeLevel: FeeLevel?
    ) -> ConversationState {

        let btcAmount: Decimal?
        if let raw = amount {
            btcAmount = normalizeAmount(raw, unit: unit)
        } else {
            btcAmount = nil
        }

        // Validate address if provided
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
            // Both present — move to fee selection or confirmation
            if let level = feeLevel {
                let fee = estimateFee(feeLevel: level)
                buildPendingTransaction(amount: amt, address: addr, fee: fee, feeLevel: level)
                return .awaitingConfirmation(amount: amt, address: addr, fee: fee)
            } else {
                // Default to medium fee and go straight to confirmation
                let fee = estimateFee(feeLevel: .medium)
                buildPendingTransaction(amount: amt, address: addr, fee: fee, feeLevel: .medium)
                return .awaitingConfirmation(amount: amt, address: addr, fee: fee)
            }

        case (.some(let amt), .none):
            // Have amount, need address
            return .awaitingAddress(amount: amt)

        case (.none, .some(let addr)):
            // Have address, need amount
            return .awaitingAmount(address: addr)

        case (.none, .none):
            // Need both — ask for address first (conventional order)
            return .awaitingAddress(amount: 0)
        }
    }

    /// Resolves a newly provided amount and advances the state.
    private func resolveAmount(_ amount: Decimal, address: String) -> ConversationState {
        guard amount > 0 else {
            return .error(L10n.Error.invalidAmount)
        }
        // Default to medium fee and go to confirmation
        let fee = estimateFee(feeLevel: .medium)
        buildPendingTransaction(amount: amount, address: address, fee: fee, feeLevel: .medium)
        return .awaitingConfirmation(amount: amount, address: address, fee: fee)
    }

    /// Resolves a newly provided address and advances the state.
    private func resolveAddress(_ address: String, amount: Decimal) -> ConversationState {
        let validator = AddressValidator()
        guard !validator.isTestnet(address) else {
            return .error(L10n.Chat.testnetNotSupported)
        }
        guard validator.isValid(address) else {
            return .error(L10n.Chat.invalidAddress)
        }

        if amount > 0 {
            // Both amount and address are now known
            let fee = estimateFee(feeLevel: .medium)
            buildPendingTransaction(amount: amount, address: address, fee: fee, feeLevel: .medium)
            return .awaitingConfirmation(amount: amount, address: address, fee: fee)
        } else {
            // Amount was a placeholder zero — need the real amount
            return .awaitingAmount(address: address)
        }
    }

    /// Estimates the fee in BTC for a typical transaction at the given fee level.
    /// Uses live network fee estimates when available, falls back to defaults.
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

        let feeSats = ratePerVB * Decimal(Self.typicalVSize)
        return feeSats / Self.satoshisPerBTC
    }

    /// Returns the estimated confirmation time in minutes for a fee level.
    private func estimatedMinutes(for level: FeeLevel) -> Int {
        switch level {
        case .fast: return 10
        case .medium, .custom: return 20
        case .slow: return 60
        }
    }

    /// Returns the fee rate in sat/vB for a given level.
    private func feeRate(for level: FeeLevel) -> Decimal {
        switch level {
        case .slow: return 5
        case .medium, .custom: return Self.defaultFeeRate
        case .fast: return 30
        }
    }

    /// Populates the ``pendingTransaction`` with all known parameters.
    private func buildPendingTransaction(
        amount: Decimal,
        address: String,
        fee: Decimal,
        feeLevel: FeeLevel
    ) {
        pendingTransaction = PendingTransactionInfo(
            toAddress: address,
            amount: amount,
            fee: fee,
            feeRate: feeRate(for: feeLevel),
            estimatedMinutes: estimatedMinutes(for: feeLevel)
        )
    }

    /// Attempts to parse a fee level from free-form text.
    private func parseFeeLevel(from text: String) -> FeeLevel {
        let lowered = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        let fastKeywords = ["fast", "priority", "urgent", "high", "rush", "asap", "quick"]
        let slowKeywords = ["slow", "low", "economy", "cheap", "saver", "eco"]

        for keyword in fastKeywords where lowered.contains(keyword) {
            return .fast
        }
        for keyword in slowKeywords where lowered.contains(keyword) {
            return .slow
        }

        return .medium
    }
}
