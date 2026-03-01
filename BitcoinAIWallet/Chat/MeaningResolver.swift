// MARK: - MeaningResolver.swift
// Bitcoin AI Wallet
//
// Maps SentenceMeaning → ClassificationResult → WalletIntent.
// Bridges language analysis to the existing intent system.
//
// Platform: iOS 17.0+

import Foundation

// MARK: - MeaningResolver

final class MeaningResolver {

    @MainActor
    func resolve(_ meaning: SentenceMeaning, memory: ConversationMemory, entityExtractor: EntityExtractor, input: String) -> ClassificationResult {

        // Emotion-only → greeting/social
        if meaning.type == .emotional {
            return ClassificationResult(intent: .greeting, confidence: 0.8, needsClarification: false, alternatives: [], meaning: meaning)
        }

        // Evaluation → pass through with meaning
        if meaning.type == .evaluation {
            return resolveEvaluation(meaning, memory: memory)
        }

        // Navigation
        if meaning.type == .navigation {
            return resolveNavigation(meaning, memory: memory)
        }

        guard let action = meaning.action else {
            return ClassificationResult(intent: .unknown(rawText: input), confidence: meaning.confidence, needsClarification: true, alternatives: [], meaning: meaning)
        }

        switch action {
        case .send:
            if meaning.isNegated { return ClassificationResult(intent: .cancelAction, confidence: 0.8, needsClarification: false, alternatives: [], meaning: meaning) }
            if meaning.type == .question {
                return ClassificationResult(intent: .help, confidence: 0.7, needsClarification: false, alternatives: [IntentScore(intent: .send(amount: nil, unit: nil, address: nil, feeLevel: nil), confidence: 0.4, source: "question")], meaning: meaning)
            }
            let e = entityExtractor.extract(from: input)
            // Safety net: if EntityExtractor missed a bare number, use the modifier from SentenceAnalyzer
            var amount = e.amount
            if amount == nil, let mod = meaning.modifier, case .specific(let n) = mod {
                amount = n
            }
            return ClassificationResult(intent: .send(amount: amount, unit: e.unit, address: e.address, feeLevel: e.feeLevel), confidence: meaning.confidence, needsClarification: false, alternatives: [], meaning: meaning)

        case .receive:
            return ClassificationResult(intent: .receive, confidence: meaning.confidence, needsClarification: false, alternatives: [], meaning: meaning)
        case .checkBalance:
            return ClassificationResult(intent: .balance, confidence: meaning.confidence, needsClarification: false, alternatives: [], meaning: meaning)
        case .showFees:
            return ClassificationResult(intent: .feeEstimate, confidence: meaning.confidence, needsClarification: false, alternatives: [], meaning: meaning)
        case .showPrice:
            return ClassificationResult(intent: .price(currency: nil), confidence: meaning.confidence, needsClarification: false, alternatives: [], meaning: meaning)
        case .showHistory:
            return ClassificationResult(intent: .history(count: nil), confidence: meaning.confidence, needsClarification: false, alternatives: [], meaning: meaning)
        case .showAddress:
            return ClassificationResult(intent: .receive, confidence: meaning.confidence, needsClarification: false, alternatives: [], meaning: meaning)
        case .showUTXO:
            return ClassificationResult(intent: .utxoList, confidence: meaning.confidence, needsClarification: false, alternatives: [], meaning: meaning)
        case .showHealth:
            return ClassificationResult(intent: .walletHealth, confidence: meaning.confidence, needsClarification: false, alternatives: [], meaning: meaning)
        case .showNetwork:
            return ClassificationResult(intent: .networkStatus, confidence: meaning.confidence, needsClarification: false, alternatives: [], meaning: meaning)
        case .confirm:
            return ClassificationResult(intent: .confirmAction, confidence: meaning.confidence, needsClarification: false, alternatives: [], meaning: meaning)
        case .cancel, .undo:
            return ClassificationResult(intent: .cancelAction, confidence: meaning.confidence, needsClarification: false, alternatives: [], meaning: meaning)
        case .repeatLast:
            if let last = memory.lastUserIntent { return ClassificationResult(intent: last, confidence: 0.8, needsClarification: false, alternatives: [], meaning: meaning) }
            return ClassificationResult(intent: .help, confidence: 0.5, needsClarification: true, alternatives: [], meaning: meaning)
        case .explain:
            return ClassificationResult(intent: .help, confidence: 0.7, needsClarification: false, alternatives: [], meaning: meaning)
        case .help:
            return ClassificationResult(intent: .help, confidence: 0.9, needsClarification: false, alternatives: [], meaning: meaning)
        case .export:
            return ClassificationResult(intent: .exportHistory, confidence: 0.85, needsClarification: false, alternatives: [], meaning: meaning)
        case .bump:
            return ClassificationResult(intent: .bumpFee(txid: nil), confidence: 0.8, needsClarification: false, alternatives: [], meaning: meaning)
        case .refresh:
            return ClassificationResult(intent: .refreshWallet, confidence: 0.85, needsClarification: false, alternatives: [], meaning: meaning)
        case .hide:
            return ClassificationResult(intent: .hideBalance, confidence: 0.85, needsClarification: false, alternatives: [], meaning: meaning)
        case .show:
            return ClassificationResult(intent: .showBalance, confidence: 0.85, needsClarification: false, alternatives: [], meaning: meaning)
        case .generate:
            return ClassificationResult(intent: .newAddress, confidence: 0.85, needsClarification: false, alternatives: [], meaning: meaning)
        case .convert:
            return ClassificationResult(intent: .price(currency: nil), confidence: 0.7, needsClarification: false, alternatives: [], meaning: meaning)
        case .compare:
            return ClassificationResult(intent: .balance, confidence: 0.8, needsClarification: false, alternatives: [], meaning: meaning)
        case .select(let idx):
            if let txs = memory.lastShownTransactions, idx >= 0, idx < txs.count {
                return ClassificationResult(intent: .transactionDetail(txid: txs[idx].txid), confidence: 0.85, needsClarification: false, alternatives: [], meaning: meaning)
            }
            return ClassificationResult(intent: .help, confidence: 0.4, needsClarification: true, alternatives: [], meaning: meaning)
        case .modify:
            return ClassificationResult(intent: .send(amount: nil, unit: nil, address: nil, feeLevel: nil), confidence: 0.7, needsClarification: false, alternatives: [], meaning: meaning)
        case .settings:
            return ClassificationResult(intent: .settings, confidence: 0.9, needsClarification: false, alternatives: [], meaning: meaning)
        case .about:
            return ClassificationResult(intent: .about, confidence: 0.9, needsClarification: false, alternatives: [], meaning: meaning)
        case .backup:
            return ClassificationResult(intent: .settings, confidence: 0.7, needsClarification: false, alternatives: [], meaning: meaning)
        }
    }

