// MARK: - SentenceAnalyzer.swift
// Bitcoin AI Wallet
//
// Analyzes classified words into SentenceMeaning structures.
// 15 grammar rules applied in priority order.
//
// Platform: iOS 17.0+

import Foundation

// MARK: - SentenceMeaning

struct SentenceMeaning {
    let type: SentenceType
    let action: ResolvedAction?
    let subject: ResolvedSubject?
    let object: ResolvedObject?
    let modifier: ResolvedModifier?
    let emotion: EmotionType?
    let isNegated: Bool
    let confidence: Double
}

enum SentenceType: Equatable {
    case command, question, statement, evaluation, navigation, emotional, singleWord, bare, empty
}

enum ResolvedAction: Equatable {
    case send, receive, checkBalance, showFees, showPrice
    case showHistory, showAddress, showUTXO, showHealth, showNetwork
    case confirm, cancel, undo, repeatLast, export, backup
    case convert, bump, refresh, hide, show, generate
    case explain, help, settings, about
    case modify(what: String)
    case compare
    case select(index: Int)
}

enum ResolvedSubject: Equatable { case user, wallet, lastEntity, network }

enum ResolvedObject: Equatable {
    case balance, fee, amount, address, transaction, price
    case wallet, network, history, utxo, lastMentioned, specific(String)
}

enum ResolvedModifier: Equatable {
    case increase, decrease, fastest, cheapest, middle
    case all, half, double, specific(Decimal)
    case tooMuch, tooLittle, enough, notEnough
}

// MARK: - SentenceAnalyzer

final class SentenceAnalyzer {
    private let wordClassifier = WordClassifier()

