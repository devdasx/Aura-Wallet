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
        if classified.allSatisfy({ isAffOrNeg($0.type) || isNoise($0.type) }) {
            if hasNegation { return SentenceMeaning(type: .command, action: .cancel, subject: nil, object: nil, modifier: nil, emotion: nil, isNegated: true, confidence: 0.85) }
            return SentenceMeaning(type: .command, action: .confirm, subject: nil, object: nil, modifier: nil, emotion: nil, isNegated: false, confidence: 0.85)
        }

        // ── RULE 4: Bare question word ──
        if isQuestion && walletVerb == nil && generalVerb == nil && questionWord != nil && !hasNumber && !hasAddress {
            return analyzeBareQuestion(questionWord!, bitcoinNoun: bitcoinNoun, memory: memory)
        }

        // ── RULE 5: Comparative alone ──
        if walletVerb == nil && generalVerb == nil && comparative != nil {
            return analyzeComparative(comparative!, memory: memory)
        }

        // ── RULE 6: Evaluative ──
        if evaluative != nil && walletVerb == nil {
            return analyzeEvaluation(evaluative!, isNegated: hasNegation, memory: memory)
        }

        // ── RULE 7: Directional ──
        if directional != nil && walletVerb == nil && generalVerb == nil {
            return analyzeDirectional(directional!, memory: memory)
        }

        // ── RULE 8: "Can I afford it?" ──
        if modal != nil && generalVerb == .afford {
            return SentenceMeaning(type: .question, action: .compare, subject: .user, object: .lastMentioned, modifier: nil, emotion: nil, isNegated: hasNegation, confidence: 0.85)
        }

        // ── RULE 9: "Is it/that safe?" ──
        if isQuestion && evaluative == .safe {
            return SentenceMeaning(type: .question, action: .explain, subject: nil, object: .wallet, modifier: nil, emotion: nil, isNegated: false, confidence: 0.8)
        }

        // ── RULE 10: Wallet verb present ──
        if let verb = walletVerb {
            let action = mapWalletVerb(verb)
            let object = bitcoinNoun.map { mapBitcoinNoun($0) } ?? .lastMentioned
            let modifier = resolveModifier(comparative, quantifier)

            // "send?" with no number/address = question about sending
            if isQuestion && !hasNumber && !hasAddress && classified.count <= 3 {
                return SentenceMeaning(type: .question, action: action, subject: .user, object: object, modifier: modifier, emotion: emotion, isNegated: hasNegation, confidence: 0.75)
            }

            // Negated wallet verb: "I don't want to send" → cancel
            if hasNegation {
                return SentenceMeaning(type: .command, action: .cancel, subject: .user, object: object, modifier: nil, emotion: emotion, isNegated: true, confidence: 0.8)
            }

            return SentenceMeaning(type: .command, action: action, subject: .user, object: object, modifier: modifier, emotion: emotion, isNegated: false, confidence: 0.9)
        }

        // ── RULE 11: General verb + Bitcoin noun ──
        if let gVerb = generalVerb, let noun = bitcoinNoun {
            let action = mapGeneralVerbWithNoun(gVerb, noun)
            return SentenceMeaning(type: isQuestion ? .question : .command, action: action, subject: .user, object: mapBitcoinNoun(noun), modifier: nil, emotion: emotion, isNegated: hasNegation, confidence: 0.85)
        }

        // ── RULE 12: Bitcoin noun alone ──
        if let noun = bitcoinNoun, walletVerb == nil {
            let action = defaultAction(for: noun)
            return SentenceMeaning(type: isQuestion ? .question : .singleWord, action: action, subject: .user, object: mapBitcoinNoun(noun), modifier: nil, emotion: emotion, isNegated: hasNegation, confidence: 0.8)
        }

        // ── RULE 13: General verb alone ──
        if let gVerb = generalVerb {
            return analyzeGeneralVerb(gVerb, memory: memory, isQuestion: isQuestion, emotion: emotion)
        }

        // ── RULE 14: Bare Bitcoin address or number ──
        if hasAddress && classified.count <= 3 {
            return SentenceMeaning(type: .bare, action: .send, subject: nil, object: .address, modifier: nil, emotion: nil, isNegated: false, confidence: 0.6)
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
    private func analyzeBareQuestion(_ q: QuestionKind, bitcoinNoun: BitcoinConcept?, memory: ConversationMemory) -> SentenceMeaning {
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

    private func analyzeSingleWord(_ item: (word: String, type: WordType), isQuestion: Bool, memory: ConversationMemory) -> SentenceMeaning {
        switch item.type {
        case .walletVerb(let v): return SentenceMeaning(type: isQuestion ? .question : .command, action: mapWalletVerb(v), subject: .user, object: nil, modifier: nil, emotion: nil, isNegated: false, confidence: isQuestion ? 0.75 : 0.9)
        case .bitcoinNoun(let n): return SentenceMeaning(type: isQuestion ? .question : .singleWord, action: defaultAction(for: n), subject: .user, object: mapBitcoinNoun(n), modifier: nil, emotion: nil, isNegated: false, confidence: 0.85)
        case .generalVerb(let v): return analyzeGeneralVerbSync(v, isQuestion: isQuestion)
        case .affirmation: return SentenceMeaning(type: .command, action: .confirm, subject: nil, object: nil, modifier: nil, emotion: nil, isNegated: false, confidence: 0.85)
        case .negation: return SentenceMeaning(type: .command, action: .cancel, subject: nil, object: nil, modifier: nil, emotion: nil, isNegated: true, confidence: 0.85)
        case .emotion(let e): return SentenceMeaning(type: .emotional, action: nil, subject: nil, object: nil, modifier: nil, emotion: e, isNegated: false, confidence: 0.9)
        case .comparative(let d): return analyzeComparativeSync(d)
        case .directional(let d): return analyzeDirectionalSync(d)
        case .questionWord(let q): return analyzeQuestionWordSync(q)
        case .bitcoinAddress: return SentenceMeaning(type: .bare, action: .send, subject: nil, object: .address, modifier: nil, emotion: nil, isNegated: false, confidence: 0.6)
        case .bitcoinUnit: return SentenceMeaning(type: .question, action: .showPrice, subject: nil, object: .price, modifier: nil, emotion: nil, isNegated: false, confidence: 0.6)
        case .greeting: return SentenceMeaning(type: .emotional, action: nil, subject: nil, object: nil, modifier: nil, emotion: nil, isNegated: false, confidence: 0.9)
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
        case .price: return .price; case .wallet: return .wallet; case .network, .mempool: return .network
        case .history: return .history; default: return .lastMentioned
        }
    }

    private func defaultAction(for n: BitcoinConcept) -> ResolvedAction {
        switch n {
        case .balance: return .checkBalance; case .fee, .fees: return .showFees; case .address: return .showAddress
        case .transaction, .transactions, .history: return .showHistory; case .utxo, .utxos: return .showUTXO
        case .price: return .showPrice; case .wallet: return .showHealth; case .network, .mempool: return .showNetwork
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

    private func isGreetingOrNoise(_ t: WordType) -> Bool { if case .greeting = t { return true }; if case .unknown = t { return true }; return isNoise(t) }
    private func isEmotionOrNoise(_ t: WordType) -> Bool { if case .emotion = t { return true }; return isNoise(t) }
    private func isAffOrNeg(_ t: WordType) -> Bool { if case .affirmation = t { return true }; if case .negation = t { return true }; return false }
    private func isNoise(_ t: WordType) -> Bool { if case .article = t { return true }; if case .preposition = t { return true }; if case .conjunction = t { return true }; return false }
}
