// MARK: - MeaningResolver.swift
// Bitcoin AI Wallet
//
// Maps SentenceMeaning → ClassificationResult → WalletIntent.
// Bridges the language analysis layer to the existing intent system.
//
// Special cases handled:
// - Bare questions ("What?" "Why?") → context-dependent
// - Evaluations ("Too much" "Good enough") → modifier-aware
// - Affordability ("Can I afford it?") → balance check
// - Safety questions ("Is that safe?") → contextual help
// - Negated commands ("Don't send") → cancel
// - Comparatives ("Faster" "Cheaper") → fee modification
//
// Platform: iOS 17.0+
// Framework: Foundation

import Foundation

// MARK: - MeaningResolver

final class MeaningResolver {

    // MARK: - Resolution

    /// Maps a SentenceMeaning to a ClassificationResult with the appropriate WalletIntent.
    @MainActor
    func resolve(_ meaning: SentenceMeaning, memory: ConversationMemory) -> ClassificationResult {
        // Empty input
        if meaning.type == .empty {
            return ClassificationResult(
                intent: .unknown(rawText: ""),
                confidence: 0,
                needsClarification: true,
                alternatives: []
            )
        }

        // Emotion-only (greetings, thanks, etc.)
        if meaning.type == .emotional {
            return resolveEmotion(meaning)
        }

        // Bare questions use conversation context
        if meaning.type == .bare {
            return resolveBareQuestion(meaning, memory: memory)
        }

        // Navigation / comparatives
        if meaning.type == .navigation {
            return resolveNavigation(meaning, memory: memory)
        }

        // Evaluations
        if meaning.type == .evaluation {
            return resolveEvaluation(meaning, memory: memory)
        }

        // Negated action → cancel
        if meaning.isNegated, let action = meaning.action, isDestructiveAction(action) {
            return ClassificationResult(
                intent: .cancelAction,
                confidence: meaning.confidence,
                needsClarification: false,
                alternatives: []
            )
        }

        // Direct action mapping
        if let action = meaning.action {
            let intent = mapActionToIntent(action, meaning: meaning)
            return ClassificationResult(
                intent: intent,
                confidence: meaning.confidence,
                needsClarification: meaning.confidence < 0.5,
                alternatives: []
            )
        }

        // Fallback
        return ClassificationResult(
            intent: .unknown(rawText: ""),
            confidence: meaning.confidence,
            needsClarification: true,
            alternatives: []
        )
    }

    // MARK: - Emotion Resolution

    private func resolveEmotion(_ meaning: SentenceMeaning) -> ClassificationResult {
        guard let emotion = meaning.emotion else {
            return ClassificationResult(intent: .greeting, confidence: 0.7,
                                        needsClarification: false, alternatives: [])
        }

        switch emotion {
        case .gratitude:
            return ClassificationResult(intent: .greeting, confidence: 0.85,
                                        needsClarification: false, alternatives: [])
        case .excitement:
            return ClassificationResult(intent: .greeting, confidence: 0.8,
                                        needsClarification: false, alternatives: [])
        case .frustration:
            return ClassificationResult(intent: .help, confidence: 0.7,
                                        needsClarification: false, alternatives: [])
        case .confusion:
            return ClassificationResult(intent: .help, confidence: 0.75,
                                        needsClarification: false, alternatives: [])
        case .humor:
            return ClassificationResult(intent: .greeting, confidence: 0.6,
                                        needsClarification: false, alternatives: [])
        case .concern:
            return ClassificationResult(intent: .help, confidence: 0.7,
                                        needsClarification: false, alternatives: [])
        }
    }

    // MARK: - Bare Question Resolution

    @MainActor
    private func resolveBareQuestion(_ meaning: SentenceMeaning,
                                      memory: ConversationMemory) -> ClassificationResult {
        // Use last user intent to provide context
        if let lastIntent = memory.lastUserIntent {
            switch lastIntent {
            case .balance:
                return ClassificationResult(intent: .balance, confidence: 0.7,
                                            needsClarification: false, alternatives: [])
            case .send:
                return ClassificationResult(intent: .help, confidence: 0.65,
                                            needsClarification: true, alternatives: [])
            case .feeEstimate:
                return ClassificationResult(intent: .feeEstimate, confidence: 0.7,
                                            needsClarification: false, alternatives: [])
            case .history:
                return ClassificationResult(intent: .history(count: nil), confidence: 0.7,
                                            needsClarification: false, alternatives: [])
            case .price:
                return ClassificationResult(intent: .price(currency: nil), confidence: 0.7,
                                            needsClarification: false, alternatives: [])
            default:
                break
            }
        }

        // No context — ask for clarification
        return ClassificationResult(
            intent: .help,
            confidence: 0.4,
            needsClarification: true,
            alternatives: []
        )
    }

    // MARK: - Navigation Resolution