    @MainActor
    func analyze(_ input: String, memory: ConversationMemory) -> SentenceMeaning {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // Pure punctuation
        if trimmed == "?" { return SentenceMeaning(type: .singleWord, action: .help, subject: nil, object: nil, modifier: nil, emotion: nil, isNegated: false, confidence: 0.9) }
        if trimmed == "..." || trimmed == ".." || trimmed == "…" { return SentenceMeaning(type: .empty, action: nil, subject: nil, object: nil, modifier: nil, emotion: nil, isNegated: false, confidence: 0.5) }

        let classified = wordClassifier.classifyAll(trimmed)
        let isQuestion = trimmed.hasSuffix("?") || trimmed.hasSuffix("؟")
        let hasNegation = classified.contains { if case .negation = $0.type { return true }; return false }
        let emotion = classified.compactMap { if case .emotion(let e) = $0.type { return e }; return nil }.first

        // Extract key components
        let walletVerb = classified.compactMap { if case .walletVerb(let v) = $0.type { return v }; return nil }.first
        let generalVerb = classified.compactMap { if case .generalVerb(let v) = $0.type { return v }; return nil }.first
        let bitcoinNoun = classified.compactMap { if case .bitcoinNoun(let n) = $0.type { return n }; return nil }.first
        let comparative = classified.compactMap { if case .comparative(let d) = $0.type { return d }; return nil }.first
        let evaluative = classified.compactMap { if case .evaluative(let e) = $0.type { return e }; return nil }.first
        let directional = classified.compactMap { if case .directional(let d) = $0.type { return d }; return nil }.first
        let quantifier = classified.compactMap { if case .quantifier(let q) = $0.type { return q }; return nil }.first
        let questionWord = classified.compactMap { if case .questionWord(let q) = $0.type { return q }; return nil }.first
        let modal = classified.compactMap { if case .modal = $0.type { return true }; return nil }.first
        let hasNumber = classified.contains { if case .number = $0.type { return true }; return false }
        let hasAddress = classified.contains { if case .bitcoinAddress = $0.type { return true }; return false }
        let hasBitcoinUnit = classified.contains { if case .bitcoinUnit = $0.type { return true }; return false }

        // ── RULE 0: Special phrase tokens (fee level, change amount) ──
        for item in classified {
            if case .unknown(let tok) = item.type {
                if tok.hasPrefix("fee_level:") {
                    return SentenceMeaning(type: .command, action: .modify(what: "fee"), subject: nil, object: .fee, modifier: tok.contains("fast") ? .fastest : (tok.contains("slow") ? .cheapest : .middle), emotion: nil, isNegated: false, confidence: 0.9)
                }
                if tok == "change_amount" {
                    return SentenceMeaning(type: .command, action: .modify(what: "amount"), subject: nil, object: .amount, modifier: nil, emotion: nil, isNegated: false, confidence: 0.85)
                }
            }
        }

        // ── RULE 1: Single word ──
        if classified.count == 1 { return analyzeSingleWord(classified[0], isQuestion: isQuestion, memory: memory) }

        // ── RULE 1b: Greeting (multi-word: "hi there", "hello how are you") ──
        let hasGreeting = classified.contains { if case .greeting = $0.type { return true }; return false }
        if hasGreeting && classified.allSatisfy({ isGreetingOrNoise($0.type) }) {
            return SentenceMeaning(type: .emotional, action: nil, subject: nil, object: nil, modifier: nil, emotion: nil, isNegated: false, confidence: 0.9)
        }

        // ── RULE 2: Pure emotion ──
        if emotion != nil && classified.allSatisfy({ isEmotionOrNoise($0.type) }) {
            return SentenceMeaning(type: .emotional, action: nil, subject: nil, object: nil, modifier: nil, emotion: emotion, isNegated: false, confidence: 0.9)
        }

        // ── RULE 3: Pure affirmation/negation ──
        if classified.allSatisfy({ isAffOrNeg($0.type) || isNoise($0.type) || isFluff($0.type) }) {
            if hasNegation { return SentenceMeaning(type: .command, action: .cancel, subject: nil, object: nil, modifier: nil, emotion: nil, isNegated: true, confidence: 0.85) }
            return SentenceMeaning(type: .command, action: .confirm, subject: nil, object: nil, modifier: nil, emotion: nil, isNegated: false, confidence: 0.85)
        }

        // ── RULE 3b: Possessive + bitcoinUnit only ("my btc", "my bitcoin") → balance ──
        if hasBitcoinUnit && classified.allSatisfy({ isBitcoinUnitOrNoise($0.type) }) {
            let hasArticle = classified.contains { if case .article = $0.type { return true }; return false }
            if hasArticle {
                return SentenceMeaning(type: .question, action: .checkBalance, subject: .user, object: .balance, modifier: nil, emotion: nil, isNegated: false, confidence: 0.85)
            }
        }

        // ── RULE 4: Bare question word ──
        // Detect ownership context: "do I have", "I have", "do I own"
        let hasOwnershipContext = classified.contains { if case .unknown(let w) = $0.type { return ["have", "own", "hold", "got"].contains(w) }; return false }
        // Treat howMuch/howMany as implicit questions even without "?"
        let isImplicitQuestion = isQuestion || questionWord == .howMuch || questionWord == .howMany
        if isImplicitQuestion && walletVerb == nil && generalVerb == nil && questionWord != nil && !hasNumber && !hasAddress {
            return analyzeBareQuestion(questionWord!, bitcoinNoun: bitcoinNoun, hasBitcoinUnit: hasBitcoinUnit, hasOwnershipContext: hasOwnershipContext, memory: memory)
        }

        // ── RULE 4b: "how much is 0.5 BTC", "how many sats is 0.001 BTC" → price conversion ──
        if (questionWord == .howMuch || questionWord == .howMany) && hasNumber && hasBitcoinUnit && walletVerb == nil && !hasAddress {
            return SentenceMeaning(type: .question, action: .showPrice, subject: nil, object: .price, modifier: nil, emotion: nil, isNegated: hasNegation, confidence: 0.85)
        }

        // ── RULE 5: Comparative (with or without non-actionable general verb) ──
        // "faster", "cheaper", "make it faster", "wait make it cheaper" → all comparative-driven
        // BUT: skip when sentence mentions a bitcoin unit with up/down (price direction query)
        // e.g., "Is bitcoin up or down?" or "Bitcoin going up?"
        let comparativeFriendlyVerbs: Set<GeneralAction> = [.make, .go, .get, .want, .need, .wait, .stop, .set]
        let isPriceDirection = (comparative == .up || comparative == .down) && hasBitcoinUnit && !hasNumber
        let isBitcoinUnitQuestion = isPriceDirection
        if walletVerb == nil && comparative != nil && !isBitcoinUnitQuestion &&
           (generalVerb == nil || comparativeFriendlyVerbs.contains(generalVerb!)) {
            return analyzeComparative(comparative!, memory: memory)
        }

        // ── RULE 6: Safety question ("is this safe?") ──
        // Must fire BEFORE general evaluative rule so .safe with ? gets explanation, not confirmation
        if isQuestion && (evaluative == .safe || evaluative == .risky) {
            return SentenceMeaning(type: .question, action: .explain, subject: nil, object: .wallet, modifier: nil, emotion: nil, isNegated: false, confidence: 0.8)
        }

        // ── RULE 6b: Evaluative ──
        if evaluative != nil && walletVerb == nil {
            return analyzeEvaluation(evaluative!, isNegated: hasNegation, memory: memory)
        }

        // ── RULE 7: Directional ──
        // Allow directional even with generalVerb if the verb is tell/see/look/explain
        // (e.g., "tell me about the first one", "show me the last one")
        // BUT: skip when there's a number + bitcoinNoun (count query: "last 3 transactions")
        let directionalFriendlyVerbs: Set<GeneralAction> = [.tell, .see, .look, .explain, .teach]
        let isCountQuery = hasNumber && bitcoinNoun != nil
        if directional != nil && walletVerb == nil && !isCountQuery && (generalVerb == nil || directionalFriendlyVerbs.contains(generalVerb!)) {
            return analyzeDirectional(directional!, memory: memory)
        }

        // ── RULE 7b: "try again" → repeatLast ──
        if generalVerb == .tryIt && directional == .again {
            return SentenceMeaning(type: .navigation, action: .repeatLast, subject: nil, object: nil, modifier: nil, emotion: nil, isNegated: false, confidence: 0.85)
        }

        // ── RULE 8: "Can I afford it?" ──
        if modal != nil && generalVerb == .afford {
            return SentenceMeaning(type: .question, action: .compare, subject: .user, object: .lastMentioned, modifier: nil, emotion: nil, isNegated: hasNegation, confidence: 0.85)
        }

        // ── RULE 9: (safety question now handled in Rule 6 above) ──

        // ── RULE 9b: Past-tense query with wallet verb ──
        // "What did I send recently" / "Did I receive anything today" → history, not send/receive
        let hasTemporal = classified.compactMap { if case .temporal(let t) = $0.type { return t }; return nil }.first
        let hasPastIndicator = classified.contains { if case .unknown(let w) = $0.type { return w == "did" || w == "was" || w == "were" }; return false }
        if let verb = walletVerb, (verb == .send || verb == .receive),
           (hasPastIndicator || hasTemporal == .recently || hasTemporal == .yesterday || hasTemporal == .today),
           !hasNumber && !hasAddress {
            return SentenceMeaning(type: .question, action: .showHistory, subject: .user, object: .history, modifier: nil, emotion: emotion, isNegated: hasNegation, confidence: 0.85)
        }

        // ── RULE 10: Wallet verb present ──
        if let verb = walletVerb {
            // "when will it confirm?" → question about confirmation timing, not .confirmAction
            if verb == .confirm && (questionWord != nil || isQuestion) {
                return SentenceMeaning(type: .question, action: .explain, subject: nil, object: .transaction, modifier: nil, emotion: nil, isNegated: false, confidence: 0.8)
            }

            // "show more" / "display more" → show more results (history)
            if (verb == .show || verb == .check) && comparative == .more && bitcoinNoun == nil {
                return SentenceMeaning(type: .command, action: .showHistory, subject: nil, object: .history, modifier: .increase, emotion: nil, isNegated: false, confidence: 0.85)
            }

            // "hide balance" / "show balance" / "reveal balance" → privacy toggle, not balance check
            if (verb == .hide || verb == .show) && bitcoinNoun == .balance {
                let privacyAction: ResolvedAction = verb == .hide ? .hide : .show
                return SentenceMeaning(type: .command, action: privacyAction, subject: .user, object: .balance, modifier: nil, emotion: emotion, isNegated: hasNegation, confidence: 0.9)
            }

            // "show"/"check" defer to the noun: "show fees" → .showFees, "check price" → .showPrice
            // Special case: "check wallet" / "show wallet" → balance (not wallet health)
            let action: ResolvedAction
            if (verb == .show || verb == .check) && bitcoinNoun == .wallet {
                action = .checkBalance
            } else if (verb == .show || verb == .check) && bitcoinNoun != nil {
                action = defaultAction(for: bitcoinNoun!)
            } else {
                action = mapWalletVerb(verb)
            }
            let object = bitcoinNoun.map { mapBitcoinNoun($0) } ?? .lastMentioned
            let modifier = resolveModifier(comparative, quantifier)

            // "send?" with no number/address = question about sending
            if isQuestion && !hasNumber && !hasAddress && classified.count <= 3 {
                return SentenceMeaning(type: .question, action: action, subject: .user, object: object, modifier: modifier, emotion: emotion, isNegated: hasNegation, confidence: 0.75)
            }

            // "send it" / "send this" with no number/address = confirmation, not new send
            if verb == .send && !hasNumber && !hasAddress && bitcoinNoun == nil &&
               classified.allSatisfy({ isSendConfirmWord($0.type) }) {
                return SentenceMeaning(type: .command, action: .confirm, subject: nil, object: nil, modifier: nil, emotion: nil, isNegated: false, confidence: 0.85)
            }

            // Negated wallet verb: "I don't want to send" → cancel
            if hasNegation {
                return SentenceMeaning(type: .command, action: .cancel, subject: .user, object: object, modifier: nil, emotion: emotion, isNegated: true, confidence: 0.8)
            }

            return SentenceMeaning(type: .command, action: action, subject: .user, object: object, modifier: modifier, emotion: emotion, isNegated: false, confidence: 0.9)
        }

        // ── RULE 11: General verb + Bitcoin noun ──
        if let gVerb = generalVerb, let noun = bitcoinNoun {
            // "Change the amount to 0.002" → modify amount, not checkBalance
            if gVerb == .change && hasNumber {
                let modifier = resolveModifier(comparative, quantifier)
                return SentenceMeaning(type: .command, action: .modify(what: "amount"), subject: .user, object: .amount, modifier: modifier, emotion: emotion, isNegated: hasNegation, confidence: 0.85)
            }
            let action = mapGeneralVerbWithNoun(gVerb, noun)
            return SentenceMeaning(type: isQuestion ? .question : .command, action: action, subject: .user, object: mapBitcoinNoun(noun), modifier: nil, emotion: emotion, isNegated: hasNegation, confidence: 0.85)
        }

        // ── RULE 11a2: "change" + number without bitcoinNoun → modify amount ──
        // "change to 0.05", "change it to 100"
        if generalVerb == .change && hasNumber && bitcoinNoun == nil {
            let numericValue = classified.compactMap { if case .number(let n) = $0.type { return n }; return nil }.first
            let mod: ResolvedModifier? = numericValue.map { .specific($0) }
            return SentenceMeaning(type: .command, action: .modify(what: "amount"), subject: .user, object: .amount, modifier: mod, emotion: emotion, isNegated: hasNegation, confidence: 0.85)
        }

        // ── RULE 11b: "fresh/new/another address" → generate new address ──
        let hasNewIndicator = classified.contains { if case .unknown(let w) = $0.type { return ["fresh", "new", "another", "different"].contains(w) }; return false }
        if hasNewIndicator && bitcoinNoun == .address && walletVerb == nil {
            return SentenceMeaning(type: .command, action: .generate, subject: .user, object: .address, modifier: nil, emotion: emotion, isNegated: hasNegation, confidence: 0.85)
        }

        // ── RULE 11c: bitcoinUnit + currency word → price query ──
        // "btc to usd", "bitcoin to eur", "btc usd"
        let hasCurrencyWord = classified.contains { if case .unknown(let w) = $0.type { return w.hasPrefix("currency:") }; return false }
        if hasBitcoinUnit && hasCurrencyWord && walletVerb == nil && !hasNumber {
            return SentenceMeaning(type: .question, action: .showPrice, subject: nil, object: .price, modifier: nil, emotion: emotion, isNegated: hasNegation, confidence: 0.85)
        }

        // ── RULE 11d: bitcoinUnit + price direction (up/down) → price query ──
        // "is bitcoin up", "is bitcoin going up", "bitcoin going up?"
        if isPriceDirection && walletVerb == nil {
            return SentenceMeaning(type: .question, action: .showPrice, subject: nil, object: .price, modifier: nil, emotion: emotion, isNegated: hasNegation, confidence: 0.85)
        }

        // ── RULE 12: Bitcoin noun alone ──
        if let noun = bitcoinNoun, walletVerb == nil {
            // When multiple bitcoin nouns exist, pick the most specific one
            // e.g., "network fees" → .fees (not .network)
            let allNouns = classified.compactMap { if case .bitcoinNoun(let n) = $0.type { return n }; return nil }
            let bestNoun = pickMostSpecificNoun(allNouns) ?? noun
            // "what's in my wallet" / question about wallet → balance check (not wallet health)
            if bestNoun == .wallet && (questionWord != nil || isQuestion) {
                return SentenceMeaning(type: .question, action: .checkBalance, subject: .user, object: .balance, modifier: nil, emotion: emotion, isNegated: hasNegation, confidence: 0.8)
            }
            let action = defaultAction(for: bestNoun)
            return SentenceMeaning(type: isQuestion ? .question : .singleWord, action: action, subject: .user, object: mapBitcoinNoun(bestNoun), modifier: nil, emotion: emotion, isNegated: hasNegation, confidence: 0.8)
        }

        // ── RULE 13: General verb alone ──
        if let gVerb = generalVerb {
            return analyzeGeneralVerb(gVerb, memory: memory, isQuestion: isQuestion, emotion: emotion)
        }

        // ── RULE 14: Bare Bitcoin address (context-aware) ──
        if hasAddress && classified.count <= 3 {
            let confidence: Double = {
                if case .awaitingAddress = memory.currentFlowState { return 0.95 }
                return 0.6
            }()
            return SentenceMeaning(type: .bare, action: .send, subject: nil, object: .address, modifier: nil, emotion: nil, isNegated: false, confidence: confidence)
        }

        // ── RULE 14b: Bare fiat amount ("$50", "€100") → convert ──
        let hasFiatAmount = classified.contains { if case .unknown(let w) = $0.type { return w.hasPrefix("fiat_amount:") }; return false }
        if hasFiatAmount && walletVerb == nil && generalVerb == nil {
            if case .awaitingAmount = memory.currentFlowState {
                return SentenceMeaning(type: .bare, action: .send, subject: nil, object: .amount, modifier: nil, emotion: nil, isNegated: false, confidence: 0.95)
            }
            return SentenceMeaning(type: .command, action: .convert, subject: nil, object: .price, modifier: nil, emotion: nil, isNegated: false, confidence: 0.8)
        }

        // ── RULE 14c: Bare number + optional unit, no verb (context-aware) ──
        if hasNumber && walletVerb == nil && generalVerb == nil {
            let hasBitcoinUnit = classified.contains { if case .bitcoinUnit = $0.type { return true }; return false }
            let hasCurrencyWord = classified.contains { if case .unknown(let w) = $0.type { return w.hasPrefix("currency:") }; return false }
            let onlyNumberAndUnit = classified.allSatisfy { w in
                if case .number = w.type { return true }
                if case .bitcoinUnit = w.type { return true }
                if case .unknown(let s) = w.type { return s.hasPrefix("currency:") || s.hasPrefix("fiat_amount:") }
                return isNoise(w.type)
            }
            if onlyNumberAndUnit {
                // Carry the numeric value as a modifier so MeaningResolver can extract it
                let numericValue = classified.compactMap { if case .number(let n) = $0.type { return n }; return nil }.first
                let mod: ResolvedModifier? = numericValue.map { .specific($0) }
                if case .awaitingAmount = memory.currentFlowState {
                    return SentenceMeaning(type: .bare, action: .send, subject: nil, object: .amount, modifier: mod, emotion: nil, isNegated: false, confidence: 0.95)
                }
                // Fiat currency word → conversion query ("100 EUR", "500 GBP in BTC")
                if hasCurrencyWord {
                    return SentenceMeaning(type: .command, action: .convert, subject: nil, object: .price, modifier: mod, emotion: nil, isNegated: false, confidence: 0.8)
                }
                if hasBitcoinUnit {
                    return SentenceMeaning(type: .bare, action: .send, subject: nil, object: .amount, modifier: mod, emotion: nil, isNegated: false, confidence: 0.7)
                }
            }
        }

        // ── RULE 15: Quantifier alone ──
        if let q = quantifier, walletVerb == nil {
            return SentenceMeaning(type: .command, action: .modify(what: "amount"), subject: nil, object: .amount, modifier: mapQuantifier(q), emotion: nil, isNegated: false, confidence: 0.7)
        }

        // ── Fallback ──
        return SentenceMeaning(type: .empty, action: nil, subject: nil, object: nil, modifier: nil, emotion: emotion, isNegated: hasNegation, confidence: 0.2)
    }