    // MARK: - Evaluation Resolution

    @MainActor
    private func resolveEvaluation(_ meaning: SentenceMeaning, memory: ConversationMemory) -> ClassificationResult {
        guard let modifier = meaning.modifier else {
            return ClassificationResult(intent: .unknown(rawText: ""), confidence: 0.3, needsClarification: true, alternatives: [], meaning: meaning)
        }
        switch modifier {
        case .enough:
            return ClassificationResult(intent: .confirmAction, confidence: 0.7, needsClarification: false, alternatives: [], meaning: meaning)
        case .tooMuch:
            if memory.lastShownFeeEstimates != nil { return ClassificationResult(intent: .feeEstimate, confidence: 0.8, needsClarification: false, alternatives: [], meaning: meaning) }
            return ClassificationResult(intent: .balance, confidence: 0.6, needsClarification: true, alternatives: [], meaning: meaning)
        case .tooLittle, .notEnough:
            return ClassificationResult(intent: .balance, confidence: 0.6, needsClarification: true, alternatives: [], meaning: meaning)
        default:
            return ClassificationResult(intent: .unknown(rawText: ""), confidence: 0.3, needsClarification: true, alternatives: [], meaning: meaning)
        }
    }

    // MARK: - Navigation Resolution

    @MainActor
    private func resolveNavigation(_ meaning: SentenceMeaning, memory: ConversationMemory) -> ClassificationResult {
        guard let action = meaning.action else {
            return ClassificationResult(intent: .help, confidence: 0.4, needsClarification: true, alternatives: [], meaning: meaning)
        }
        switch action {
        case .undo:
            return ClassificationResult(intent: .cancelAction, confidence: 0.8, needsClarification: false, alternatives: [], meaning: meaning)
        case .repeatLast:
            if let last = memory.lastUserIntent { return ClassificationResult(intent: last, confidence: 0.8, needsClarification: false, alternatives: [], meaning: meaning) }
            return ClassificationResult(intent: .help, confidence: 0.5, needsClarification: true, alternatives: [], meaning: meaning)
        case .select(let idx):
            if let txs = memory.lastShownTransactions {
                let safeIdx = idx == -1 ? txs.count - 1 : min(idx, txs.count - 1)
                if safeIdx >= 0 && safeIdx < txs.count {
                    return ClassificationResult(intent: .transactionDetail(txid: txs[safeIdx].txid), confidence: 0.85, needsClarification: false, alternatives: [], meaning: meaning)
                }
            }
            return ClassificationResult(intent: .help, confidence: 0.4, needsClarification: true, alternatives: [], meaning: meaning)
        default:
            return ClassificationResult(intent: .help, confidence: 0.4, needsClarification: true, alternatives: [], meaning: meaning)
        }
    }
}