    @MainActor
    private func resolveNavigation(_ meaning: SentenceMeaning,
                                    memory: ConversationMemory) -> ClassificationResult {
        guard let modifier = meaning.modifier else {
            // Repeat last action
            if let lastIntent = memory.lastUserIntent {
                return ClassificationResult(intent: lastIntent, confidence: 0.6,
                                            needsClarification: false, alternatives: [])
            }
            return ClassificationResult(intent: .help, confidence: 0.4,
                                        needsClarification: true, alternatives: [])
        }

        switch modifier {
        case .fastest:
            // "Faster" in fee context → show fee estimate
            return ClassificationResult(intent: .feeEstimate, confidence: 0.75,
                                        needsClarification: false, alternatives: [])
        case .cheapest:
            return ClassificationResult(intent: .feeEstimate, confidence: 0.75,
                                        needsClarification: false, alternatives: [])
        case .increase:
            // "More" → more history or more details
            if memory.lastUserIntent == .history(count: nil) ||
               memory.lastShownTransactions != nil {
                return ClassificationResult(intent: .history(count: 20), confidence: 0.7,
                                            needsClarification: false, alternatives: [])
            }
            return ClassificationResult(intent: .help, confidence: 0.5,
                                        needsClarification: true, alternatives: [])
        case .decrease:
            return ClassificationResult(intent: .feeEstimate, confidence: 0.6,
                                        needsClarification: true, alternatives: [])
        default:
            if let lastIntent = memory.lastUserIntent {
                return ClassificationResult(intent: lastIntent, confidence: 0.55,
                                            needsClarification: true, alternatives: [])
            }
            return ClassificationResult(intent: .help, confidence: 0.4,
                                        needsClarification: true, alternatives: [])
        }
    }

    // MARK: - Evaluation Resolution

    @MainActor
    private func resolveEvaluation(_ meaning: SentenceMeaning,
                                    memory: ConversationMemory) -> ClassificationResult {
        guard let modifier = meaning.modifier else {
            return ClassificationResult(intent: .help, confidence: 0.4,
                                        needsClarification: true, alternatives: [])
        }

        switch modifier {
        case .tooMuch:
            // "Too much" — context-dependent
            if let lastIntent = memory.lastUserIntent {
                switch lastIntent {
                case .feeEstimate:
                    // Fee too high → show lower fee options
                    return ClassificationResult(intent: .feeEstimate, confidence: 0.8,
                                                needsClarification: false, alternatives: [])
                case .send:
                    // Amount too high → user may want to adjust
                    return ClassificationResult(intent: .balance, confidence: 0.7,
                                                needsClarification: true, alternatives: [])
                case .balance:
                    return ClassificationResult(intent: .help, confidence: 0.5,
                                                needsClarification: true, alternatives: [])
                default:
                    break
                }
            }
            return ClassificationResult(intent: .help, confidence: 0.5,
                                        needsClarification: true, alternatives: [])

        case .tooLittle:
            return ClassificationResult(intent: .balance, confidence: 0.6,
                                        needsClarification: true, alternatives: [])

        case .enough:
            // "Good enough" / "Enough" — proceed with current action
            return ClassificationResult(intent: .confirmAction, confidence: 0.7,
                                        needsClarification: false, alternatives: [])

        case .safest:
            return ClassificationResult(intent: .help, confidence: 0.7,
                                        needsClarification: false, alternatives: [])

        default:
            return ClassificationResult(intent: .help, confidence: 0.5,
                                        needsClarification: true, alternatives: [])
        }
    }

    // MARK: - Action → Intent Mapping

    private func mapActionToIntent(_ action: ResolvedAction, meaning: SentenceMeaning) -> WalletIntent {
        switch action {
        case .send:
            // Extract amount and address from the object if available
            var amount: Decimal?
            var address: String?
            if case .amount(let a) = meaning.object { amount = a }
            if case .address(let a) = meaning.object { address = a }
            return .send(amount: amount, unit: nil, address: address, feeLevel: nil)

        case .receive:
            return .receive

        case .checkBalance:
            return .balance

        case .showFees:
            return .feeEstimate

        case .showPrice:
            return .price(currency: nil)

        case .showHistory:
            return .history(count: nil)

        case .showDetail:
            if case .transaction(let txid) = meaning.object {
                return .transactionDetail(txid: txid)
            }
            return .history(count: nil)

        case .newAddress:
            return .newAddress

        case .exportHistory:
            return .exportHistory

        case .utxoList:
            return .utxoList

        case .bumpFee:
            return .bumpFee(txid: nil)

        case .networkStatus:
            return .networkStatus

        case .walletHealth:
            return .walletHealth

        case .settings:
            return .settings

        case .helpUser:
            return .help

        case .about:
            return .about

        case .confirm:
            return .confirmAction

        case .cancel:
            return .cancelAction

        case .hide:
            return .hideBalance

        case .show:
            return .showBalance

        case .refresh:
            return .refreshWallet

        case .convert:
            if case .amount(let a) = meaning.object {
                return .convertAmount(amount: a, fromCurrency: "USD")
            }
            return .price(currency: nil)
        }
    }

    // MARK: - Helpers

    private func isDestructiveAction(_ action: ResolvedAction) -> Bool {
        switch action {
        case .send, .confirm, .bumpFee:
            return true
        default:
            return false
        }
    }
}