    // MARK: - Bare Question Analysis

    @MainActor
    private func analyzeBareQuestion(_ q: QuestionKind, bitcoinNoun: BitcoinConcept?, hasBitcoinUnit: Bool = false, hasOwnershipContext: Bool = false, memory: ConversationMemory) -> SentenceMeaning {
        // If a Bitcoin concept is mentioned, use it to determine the action
        if let noun = bitcoinNoun {
            switch q {
            case .what, .howMuch, .howMany, .where, .which:
                return SentenceMeaning(type: .question, action: defaultAction(for: noun), subject: .user, object: mapBitcoinNoun(noun), modifier: nil, emotion: nil, isNegated: false, confidence: 0.85)
            case .why, .how, .when, .who:
                return SentenceMeaning(type: .question, action: .explain, subject: nil, object: mapBitcoinNoun(noun), modifier: nil, emotion: nil, isNegated: false, confidence: 0.8)
            }
        }

        // "How much bitcoin do I have?" / "How many sats do I have?" → balance (ownership)
        if hasBitcoinUnit && hasOwnershipContext && (q == .howMuch || q == .howMany) {
            return SentenceMeaning(type: .question, action: .checkBalance, subject: .user, object: .balance, modifier: nil, emotion: nil, isNegated: false, confidence: 0.85)
        }

        // "How much is bitcoin?" → price query
        if hasBitcoinUnit && q == .howMuch {
            return SentenceMeaning(type: .question, action: .showPrice, subject: nil, object: .price, modifier: nil, emotion: nil, isNegated: false, confidence: 0.85)
        }
        // "What's bitcoin?" / "What is bitcoin?" → knowledge/explain question
        if hasBitcoinUnit && q == .what && !hasOwnershipContext {
            return SentenceMeaning(type: .question, action: .explain, subject: nil, object: .specific("bitcoin"), modifier: nil, emotion: nil, isNegated: false, confidence: 0.85)
        }

        switch q {
        case .what:  return SentenceMeaning(type: .question, action: .explain, subject: nil, object: .lastMentioned, modifier: nil, emotion: nil, isNegated: false, confidence: 0.8)
        case .why:   return SentenceMeaning(type: .question, action: .explain, subject: nil, object: .lastMentioned, modifier: nil, emotion: nil, isNegated: false, confidence: 0.8)
        case .how:   return SentenceMeaning(type: .question, action: .explain, subject: nil, object: .lastMentioned, modifier: nil, emotion: nil, isNegated: false, confidence: 0.7)
        case .when:
            if memory.lastSentTx != nil { return SentenceMeaning(type: .question, action: .explain, subject: nil, object: .transaction, modifier: nil, emotion: nil, isNegated: false, confidence: 0.8) }
            return SentenceMeaning(type: .question, action: .explain, subject: nil, object: .lastMentioned, modifier: nil, emotion: nil, isNegated: false, confidence: 0.6)
        case .where: return SentenceMeaning(type: .question, action: .showAddress, subject: nil, object: .address, modifier: nil, emotion: nil, isNegated: false, confidence: 0.7)
        case .which: return SentenceMeaning(type: .question, action: .explain, subject: nil, object: .lastMentioned, modifier: nil, emotion: nil, isNegated: false, confidence: 0.7)
        case .howMuch:
            if memory.currentFlowState != .idle { return SentenceMeaning(type: .question, action: .showFees, subject: nil, object: .fee, modifier: nil, emotion: nil, isNegated: false, confidence: 0.8) }
            return SentenceMeaning(type: .question, action: .checkBalance, subject: .user, object: .balance, modifier: nil, emotion: nil, isNegated: false, confidence: 0.8)
        case .howMany:
            if memory.currentFlowState != .idle { return SentenceMeaning(type: .question, action: .showFees, subject: nil, object: .fee, modifier: nil, emotion: nil, isNegated: false, confidence: 0.8) }
            return SentenceMeaning(type: .question, action: .checkBalance, subject: .user, object: .balance, modifier: nil, emotion: nil, isNegated: false, confidence: 0.8)
        default: return SentenceMeaning(type: .question, action: .help, subject: nil, object: nil, modifier: nil, emotion: nil, isNegated: false, confidence: 0.5)
        }
    }

