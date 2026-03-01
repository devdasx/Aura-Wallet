// MARK: - SmartConversationFlow.swift
// Bitcoin AI Wallet
//
// Pausable, resumable, modifiable conversation flow.
// Replaces the rigid ConversationFlow with smart handling:
// - Pause: user asks "balance?" mid-send -> pause, show balance, resume hint
// - Resume: user provides expected data -> resume paused flow
// - Modify: "faster" / "cheaper" -> modify fee in-flight
// - Re-entry: "change amount" / "change address" -> go back without losing data
// - Evaluate: "too much" -> let DynamicResponseBuilder handle
//
// State machine:
//   idle -> awaitingAmount -> awaitingAddress -> awaitingFeeLevel -> awaitingConfirmation -> processing -> completed
//   Any state -> idle (on cancel)
//   Any state -> error (on failure)
//   Partial info can skip states (e.g., amount+address given -> awaitingFeeLevel)
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
    private static let maxDecimalPlaces: Int16 = 8

    var liveFeeEstimates: (slow: Decimal, medium: Decimal, fast: Decimal)?

    // MARK: - Public API

    func processMessage(_ intent: WalletIntent, meaning: SentenceMeaning?, memory: ConversationMemory) -> FlowAction {
        // Evaluation/question about last thing/emotional -> let response builder handle
        if let m = meaning {
            // In awaitingFeeLevel, don't intercept evaluations -- let fee parsing handle it
            // e.g., "normal is fine" should resolve to medium fee, not trigger evaluation
            let isAwaitingFee: Bool
            if case .awaitingFeeLevel = activeFlow { isAwaitingFee = true } else { isAwaitingFee = false }
            if m.type == .evaluation && !isAwaitingFee { return .respondToMeaning(m) }
            if m.type == .question && m.action == .explain && m.object == .lastMentioned { return .respondToMeaning(m) }
            if m.type == .emotional { return .respondToMeaning(m) }

            // Safety question in-flow: "Is this safe?" -> answer without pausing
            if isInSendFlow(activeFlow) && m.type == .question && m.object == .wallet {
                return .respondToMeaning(m)
            }

            // Affordability question in-flow: "Can I afford this?" -> answer without pausing
            if isInSendFlow(activeFlow) && m.action == .compare {
                return .respondToMeaning(m)
            }

            // "Wait" / "Hold on" during send flow -> hesitation, NOT cancel.
            // Keep the flow active, just acknowledge.
            if isInSendFlow(activeFlow) && m.type == .command && m.action == .cancel {
                // Check if original word was "wait" / "hold" (not explicit "cancel" / "no")
                if !m.isNegated {
                    // Soft pause -- return hesitation response without resetting flow
                    return .respondToMeaning(SentenceMeaning(
                        type: .emotional, action: nil, subject: nil, object: nil,
                        modifier: nil, emotion: .confusion, isNegated: false, confidence: 0.8
                    ))
                }
            }
        }

        // "?" during send flow -> re-prompt with contextual help, not pause for help
        if isInSendFlow(activeFlow), case .help = intent {
            return .advanceFlow(activeFlow) // Stay in current state, re-prompt
        }

        // Fee estimate request during awaitingFeeLevel -> show fees without pausing
        if case .awaitingFeeLevel = activeFlow, case .feeEstimate = intent {
            pausedFlow = activeFlow
            let hint = buildResumeHint(activeFlow)
            // Don't reset activeFlow -- keep it so we can resume
            return .pauseAndHandle(intent, resumeHint: hint)
        }

        // Re-entry handling: "change amount", "change address", "change fee"
        if isInSendFlow(activeFlow), let reEntry = handleReEntry(intent, meaning: meaning) {
            return reEntry
        }

        // In send flow + modification (comparative, quantifier) — MUST run before isUnrelated
        // so "Faster"/"Cheaper" during confirmation modifies the fee, not pauses the flow.
        if isInSendFlow(activeFlow), let m = meaning, m.modifier != nil {
            return handleModification(m)
        }

        // In send flow + unrelated intent -> PAUSE
        if isInSendFlow(activeFlow) && isUnrelated(intent) {
            pausedFlow = activeFlow
            let hint = buildResumeHint(activeFlow)
            activeFlow = .idle
            return .pauseAndHandle(intent, resumeHint: hint)
        }

        // Paused flow + resuming data -> resume
        if let paused = pausedFlow, isResumingData(intent, for: paused) {
            activeFlow = paused
            pausedFlow = nil
            return .advanceFlow(processNormally(intent))
        }

        // Normal processing
        return .advanceFlow(processNormally(intent))
    }

    // MARK: - Flow State Queries

    /// Returns true when the flow is in any active send state.
    /// Includes: awaitingAmount, awaitingAddress, awaitingFeeLevel, awaitingConfirmation, processing.
    /// Returns false for: idle, completed, error.
    func isInSendFlow(_ state: ConversationState) -> Bool {
        switch state {
        case .awaitingAmount, .awaitingAddress, .awaitingFeeLevel,
             .awaitingConfirmation, .processing:
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
        // Keep pendingTransaction so the user can retry or modify
    }

    // MARK: - Re-entry Handling

    /// Handles "change amount", "change address", "change fee" to go back in the flow
    /// without losing already-collected data.
    private func handleReEntry(_ intent: WalletIntent, meaning: SentenceMeaning?) -> FlowAction? {
        // Check for explicit modification actions via SentenceMeaning
        if let m = meaning, case .modify(let what) = m.action {
            let lowered = what.lowercased()
            if lowered.contains("amount") || lowered.contains("value") {
                return handleChangeAmount()
            }
            if lowered.contains("address") || lowered.contains("destination") || lowered.contains("recipient") {
                return handleChangeAddress()
            }
            if lowered.contains("fee") || lowered.contains("speed") || lowered.contains("priority") {
                return handleChangeFee()
            }
        }

        // During confirmation: user provides a new send intent with different amount -> update
        if case .awaitingConfirmation(_, let addr, _) = activeFlow,
           case .send(let newAmt, let newUnit, let newAddr, let newFee) = intent {
            if let amt = newAmt {
                let btcAmount = truncateToMaxDecimals(normalizeAmount(amt, unit: newUnit))
                guard btcAmount > 0 else { return .advanceFlow(.error(L10n.Error.invalidAmount)) }
                let effectiveAddr = newAddr ?? addr
                let level = newFee ?? feeLevelFromRate(pendingTransaction?.feeRate)
                let fee = estimateFee(feeLevel: level)
                buildPendingTransaction(amount: btcAmount, address: effectiveAddr, fee: fee, feeLevel: level)
                activeFlow = .awaitingConfirmation(amount: btcAmount, address: effectiveAddr, fee: fee)
                return .advanceFlow(activeFlow)
            }
        }

        return nil
    }

    /// Go back to awaitingAmount, keeping the address if we have it.
    private func handleChangeAmount() -> FlowAction {
        let address: String
        switch activeFlow {
        case .awaitingFeeLevel(_, let addr): address = addr
        case .awaitingConfirmation(_, let addr, _): address = addr
        default: address = ""
        }
        pendingTransaction = nil
        activeFlow = .awaitingAmount(address: address)
        return .advanceFlow(activeFlow)
    }

    /// Go back to awaitingAddress, keeping the amount if we have it.
    private func handleChangeAddress() -> FlowAction {
        let amount: Decimal
        switch activeFlow {
        case .awaitingFeeLevel(let amt, _): amount = amt
        case .awaitingConfirmation(let amt, _, _): amount = amt
        case .awaitingAmount: amount = 0
        default: amount = 0
        }
        pendingTransaction = nil
        activeFlow = .awaitingAddress(amount: amount)
        return .advanceFlow(activeFlow)
    }

    /// Go back to awaitingFeeLevel, keeping amount and address.
    private func handleChangeFee() -> FlowAction {
        switch activeFlow {
        case .awaitingConfirmation(let amt, let addr, _):
            pendingTransaction = nil
            activeFlow = .awaitingFeeLevel(amount: amt, address: addr)
            return .advanceFlow(activeFlow)
        default:
            return .advanceFlow(activeFlow)
        }
    }

    // MARK: - Normal Processing (State Machine)

    private func processNormally(_ intent: WalletIntent) -> ConversationState {
        let newState: ConversationState

        switch (activeFlow, intent) {

        // ──────────────────────────────────────────────
        // MARK: Start a new send flow from idle
        // ──────────────────────────────────────────────
        case (.idle, .send(let amount, let unit, let address, let feeLevel)):
            newState = handleNewSend(amount: amount, unit: unit, address: address, feeLevel: feeLevel)

        // ──────────────────────────────────────────────
        // MARK: awaitingAmount - resolve missing amount
        // ──────────────────────────────────────────────

        // User provides a send intent with an amount (and possibly other fields)
        case (.awaitingAmount(let storedAddress), .send(let amount, let unit, let newAddress, let feeLevel)):
            if let amount = amount {
                let btcAmount = truncateToMaxDecimals(normalizeAmount(amount, unit: unit))
                guard btcAmount > 0 else {
                    newState = .error(L10n.Error.invalidAmount)
                    break
                }
                // If they also provided an address, use it (override stored one)
                let effectiveAddress = newAddress ?? (storedAddress.isEmpty ? nil : storedAddress)

                if let addr = effectiveAddress {
                    // Validate the address
                    switch validateAddress(addr) {
                    case .valid(let validAddr):
                        if let feeLevel = feeLevel {
                            // Have all three: amount, address, fee
                            let fee = estimateFee(feeLevel: feeLevel)
                            buildPendingTransaction(amount: btcAmount, address: validAddr, fee: fee, feeLevel: feeLevel)
                            newState = .awaitingConfirmation(amount: btcAmount, address: validAddr, fee: fee)
                        } else {
                            // Have amount and address, need fee
                            newState = .awaitingFeeLevel(amount: btcAmount, address: validAddr)
                        }
                    case .testnet:
                        newState = .error(L10n.Chat.testnetNotSupported)
                    case .invalid:
                        // Bad address, but we have the amount -- ask for address
                        newState = .awaitingAddress(amount: btcAmount)
                    }
                } else {
                    // Have amount but no address
                    newState = .awaitingAddress(amount: btcAmount)
                }
            } else if let newAddress = newAddress {
                // User provided address but not amount -- store the address, still need amount
                switch validateAddress(newAddress) {
                case .valid(let validAddr):
                    newState = .awaitingAmount(address: validAddr)
                case .testnet:
                    newState = .error(L10n.Chat.testnetNotSupported)
                case .invalid:
                    newState = activeFlow // Invalid address, stay and re-prompt for amount
                }
            } else {
                newState = activeFlow // No useful data, re-prompt
            }

        // User types a bare number or amount string while awaiting amount
        case (.awaitingAmount(let storedAddress), .unknown(let rawText)):
            // Try EntityExtractor first (handles "0.0001 btc", "50000 sats", "$50")
            let extractor = EntityExtractor()
            let entities = extractor.extract(from: rawText)
            if let extractedAmount = entities.amount {
                let btcAmount = truncateToMaxDecimals(normalizeAmount(extractedAmount, unit: entities.unit))
                guard btcAmount > 0 else {
                    newState = .error(L10n.Error.invalidAmount)
                    break
                }
                // Check if an address was also extracted
                let addr = entities.address ?? (storedAddress.isEmpty ? nil : storedAddress)
                if let addr = addr {
                    switch validateAddress(addr) {
                    case .valid(let validAddr):
                        newState = .awaitingFeeLevel(amount: btcAmount, address: validAddr)
                    case .testnet:
                        newState = .error(L10n.Chat.testnetNotSupported)
                    case .invalid:
                        newState = .awaitingAddress(amount: btcAmount)
                    }
                } else {
                    newState = .awaitingAddress(amount: btcAmount)
                }
            } else if let parsedAmount = Decimal(string: rawText.trimmingCharacters(in: .whitespacesAndNewlines)) {
                // Fallback: bare number parsing (treated as BTC)
                let truncated = truncateToMaxDecimals(parsedAmount)
                guard truncated > 0 else {
                    newState = .error(L10n.Error.invalidAmount)
                    break
                }
                if storedAddress.isEmpty {
                    newState = .awaitingAddress(amount: truncated)
                } else {
                    newState = .awaitingFeeLevel(amount: truncated, address: storedAddress)
                }
            } else {
                // Maybe user pasted an address while we expected amount
                let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
                switch validateAddress(trimmed) {
                case .valid(let validAddr):
                    // Store the address, still need amount
                    newState = .awaitingAmount(address: validAddr)
                case .testnet:
                    newState = .error(L10n.Chat.testnetNotSupported)
                case .invalid:
                    newState = activeFlow // Unrecognized input, re-prompt
                }
            }

        // ──────────────────────────────────────────────
        // MARK: awaitingAddress - resolve missing address
        // ──────────────────────────────────────────────

        // User provides a send intent with an address
        case (.awaitingAddress(let storedAmount), .send(let newAmount, let newUnit, let address, let feeLevel)):
            if let address = address {
                // Optionally update the amount if user provided one
                let effectiveAmount: Decimal
                if let newAmt = newAmount {
                    effectiveAmount = truncateToMaxDecimals(normalizeAmount(newAmt, unit: newUnit))
                } else {
                    effectiveAmount = storedAmount
                }

                switch validateAddress(address) {
                case .valid(let validAddr):
                    if effectiveAmount > 0 {
                        if let feeLevel = feeLevel {
                            let fee = estimateFee(feeLevel: feeLevel)
                            buildPendingTransaction(amount: effectiveAmount, address: validAddr, fee: fee, feeLevel: feeLevel)
                            newState = .awaitingConfirmation(amount: effectiveAmount, address: validAddr, fee: fee)
                        } else {
                            newState = .awaitingFeeLevel(amount: effectiveAmount, address: validAddr)
                        }
                    } else {
                        // Have address but amount is still 0/missing
                        newState = .awaitingAmount(address: validAddr)
                    }
                case .testnet:
                    newState = .error(L10n.Chat.testnetNotSupported)
                case .invalid:
                    newState = activeFlow // Invalid address, stay and re-prompt
                }
            } else if let newAmt = newAmount {
                // User changed the amount while we were waiting for address
                let btcAmount = truncateToMaxDecimals(normalizeAmount(newAmt, unit: newUnit))
                newState = .awaitingAddress(amount: btcAmount)
            } else {
                newState = activeFlow
            }

        // User types a raw address string
        case (.awaitingAddress(let storedAmount), .unknown(let rawText)):
            let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            switch validateAddress(trimmed) {
            case .valid(let validAddr):
                if storedAmount > 0 {
                    newState = .awaitingFeeLevel(amount: storedAmount, address: validAddr)
                } else {
                    newState = .awaitingAmount(address: validAddr)
                }
            case .testnet:
                newState = .error(L10n.Chat.testnetNotSupported)
            case .invalid:
                // Maybe they typed an amount instead of an address
                let extractor = EntityExtractor()
                let entities = extractor.extract(from: rawText)
                if let extractedAmount = entities.amount {
                    let btcAmount = truncateToMaxDecimals(normalizeAmount(extractedAmount, unit: entities.unit))
                    // Update amount, still need address
                    newState = .awaitingAddress(amount: btcAmount)
                } else {
                    newState = activeFlow // Stay and re-prompt
                }
            }

        // ──────────────────────────────────────────────
        // MARK: awaitingFeeLevel - resolve fee selection
        // ──────────────────────────────────────────────

        // User selects fee via send intent
        case (.awaitingFeeLevel(let amount, let address), .send(_, _, _, let feeLevel)):
            let level = feeLevel ?? .medium
            let fee = estimateFee(feeLevel: level)
            newState = .awaitingConfirmation(amount: amount, address: address, fee: fee)
            buildPendingTransaction(amount: amount, address: address, fee: fee, feeLevel: level)

        // User types fee level as text
        case (.awaitingFeeLevel(let amount, let address), .unknown(let rawText)):
            let level = parseFeeLevel(from: rawText)
            let fee = estimateFee(feeLevel: level)
            newState = .awaitingConfirmation(amount: amount, address: address, fee: fee)
            buildPendingTransaction(amount: amount, address: address, fee: fee, feeLevel: level)

        // Confirm/accept in awaitingFeeLevel -> default to medium fee
        // Handles "normal is fine", "ok", "sure", "that's fine"
        case (.awaitingFeeLevel(let amount, let address), .confirmAction):
            let fee = estimateFee(feeLevel: .medium)
            newState = .awaitingConfirmation(amount: amount, address: address, fee: fee)
            buildPendingTransaction(amount: amount, address: address, fee: fee, feeLevel: .medium)

        // ──────────────────────────────────────────────
        // MARK: awaitingConfirmation - confirm or cancel
        // ──────────────────────────────────────────────

        case (.awaitingConfirmation, .confirmAction):
            newState = .processing

        // Cancel from confirmation
        case (.awaitingConfirmation, .cancelAction):
            reset()
            return .idle

        // Cancel from any active send state
        case (_, .cancelAction) where isInSendFlow(activeFlow):
            reset()
            return .idle

        // General cancel from non-flow states
        case (_, .cancelAction):
            reset()
            return .idle

        // ──────────────────────────────────────────────
        // MARK: New send during active flow restarts
        // ──────────────────────────────────────────────

        case (_, .send(let amount, let unit, let address, let feeLevel))
            where activeFlow != .idle && activeFlow != .processing:
            pendingTransaction = nil // Clear old pending data before restarting
            newState = handleNewSend(amount: amount, unit: unit, address: address, feeLevel: feeLevel)

        // ──────────────────────────────────────────────
        // MARK: Pass-through (stay in current state)
        // ──────────────────────────────────────────────
        default:
            newState = activeFlow
        }

        activeFlow = newState
        return newState
    }

    // MARK: - Modification Handling

    private func handleModification(_ meaning: SentenceMeaning) -> FlowAction {
        guard let modifier = meaning.modifier else { return .advanceFlow(activeFlow) }

        // At awaitingConfirmation, "faster"/"slower" always means fee — the amount is already set.
        let isAtConfirmation: Bool = {
            if case .awaitingConfirmation = activeFlow { return true }
            return false
        }()

        switch modifier {
        case .increase:
            let field = (isAtConfirmation || meaning.object == .fee) ? "fee" : "amount"
            return .modifyFlow(field: field, newValue: "increase")
        case .decrease:
            let field = (isAtConfirmation || meaning.object == .fee) ? "fee" : "amount"
            return .modifyFlow(field: field, newValue: "decrease")
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
            if addr.isEmpty {
                return "\n\n{{dim:You were starting a send. Just tell me the amount when you're ready.}}"
            }
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
        case .balance, .price, .history, .help, .about,
             .walletHealth, .networkStatus, .utxoList, .receive,
             .newAddress, .hideBalance, .showBalance, .refreshWallet,
             .exportHistory, .greeting, .explain:
            return true
        case .convertAmount:
            return true
        case .feeEstimate:
            // Fee estimate is NOT unrelated during awaitingFeeLevel -- handled separately above
            if case .awaitingFeeLevel = activeFlow { return false }
            return true
        default:
            return false
        }
    }

    private func isResumingData(_ intent: WalletIntent, for paused: ConversationState) -> Bool {
        switch (paused, intent) {
        // Resume awaitingAddress with an address
        case (.awaitingAddress, .send(_, _, let addr, _)) where addr != nil:
            return true
        case (.awaitingAddress, .unknown(let rawText)):
            let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            let validator = AddressValidator()
            return validator.isValid(trimmed)

        // Resume awaitingAmount with an amount
        case (.awaitingAmount, .send(let amt, _, _, _)) where amt != nil:
            return true
        case (.awaitingAmount, .unknown(let rawText)):
            let extractor = EntityExtractor()
            let entities = extractor.extract(from: rawText)
            if entities.amount != nil { return true }
            if Decimal(string: rawText.trimmingCharacters(in: .whitespacesAndNewlines)) != nil { return true }
            return false

        // Resume awaitingFeeLevel with a fee level
        case (.awaitingFeeLevel, .send(_, _, _, let feeLevel)) where feeLevel != nil:
            return true
        case (.awaitingFeeLevel, .unknown(let rawText)):
            let lowered = rawText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let feeKeywords = ["fast", "priority", "urgent", "high", "rush", "asap", "quick",
                               "slow", "low", "economy", "cheap", "saver", "eco",
                               "medium", "normal", "standard", "regular", "default"]
            return feeKeywords.contains(where: { lowered.contains($0) })

        // Resume awaitingConfirmation with confirm/cancel
        case (.awaitingConfirmation, .confirmAction):
            return true
        case (.awaitingConfirmation, .cancelAction):
            return true

        default:
            return false
        }
    }

    // MARK: - Address Validation Helper

    private enum AddressValidationResult {
        case valid(String)
        case testnet
        case invalid
    }

    private func validateAddress(_ address: String) -> AddressValidationResult {
        let validator = AddressValidator()
        if validator.isTestnet(address) {
            return .testnet
        }
        if validator.isValid(address) {
            return .valid(address)
        }
        return .invalid
    }

    // MARK: - Send Flow Helpers

    /// Handles initiating a new send flow. Determines which state to enter based on
    /// which pieces of information are already provided.
    ///
    /// Transitions:
    /// - No info           -> awaitingAmount (ask amount first, natural flow)
    /// - Amount only       -> awaitingAddress
    /// - Address only      -> awaitingAmount (with address stored)
    /// - Amount + Address  -> awaitingFeeLevel (user picks fee)
    /// - All three         -> awaitingConfirmation
    private func handleNewSend(amount: Decimal?, unit: BitcoinUnit?, address: String?, feeLevel: FeeLevel?) -> ConversationState {
        let btcAmount: Decimal? = amount.map { truncateToMaxDecimals(normalizeAmount($0, unit: unit)) }

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

        switch (btcAmount, validatedAddress, feeLevel) {
        // All three provided -> go straight to confirmation
        case (.some(let amt), .some(let addr), .some(let level)):
            guard amt > 0 else { return .error(L10n.Error.invalidAmount) }
            let fee = estimateFee(feeLevel: level)
            buildPendingTransaction(amount: amt, address: addr, fee: fee, feeLevel: level)
            return .awaitingConfirmation(amount: amt, address: addr, fee: fee)

        // Amount + Address provided -> ask for fee level
        case (.some(let amt), .some(let addr), .none):
            guard amt > 0 else { return .error(L10n.Error.invalidAmount) }
            return .awaitingFeeLevel(amount: amt, address: addr)

        // Amount only -> ask for address
        case (.some(let amt), .none, _):
            guard amt > 0 else { return .error(L10n.Error.invalidAmount) }
            return .awaitingAddress(amount: amt)

        // Address only -> ask for amount (store the address)
        case (.none, .some(let addr), _):
            return .awaitingAmount(address: addr)

        // Nothing provided -> ask for amount first (natural flow)
        case (.none, .none, _):
            return .awaitingAmount(address: "")
        }
    }

    func normalizeAmount(_ amount: Decimal, unit: BitcoinUnit?) -> Decimal {
        guard let unit = unit else { return amount }
        switch unit {
        case .btc: return amount
        case .sats, .satoshis: return amount / Self.satoshisPerBTC
        }
    }

    /// Truncates a BTC amount to at most 8 decimal places (1 satoshi precision).
    private func truncateToMaxDecimals(_ amount: Decimal) -> Decimal {
        let handler = NSDecimalNumberHandler(
            roundingMode: .down, scale: Self.maxDecimalPlaces,
            raiseOnExactness: false, raiseOnOverflow: false,
            raiseOnUnderflow: false, raiseOnDivideByZero: false
        )
        return NSDecimalNumber(decimal: amount).rounding(accordingToBehavior: handler).decimalValue
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

    /// Reverse-maps a fee rate back to a FeeLevel for re-entry scenarios.
    private func feeLevelFromRate(_ rate: Decimal?) -> FeeLevel {
        guard let rate = rate, let live = liveFeeEstimates else { return .medium }
        if rate == live.fast { return .fast }
        if rate == live.slow { return .slow }
        return .medium
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
            responses.append(.text("Check your connection and try again. Nothing was sent \u{2014} your funds are safe."))
        } else if error.lowercased().contains("invalid address") {
            responses.append(.text("That address doesn't look right. Double-check it and try again."))
        } else {
            responses.append(.text("Want to try again, or do something else?"))
        }
        return responses
    }
}