    // MARK: - Comparative Analysis

    @MainActor
    private func analyzeComparative(_ dir: Direction, memory: ConversationMemory) -> SentenceMeaning {
        let feeContext = memory.lastShownFeeEstimates != nil
        switch dir {
        case .faster, .up, .increase, .raise, .higher:
            if feeContext { return SentenceMeaning(type: .command, action: .modify(what: "fee"), subject: nil, object: .fee, modifier: .increase, emotion: nil, isNegated: false, confidence: 0.85) }
            return SentenceMeaning(type: .command, action: .modify(what: "amount"), subject: nil, object: .amount, modifier: .increase, emotion: nil, isNegated: false, confidence: 0.7)
        case .slower, .cheaper, .down, .decrease, .lower, .reduce:
            if feeContext { return SentenceMeaning(type: .command, action: .modify(what: "fee"), subject: nil, object: .fee, modifier: .decrease, emotion: nil, isNegated: false, confidence: 0.85) }
            return SentenceMeaning(type: .command, action: .modify(what: "amount"), subject: nil, object: .amount, modifier: .decrease, emotion: nil, isNegated: false, confidence: 0.7)
        case .more:
            if memory.lastShownTransactions != nil { return SentenceMeaning(type: .command, action: .showHistory, subject: nil, object: .history, modifier: .increase, emotion: nil, isNegated: false, confidence: 0.8) }
            return SentenceMeaning(type: .command, action: .modify(what: "amount"), subject: nil, object: .amount, modifier: .increase, emotion: nil, isNegated: false, confidence: 0.6)
        case .less:
            return SentenceMeaning(type: .command, action: .modify(what: "amount"), subject: nil, object: .amount, modifier: .decrease, emotion: nil, isNegated: false, confidence: 0.6)
        default:
            return SentenceMeaning(type: .question, action: nil, subject: nil, object: .lastMentioned, modifier: nil, emotion: nil, isNegated: false, confidence: 0.3)
        }
    }

    // MARK: - Evaluation Analysis

    @MainActor
    private func analyzeEvaluation(_ eval: Evaluation, isNegated: Bool, memory: ConversationMemory) -> SentenceMeaning {
        let object: ResolvedObject = memory.lastShownFeeEstimates != nil ? .fee : (memory.lastAmount != nil ? .amount : .lastMentioned)
        let modifier: ResolvedModifier
        switch eval {
        case .tooMuch, .expensive, .high: modifier = .tooMuch
        case .tooLittle, .cheap, .low: modifier = .tooLittle
        case .enough, .good, .fine, .ok, .perfect, .correct, .right, .reasonable, .fair: modifier = .enough
        case .bad, .wrong: modifier = .notEnough
        default: modifier = .enough
        }
        return SentenceMeaning(type: .evaluation, action: nil, subject: nil, object: object, modifier: modifier, emotion: nil, isNegated: isNegated, confidence: 0.8)
    }

    // MARK: - Directional Analysis

    @MainActor
    private func analyzeDirectional(_ dir: NavigationDir, memory: ConversationMemory) -> SentenceMeaning {
        switch dir {
        case .back: return SentenceMeaning(type: .navigation, action: .undo, subject: nil, object: nil, modifier: nil, emotion: nil, isNegated: false, confidence: 0.8)
        case .again: return SentenceMeaning(type: .navigation, action: .repeatLast, subject: nil, object: nil, modifier: nil, emotion: nil, isNegated: false, confidence: 0.85)
        case .first: return SentenceMeaning(type: .navigation, action: .select(index: 0), subject: nil, object: .transaction, modifier: nil, emotion: nil, isNegated: false, confidence: 0.8)
        case .next: return SentenceMeaning(type: .navigation, action: .select(index: 1), subject: nil, object: .transaction, modifier: nil, emotion: nil, isNegated: false, confidence: 0.75)
        case .last: return SentenceMeaning(type: .navigation, action: .select(index: -1), subject: nil, object: .transaction, modifier: nil, emotion: nil, isNegated: false, confidence: 0.8)
        default: return SentenceMeaning(type: .navigation, action: nil, subject: nil, object: nil, modifier: nil, emotion: nil, isNegated: false, confidence: 0.5)
        }
    }

    // MARK: - General Verb Analysis

    @MainActor
    private func analyzeGeneralVerb(_ verb: GeneralAction, memory: ConversationMemory, isQuestion: Bool, emotion: EmotionType?) -> SentenceMeaning {
        switch verb {
        case .explain, .teach: return SentenceMeaning(type: .question, action: .explain, subject: nil, object: .lastMentioned, modifier: nil, emotion: emotion, isNegated: false, confidence: 0.7)
        case .help: return SentenceMeaning(type: .command, action: .help, subject: nil, object: nil, modifier: nil, emotion: emotion, isNegated: false, confidence: 0.9)
        case .repeat: return SentenceMeaning(type: .command, action: .repeatLast, subject: nil, object: nil, modifier: nil, emotion: emotion, isNegated: false, confidence: 0.85)
        case .undo: return SentenceMeaning(type: .command, action: .undo, subject: nil, object: nil, modifier: nil, emotion: emotion, isNegated: false, confidence: 0.85)
        case .wait, .stop: return SentenceMeaning(type: .command, action: .cancel, subject: nil, object: nil, modifier: nil, emotion: emotion, isNegated: false, confidence: 0.7)
        case .afford:
            return SentenceMeaning(type: .question, action: .compare, subject: .user, object: .lastMentioned, modifier: nil, emotion: emotion, isNegated: false, confidence: 0.8)
        default: return SentenceMeaning(type: .empty, action: nil, subject: nil, object: nil, modifier: nil, emotion: emotion, isNegated: false, confidence: 0.3)
        }
    }

    // MARK: - Single Word Analysis

    @MainActor
    private func analyzeSingleWord(_ item: (word: String, type: WordType), isQuestion: Bool, memory: ConversationMemory) -> SentenceMeaning {
        switch item.type {
        case .walletVerb(let v): return SentenceMeaning(type: isQuestion ? .question : .command, action: mapWalletVerb(v), subject: .user, object: nil, modifier: nil, emotion: nil, isNegated: false, confidence: isQuestion ? 0.75 : 0.9)
        case .bitcoinNoun(let n): return SentenceMeaning(type: isQuestion ? .question : .singleWord, action: defaultAction(for: n), subject: .user, object: mapBitcoinNoun(n), modifier: nil, emotion: nil, isNegated: false, confidence: 0.85)
        case .generalVerb(let v): return analyzeGeneralVerbSync(v, isQuestion: isQuestion)
        case .affirmation: return SentenceMeaning(type: .command, action: .confirm, subject: nil, object: nil, modifier: nil, emotion: nil, isNegated: false, confidence: 0.85)
        case .negation: return SentenceMeaning(type: .command, action: .cancel, subject: nil, object: nil, modifier: nil, emotion: nil, isNegated: true, confidence: 0.85)
        case .emotion(let e): return SentenceMeaning(type: .emotional, action: nil, subject: nil, object: nil, modifier: nil, emotion: e, isNegated: false, confidence: 0.9)
        case .comparative(let d): return analyzeComparative(d, memory: memory)
        case .directional(let d): return analyzeDirectionalSync(d)
        case .questionWord(let q): return analyzeQuestionWordSync(q)

        // Context-aware: bare number
        case .number(let n):
            if case .awaitingAmount = memory.currentFlowState {
                return SentenceMeaning(type: .bare, action: .send, subject: nil, object: .amount, modifier: nil, emotion: nil, isNegated: false, confidence: 0.95)
            }
            return SentenceMeaning(type: .bare, action: nil, subject: nil, object: .amount, modifier: .specific(n), emotion: nil, isNegated: false, confidence: 0.4)

        // Context-aware: bare Bitcoin address
        case .bitcoinAddress:
            if case .awaitingAddress = memory.currentFlowState {
                return SentenceMeaning(type: .bare, action: .send, subject: nil, object: .address, modifier: nil, emotion: nil, isNegated: false, confidence: 0.95)
            }
            return SentenceMeaning(type: .bare, action: .send, subject: nil, object: .address, modifier: nil, emotion: nil, isNegated: false, confidence: 0.6)

        case .pronoun(let p):
            // Context-aware pronoun handling
            switch p {
            case .same:
                // "Same" = repeat last action
                return SentenceMeaning(type: .navigation, action: .repeatLast, subject: nil, object: nil, modifier: nil, emotion: nil, isNegated: false, confidence: 0.7)
            default:
                return SentenceMeaning(type: .empty, action: nil, subject: nil, object: .lastMentioned, modifier: nil, emotion: nil, isNegated: false, confidence: 0.3)
            }

        case .evaluative(let e): return analyzeEvaluationSync(e)
        case .bitcoinUnit: return SentenceMeaning(type: .question, action: .showPrice, subject: nil, object: .price, modifier: nil, emotion: nil, isNegated: false, confidence: 0.6)
        case .greeting: return SentenceMeaning(type: .emotional, action: nil, subject: nil, object: nil, modifier: nil, emotion: nil, isNegated: false, confidence: 0.9)
        case .txid: return SentenceMeaning(type: .bare, action: .showHistory, subject: nil, object: .transaction, modifier: nil, emotion: nil, isNegated: false, confidence: 0.8)
        case .unknown(let w) where w.hasPrefix("fiat_amount:"):
            return SentenceMeaning(type: .command, action: .convert, subject: nil, object: .price, modifier: nil, emotion: nil, isNegated: false, confidence: 0.8)
        default: return SentenceMeaning(type: .empty, action: nil, subject: nil, object: nil, modifier: nil, emotion: nil, isNegated: false, confidence: 0.2)
        }
    }

    // Non-MainActor versions for single-word analysis (no memory access needed)
    private func analyzeGeneralVerbSync(_ verb: GeneralAction, isQuestion: Bool) -> SentenceMeaning {
        switch verb {
        case .explain, .teach: return SentenceMeaning(type: .question, action: .explain, subject: nil, object: .lastMentioned, modifier: nil, emotion: nil, isNegated: false, confidence: 0.7)
        case .help: return SentenceMeaning(type: .command, action: .help, subject: nil, object: nil, modifier: nil, emotion: nil, isNegated: false, confidence: 0.9)
        case .repeat: return SentenceMeaning(type: .command, action: .repeatLast, subject: nil, object: nil, modifier: nil, emotion: nil, isNegated: false, confidence: 0.85)
        case .undo: return SentenceMeaning(type: .command, action: .undo, subject: nil, object: nil, modifier: nil, emotion: nil, isNegated: false, confidence: 0.85)
        case .wait, .stop: return SentenceMeaning(type: .command, action: .cancel, subject: nil, object: nil, modifier: nil, emotion: nil, isNegated: false, confidence: 0.7)
        case .afford: return SentenceMeaning(type: .question, action: .compare, subject: .user, object: .lastMentioned, modifier: nil, emotion: nil, isNegated: false, confidence: 0.8)
        default: return SentenceMeaning(type: .empty, action: nil, subject: nil, object: nil, modifier: nil, emotion: nil, isNegated: false, confidence: 0.3)
        }
    }

    private func analyzeComparativeSync(_ dir: Direction) -> SentenceMeaning {
        switch dir {
        case .faster, .up, .increase, .raise, .higher:
            return SentenceMeaning(type: .command, action: .modify(what: "fee"), subject: nil, object: .fee, modifier: .increase, emotion: nil, isNegated: false, confidence: 0.7)
        case .slower, .cheaper, .down, .decrease, .lower, .reduce:
            return SentenceMeaning(type: .command, action: .modify(what: "fee"), subject: nil, object: .fee, modifier: .decrease, emotion: nil, isNegated: false, confidence: 0.7)
        case .more:
            return SentenceMeaning(type: .command, action: .modify(what: "amount"), subject: nil, object: .amount, modifier: .increase, emotion: nil, isNegated: false, confidence: 0.6)
        case .less:
            return SentenceMeaning(type: .command, action: .modify(what: "amount"), subject: nil, object: .amount, modifier: .decrease, emotion: nil, isNegated: false, confidence: 0.6)
        default:
            return SentenceMeaning(type: .question, action: nil, subject: nil, object: .lastMentioned, modifier: nil, emotion: nil, isNegated: false, confidence: 0.3)
        }
    }

    private func analyzeEvaluationSync(_ eval: Evaluation) -> SentenceMeaning {
        let modifier: ResolvedModifier
        switch eval {
        case .tooMuch, .expensive, .high: modifier = .tooMuch
        case .tooLittle, .cheap, .low: modifier = .tooLittle
        case .enough, .good, .fine, .ok, .perfect, .correct, .right, .reasonable, .fair: modifier = .enough
        case .bad, .wrong: modifier = .notEnough
        default: modifier = .enough
        }
        return SentenceMeaning(type: .evaluation, action: nil, subject: nil, object: .lastMentioned, modifier: modifier, emotion: nil, isNegated: false, confidence: 0.8)
    }

    private func analyzeDirectionalSync(_ dir: NavigationDir) -> SentenceMeaning {
        switch dir {
        case .back: return SentenceMeaning(type: .navigation, action: .undo, subject: nil, object: nil, modifier: nil, emotion: nil, isNegated: false, confidence: 0.8)
        case .again: return SentenceMeaning(type: .navigation, action: .repeatLast, subject: nil, object: nil, modifier: nil, emotion: nil, isNegated: false, confidence: 0.85)
        case .first: return SentenceMeaning(type: .navigation, action: .select(index: 0), subject: nil, object: .transaction, modifier: nil, emotion: nil, isNegated: false, confidence: 0.8)
        case .next: return SentenceMeaning(type: .navigation, action: .select(index: 1), subject: nil, object: .transaction, modifier: nil, emotion: nil, isNegated: false, confidence: 0.75)
        case .last: return SentenceMeaning(type: .navigation, action: .select(index: -1), subject: nil, object: .transaction, modifier: nil, emotion: nil, isNegated: false, confidence: 0.8)
        default: return SentenceMeaning(type: .navigation, action: nil, subject: nil, object: nil, modifier: nil, emotion: nil, isNegated: false, confidence: 0.5)
        }
    }

    private func analyzeQuestionWordSync(_ q: QuestionKind) -> SentenceMeaning {
        switch q {
        case .what, .why, .how: return SentenceMeaning(type: .question, action: .explain, subject: nil, object: .lastMentioned, modifier: nil, emotion: nil, isNegated: false, confidence: 0.7)
        case .where: return SentenceMeaning(type: .question, action: .showAddress, subject: nil, object: .address, modifier: nil, emotion: nil, isNegated: false, confidence: 0.7)
        case .howMuch: return SentenceMeaning(type: .question, action: .checkBalance, subject: .user, object: .balance, modifier: nil, emotion: nil, isNegated: false, confidence: 0.8)
        default: return SentenceMeaning(type: .question, action: .help, subject: nil, object: nil, modifier: nil, emotion: nil, isNegated: false, confidence: 0.5)
        }
    }

    // MARK: - Mappers

    private func mapWalletVerb(_ v: WalletAction) -> ResolvedAction {
        switch v {
        case .send: return .send; case .receive: return .receive; case .check, .verify: return .checkBalance
        case .show: return .checkBalance; case .hide: return .hide; case .export: return .export
        case .bump: return .bump; case .refresh, .sync: return .refresh; case .generate: return .generate
        case .confirm: return .confirm; case .cancel: return .cancel; case .convert: return .convert
        case .backup: return .backup
        }
    }

    private func mapBitcoinNoun(_ n: BitcoinConcept) -> ResolvedObject {
        switch n {
        case .balance: return .balance; case .fee, .fees: return .fee; case .address: return .address
        case .transaction, .transactions: return .transaction; case .utxo, .utxos: return .utxo
        case .price: return .price; case .wallet: return .wallet; case .network: return .network; case .mempool: return .fee
        case .history: return .history; default: return .lastMentioned
        }
    }

    private func defaultAction(for n: BitcoinConcept) -> ResolvedAction {
        switch n {
        case .balance: return .checkBalance; case .fee, .fees: return .showFees; case .address: return .showAddress
        case .transaction, .transactions, .history: return .showHistory; case .utxo, .utxos: return .showUTXO
        case .price: return .showPrice; case .wallet: return .showHealth; case .network: return .showNetwork; case .mempool: return .showFees
        default: return .help
        }
    }

    private func mapGeneralVerbWithNoun(_ v: GeneralAction, _ n: BitcoinConcept) -> ResolvedAction {
        if v == .explain || v == .teach { return .explain }
        return defaultAction(for: n)
    }

    private func resolveModifier(_ comp: Direction?, _ quant: Quantity?) -> ResolvedModifier? {
        if let c = comp {
            switch c {
            case .more, .bigger, .faster, .higher, .up, .increase, .raise: return .increase
            case .less, .smaller, .slower, .cheaper, .lower, .down, .decrease, .reduce: return .decrease
            default: return nil
            }
        }
        if let q = quant { return mapQuantifier(q) }
        return nil
    }

    private func mapQuantifier(_ q: Quantity) -> ResolvedModifier {
        switch q {
        case .all, .maximum, .every: return .all
        case .half: return .half
        case .double: return .double
        case .none, .minimum: return .decrease
        default: return .increase
        }
    }

    // MARK: - Helpers

    private func isGreetingOrNoise(_ t: WordType) -> Bool {
        if case .greeting = t { return true }
        if case .unknown = t { return true }
        if case .questionWord = t { return true }  // "what's up", "how are you"
        if case .pronoun = t { return true }        // "hi there"
        if case .comparative = t { return true }    // "what's up" (up = comparative)
        return isNoise(t)
    }
    private func isEmotionOrNoise(_ t: WordType) -> Bool {
        if case .emotion = t { return true }
        if case .unknown = t { return true }   // "you", "so", "much", etc.
        if case .pronoun = t { return true }   // "it", "that"
        if case .temporal = t { return true }  // "right_now"
        return isNoise(t)
    }
    private func isAffOrNeg(_ t: WordType) -> Bool {
        if case .affirmation = t { return true }
        if case .negation = t { return true }
        if case .pronoun = t { return true }       // "I'm sure" — pronoun-like words near affirmations
        if case .unknown(let w) = t {
            // Treat common filler words as compatible with affirmation/negation
            let fillers = ["i'm", "im", "i", "me", "do", "am", "is", "it", "please", "just", "really", "actually"]
            if fillers.contains(w) { return true }
        }
        return false
    }
    private func isFluff(_ t: WordType) -> Bool {
        // Pronouns, unknowns that commonly appear alongside affirmation/negation
        if case .pronoun = t { return true }
        if case .unknown(let w) = t {
            let fillers = ["i'm", "im", "i", "me", "do", "am", "is", "it", "please", "just",
                           "really", "actually", "well", "right", "thing", "so", "then"]
            return fillers.contains(w)
        }
        return false
    }
    private func isNoise(_ t: WordType) -> Bool { if case .article = t { return true }; if case .preposition = t { return true }; if case .conjunction = t { return true }; return false }
    /// Matches words that can accompany "send" in a confirmatory context: "send it", "send this"
    private func isSendConfirmWord(_ t: WordType) -> Bool {
        if case .walletVerb(.send) = t { return true }
        if case .pronoun = t { return true }
        if case .temporal = t { return true } // "send it now"
        return isNoise(t)
    }
    private func isBitcoinUnitOrNoise(_ t: WordType) -> Bool {
        if case .bitcoinUnit = t { return true }
        if case .article = t { return true }
        if case .pronoun = t { return true }
        if case .unknown = t { return true }
        return isNoise(t)
    }

    /// When multiple Bitcoin nouns appear, pick the most actionable one.
    /// Priority: fee/fees > transaction/transactions/history > balance > price > address > network/mempool/wallet
    private func pickMostSpecificNoun(_ nouns: [BitcoinConcept]) -> BitcoinConcept? {
        guard nouns.count > 1 else { return nouns.first }
        let priority: [BitcoinConcept] = [.fee, .fees, .transaction, .transactions, .history,
                                           .balance, .price, .address, .utxo, .utxos,
                                           .network, .mempool, .wallet]
        for p in priority {
            if nouns.contains(p) { return p }
        }
        return nouns.first
    }
}
