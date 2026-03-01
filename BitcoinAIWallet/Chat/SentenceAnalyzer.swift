// MARK: - SentenceAnalyzer.swift
// Bitcoin AI Wallet
//
// Analyzes classified words into a SentenceMeaning structure.
// Extracts: sentence type, action, subject, object, modifier, emotion,
// and negation from the grammatical word classifications.
//
// Patterns recognized:
// 1. Single word / bare questions ("What?" "Balance?" "Fees?")
// 2. Comparatives alone ("Faster" "Cheaper")
// 3. Evaluatives ("That's too much" "Good enough")
// 4. Directionals ("Back" "Again")
// 5. Modal + general verb ("Can I afford it?")
// 6. Wallet verb commands ("send 0.01 to bc1q...")
// 7. General verb + bitcoin noun ("show my balance")
// 8. Bitcoin noun alone ("balance" → check balance)
// 9. Affirmation / Negation alone ("yes" "no")
//
// Platform: iOS 17.0+
// Framework: Foundation

import Foundation

// MARK: - Sentence Types

enum SentenceType: Equatable {
    case command       // "Send 0.01 BTC"
    case question      // "What is my balance?"
    case statement     // "I have 0.5 BTC"
    case evaluation    // "That's too much"
    case navigation    // "Back", "Again"
    case emotional     // "Thanks!", "Wow!"
    case singleWord    // "Balance", "Fees"
    case bare          // "What?", "And?"
    case empty
}

// MARK: - Resolved Components

enum ResolvedAction: Equatable {
    case send, receive, checkBalance, showFees, showPrice, showHistory
    case showDetail, newAddress, exportHistory, utxoList, bumpFee
    case networkStatus, walletHealth, settings, helpUser, about
    case confirm, cancel, hide, show, refresh, convert
}

enum ResolvedSubject: Equatable {
    case user, wallet, lastEntity, network, unspecified
}

enum ResolvedObject: Equatable {
    case balance, fee, amount(Decimal), address(String), transaction(String)
    case price, history, utxo, wallet, network, money, unspecified
}

enum ResolvedModifier: Equatable {
    case increase, decrease
    case fastest, cheapest, safest
    case all, half, some, none
    case tooMuch, tooLittle, enough
    case now, later, soon
}

// MARK: - SentenceMeaning

struct SentenceMeaning: Equatable {
    let type: SentenceType
    let action: ResolvedAction?
    let subject: ResolvedSubject
    let object: ResolvedObject?
    let modifier: ResolvedModifier?
    let emotion: WordEmotionType?
    let isNegated: Bool
    let confidence: Double
}

// MARK: - SentenceAnalyzer

final class SentenceAnalyzer {

    // MARK: - Analysis

    func analyze(_ words: [ClassifiedWord]) -> SentenceMeaning {
        guard !words.isEmpty else {
            return SentenceMeaning(type: .empty, action: nil, subject: .unspecified,
                                   object: nil, modifier: nil, emotion: nil,
                                   isNegated: false, confidence: 0)
        }

        // Filter out punctuation tokens for analysis
        let meaningful = words.filter { w in
            let t = w.word.trimmingCharacters(in: .punctuationCharacters)
            return !t.isEmpty || w.type != nil
        }

        let hasQuestion = words.contains { $0.word == "?" }
        let isNegated = words.contains { $0.type == .negation }
        let emotion = extractEmotion(from: words)

        // 1. Single meaningful word
        if meaningful.count == 1 {
            return analyzeSingleWord(meaningful[0], isQuestion: hasQuestion,
                                     isNegated: isNegated, emotion: emotion)
        }

        // 2. Bare question ("What?" "Why?" "And?")
        if meaningful.count <= 2 && hasQuestion {
            if let qWord = meaningful.first(where: { if case .questionWord = $0.type { return true }; return false }) {
                return SentenceMeaning(type: .bare, action: nil, subject: .unspecified,
                                       object: nil, modifier: nil, emotion: nil,
                                       isNegated: false, confidence: 0.8)
            }
        }

        // 3. Comparative alone ("Faster" "Cheaper" "More")
        if let comp = extractComparative(from: meaningful), meaningful.count <= 3 {
            return SentenceMeaning(type: .navigation, action: nil, subject: .unspecified,
                                   object: nil, modifier: comp, emotion: nil,
                                   isNegated: isNegated, confidence: 0.75)
        }

        // 4. Evaluative sentence ("That's too much" "Good enough" "Is that safe?")
        if let eval = extractEvaluation(from: meaningful) {
            return SentenceMeaning(type: .evaluation, action: nil, subject: .lastEntity,
                                   object: nil, modifier: eval, emotion: nil,
                                   isNegated: isNegated, confidence: 0.8)
        }

        // 5. Directional alone ("Back" "Again" "Next")
        if let dir = extractDirectional(from: meaningful), meaningful.count <= 2 {
            return SentenceMeaning(type: .navigation, action: nil, subject: .unspecified,
                                   object: nil, modifier: nil, emotion: nil,
                                   isNegated: isNegated, confidence: 0.7)
        }

        // 6. Emotion-only ("Thanks!" "Wow!")
        if let emo = emotion, meaningful.allSatisfy({ isEmotionOrStructure($0) }) {
            return SentenceMeaning(type: .emotional, action: nil, subject: .user,
                                   object: nil, modifier: nil, emotion: emo,
                                   isNegated: false, confidence: 0.85)
        }

        // 7. Modal + general verb ("Can I afford it?" "Should I send?")
        if let modalResult = analyzeModalPattern(meaningful, isQuestion: hasQuestion, isNegated: isNegated) {
            return modalResult
        }

        // 8. Wallet verb command ("send 0.01 to bc1q...")
        if let walletResult = analyzeWalletVerb(meaningful, isQuestion: hasQuestion, isNegated: isNegated) {
            return walletResult
        }

        // 9. General verb + bitcoin noun ("show my balance" "check the fees")
        if let generalResult = analyzeGeneralVerb(meaningful, isQuestion: hasQuestion, isNegated: isNegated) {
            return generalResult
        }

        // 10. Question word + bitcoin noun ("What is my balance?" "How much are fees?")
        if let questionResult = analyzeQuestionPattern(meaningful, isNegated: isNegated) {
            return questionResult
        }

        // 11. Bitcoin noun alone or prominent ("balance" "fees" "price")
        if let nounResult = analyzeBitcoinNoun(meaningful, isQuestion: hasQuestion, isNegated: isNegated) {
            return nounResult
        }

        // 12. Affirmation / Negation alone
        if meaningful.allSatisfy({ $0.type == .affirmation || $0.type == .article || $0.type == nil }) {
            if meaningful.contains(where: { $0.type == .affirmation }) {
                return SentenceMeaning(type: .command, action: .confirm, subject: .user,
                                       object: nil, modifier: nil, emotion: nil,
                                       isNegated: false, confidence: 0.9)
            }
        }

        if isNegated && meaningful.count <= 3 && !meaningful.contains(where: { isActionWord($0) }) {
            return SentenceMeaning(type: .command, action: .cancel, subject: .user,
                                   object: nil, modifier: nil, emotion: nil,
                                   isNegated: true, confidence: 0.85)
        }

        // 13. Fallback — try to extract any meaningful combination
        let action = extractAnyAction(from: meaningful)
        let object = extractAnyObject(from: meaningful)
        let sentenceType: SentenceType = hasQuestion ? .question : (action != nil ? .command : .statement)

        return SentenceMeaning(type: sentenceType, action: action, subject: .user,
                               object: object, modifier: nil, emotion: emotion,
                               isNegated: isNegated,
                               confidence: action != nil ? 0.5 : 0.3)
    }

    // MARK: - Single Word Analysis

    private func analyzeSingleWord(_ word: ClassifiedWord, isQuestion: Bool,
                                    isNegated: Bool, emotion: WordEmotionType?) -> SentenceMeaning {
        guard let type = word.type else {
            return SentenceMeaning(type: .singleWord, action: nil, subject: .unspecified,
                                   object: nil, modifier: nil, emotion: nil,
                                   isNegated: false, confidence: 0.2)
        }

        switch type {
        case .bitcoinNoun(let concept):
            let (action, object) = mapConceptToActionObject(concept)
            return SentenceMeaning(type: .singleWord, action: action, subject: .wallet,
                                   object: object, modifier: nil, emotion: nil,
                                   isNegated: false, confidence: 0.8)

        case .walletVerb(let action):
            return SentenceMeaning(type: .command, action: mapWalletAction(action),
                                   subject: .user, object: nil, modifier: nil, emotion: nil,
                                   isNegated: isNegated, confidence: 0.75)

        case .affirmation:
            return SentenceMeaning(type: .command, action: .confirm, subject: .user,
                                   object: nil, modifier: nil, emotion: nil,
                                   isNegated: false, confidence: 0.9)

        case .negation:
            return SentenceMeaning(type: .command, action: .cancel, subject: .user,
                                   object: nil, modifier: nil, emotion: nil,
                                   isNegated: true, confidence: 0.85)

        case .emotionWord(let emo):
            return SentenceMeaning(type: .emotional, action: nil, subject: .user,
                                   object: nil, modifier: nil, emotion: emo,
                                   isNegated: false, confidence: 0.8)

        case .questionWord:
            return SentenceMeaning(type: .bare, action: nil, subject: .unspecified,
                                   object: nil, modifier: nil, emotion: nil,
                                   isNegated: false, confidence: 0.7)

        case .comparative(let dir):
            return SentenceMeaning(type: .navigation, action: nil, subject: .lastEntity,
                                   object: nil, modifier: mapComparative(dir), emotion: nil,
                                   isNegated: false, confidence: 0.7)

        case .generalVerb(.helpMe):
            return SentenceMeaning(type: .command, action: .helpUser, subject: .user,
                                   object: nil, modifier: nil, emotion: nil,
                                   isNegated: false, confidence: 0.8)

        default:
            return SentenceMeaning(type: .singleWord, action: nil, subject: .unspecified,
                                   object: nil, modifier: nil, emotion: emotion,
                                   isNegated: isNegated, confidence: 0.3)
        }
    }

    // MARK: - Modal Pattern ("Can I afford it?")

    private func analyzeModalPattern(_ words: [ClassifiedWord], isQuestion: Bool,
                                      isNegated: Bool) -> SentenceMeaning? {
        guard let modalIdx = words.firstIndex(where: { if case .modal = $0.type { return true }; return false }) else {
            return nil
        }

        // Look for general verb after modal
        let afterModal = Array(words.suffix(from: modalIdx))
        guard let verbWord = afterModal.first(where: { if case .generalVerb = $0.type { return true }; return false }),
              case .generalVerb(let verb) = verbWord.type else {
            return nil
        }

        // "Can I afford it/that?"
        if verb == .afford {
            let object = extractAnyObject(from: words) ?? .balance
            return SentenceMeaning(type: .question, action: .checkBalance, subject: .user,
                                   object: object, modifier: nil, emotion: nil,
                                   isNegated: isNegated, confidence: 0.85)
        }

        // "Can I send?" "Should I confirm?"
        if let walletAction = afterModal.first(where: { if case .walletVerb = $0.type { return true }; return false }),
           case .walletVerb(let action) = walletAction.type {
            return SentenceMeaning(type: .question, action: mapWalletAction(action), subject: .user,
                                   object: extractAnyObject(from: words), modifier: nil, emotion: nil,
                                   isNegated: isNegated, confidence: 0.75)
        }

        // "Can I see my balance?" "Could you show fees?"
        if verb == .see || verb == .know {
            if let obj = extractAnyObject(from: words) {
                let action = objectToAction(obj)
                return SentenceMeaning(type: .question, action: action, subject: .user,
                                       object: obj, modifier: nil, emotion: nil,
                                       isNegated: isNegated, confidence: 0.75)
            }
        }

        return nil
    }

    // MARK: - Wallet Verb Pattern ("send 0.01 to bc1q...")

    private func analyzeWalletVerb(_ words: [ClassifiedWord], isQuestion: Bool,
                                    isNegated: Bool) -> SentenceMeaning? {
        guard let verbWord = words.first(where: { if case .walletVerb = $0.type { return true }; return false }),
              case .walletVerb(let action) = verbWord.type else {
            return nil
        }

        let resolved = mapWalletAction(action)
        let object = extractAnyObject(from: words)
        let modifier = extractAnyModifier(from: words)
        let sentenceType: SentenceType = isQuestion ? .question : .command

        return SentenceMeaning(type: sentenceType, action: resolved, subject: .user,
                               object: object, modifier: modifier, emotion: nil,
                               isNegated: isNegated, confidence: 0.85)
    }

    // MARK: - General Verb Pattern ("show my balance")

    private func analyzeGeneralVerb(_ words: [ClassifiedWord], isQuestion: Bool,
                                     isNegated: Bool) -> SentenceMeaning? {
        guard words.contains(where: { if case .generalVerb = $0.type { return true }; return false }) else {
            return nil
        }

        // Need a bitcoin noun to make this meaningful
        guard let nounWord = words.first(where: { if case .bitcoinNoun = $0.type { return true }; return false }),
              case .bitcoinNoun(let concept) = nounWord.type else {
            return nil
        }

        let (action, object) = mapConceptToActionObject(concept)
        let modifier = extractAnyModifier(from: words)

        return SentenceMeaning(type: isQuestion ? .question : .command,
                               action: action, subject: .user,
                               object: object, modifier: modifier, emotion: nil,
                               isNegated: isNegated, confidence: 0.75)
    }

    // MARK: - Question Pattern ("What is my balance?")

    private func analyzeQuestionPattern(_ words: [ClassifiedWord], isNegated: Bool) -> SentenceMeaning? {
        guard words.contains(where: { if case .questionWord = $0.type { return true }; return false }) else {
            return nil
        }

        // Look for a bitcoin noun or wallet verb
        if let nounWord = words.first(where: { if case .bitcoinNoun = $0.type { return true }; return false }),
           case .bitcoinNoun(let concept) = nounWord.type {
            let (action, object) = mapConceptToActionObject(concept)
            return SentenceMeaning(type: .question, action: action, subject: .wallet,
                                   object: object, modifier: nil, emotion: nil,
                                   isNegated: isNegated, confidence: 0.8)
        }

        if let verbWord = words.first(where: { if case .walletVerb = $0.type { return true }; return false }),
           case .walletVerb(let action) = verbWord.type {
            return SentenceMeaning(type: .question, action: mapWalletAction(action), subject: .user,
                                   object: nil, modifier: nil, emotion: nil,
                                   isNegated: isNegated, confidence: 0.7)
        }

        // "How much?" with money/amount context
        if words.contains(where: { if case .questionWord(.how) = $0.type { return true }; return false }) {
            if words.contains(where: { $0.word.lowercased() == "much" }) {
                // "How much do I have?" → balance
                if words.contains(where: { if case .generalVerb(.have) = $0.type { return true }; return false }) {
                    return SentenceMeaning(type: .question, action: .checkBalance, subject: .user,
                                           object: .balance, modifier: nil, emotion: nil,
                                           isNegated: isNegated, confidence: 0.85)
                }
                return SentenceMeaning(type: .question, action: .checkBalance, subject: .user,
                                       object: .balance, modifier: nil, emotion: nil,
                                       isNegated: isNegated, confidence: 0.7)
            }
        }

        return nil
    }

    // MARK: - Bitcoin Noun Pattern ("balance" "fees" "price")

    private func analyzeBitcoinNoun(_ words: [ClassifiedWord], isQuestion: Bool,
                                     isNegated: Bool) -> SentenceMeaning? {
        guard let nounWord = words.first(where: { if case .bitcoinNoun = $0.type { return true }; return false }),
              case .bitcoinNoun(let concept) = nounWord.type else {
            return nil
        }

        let (action, object) = mapConceptToActionObject(concept)
        let modifier = extractAnyModifier(from: words)

        return SentenceMeaning(type: isQuestion ? .question : .singleWord,
                               action: action, subject: .wallet,
                               object: object, modifier: modifier, emotion: nil,
                               isNegated: isNegated, confidence: 0.7)
    }

    // MARK: - Extraction Helpers

    private func extractEmotion(from words: [ClassifiedWord]) -> WordEmotionType? {
        for word in words {
            if case .emotionWord(let emo) = word.type { return emo }
        }
        return nil
    }

    private func extractComparative(from words: [ClassifiedWord]) -> ResolvedModifier? {
        for word in words {
            if case .comparative(let dir) = word.type {
                return mapComparative(dir)
            }
        }
        return nil
    }

    private func extractEvaluation(from words: [ClassifiedWord]) -> ResolvedModifier? {
        // "too much" / "too expensive" / "too high"
        let hasEvalToo = words.contains { w in
            if case .evaluative(.tooMuch) = w.type { return true }
            return w.word.lowercased() == "too"
        }

        if hasEvalToo {
            // Check what follows "too"
            if words.contains(where: { if case .evaluative(.expensive) = $0.type { return true }; return false }) ||
               words.contains(where: { if case .comparative(.higher) = $0.type { return true }; return false }) ||
               words.contains(where: { $0.word.lowercased() == "much" || $0.word.lowercased() == "high" }) {
                return .tooMuch
            }
            if words.contains(where: { $0.word.lowercased() == "little" || $0.word.lowercased() == "low" || $0.word.lowercased() == "small" }) {
                return .tooLittle
            }
            return .tooMuch // Default for bare "too"
        }

        // "enough" / "good enough" / "sufficient"
        if words.contains(where: { if case .evaluative(.enough) = $0.type { return true }; return false }) {
            return .enough
        }

        // "not enough"
        if words.contains(where: { $0.type == .negation }) &&
           words.contains(where: { if case .evaluative(.enough) = $0.type { return true }; return false }) {
            return .tooLittle
        }

        return nil
    }

    private func extractDirectional(from words: [ClassifiedWord]) -> NavigationDirection? {
        for word in words {
            if case .directional(let dir) = word.type { return dir }
        }
        return nil
    }

    private func extractAnyAction(from words: [ClassifiedWord]) -> ResolvedAction? {
        for word in words {
            if case .walletVerb(let action) = word.type { return mapWalletAction(action) }
        }
        for word in words {
            if case .generalVerb(.helpMe) = word.type { return .helpUser }
        }
        return nil
    }

    private func extractAnyObject(from words: [ClassifiedWord]) -> ResolvedObject? {
        for word in words {
            switch word.type {
            case .bitcoinNoun(let concept):
                return mapConceptToObject(concept)
            case .number(let decimal):
                return .amount(decimal)
            case .bitcoinAddress:
                return .address(word.word)
            case .txid:
                return .transaction(word.word)
            default:
                continue
            }
        }
        return nil
    }

    private func extractAnyModifier(from words: [ClassifiedWord]) -> ResolvedModifier? {
        // Check comparatives
        if let comp = extractComparative(from: words) { return comp }
        // Check quantifiers
        for word in words {
            if case .quantifier(let q) = word.type {
                switch q {
                case .all, .max: return .all
                case .half: return .half
                case .some, .few: return .some
                case .none, .min: return .none
                case .most: return .all
                }
            }
        }
        // Check evaluations
        return extractEvaluation(from: words)
    }

    // MARK: - Mapping Helpers

    private func mapWalletAction(_ action: WalletAction) -> ResolvedAction {
        switch action {
        case .send: return .send
        case .receive: return .receive
        case .check: return .checkBalance
        case .show: return .checkBalance
        case .hide: return .hide
        case .export: return .exportHistory
        case .bump: return .bumpFee
        case .refresh: return .refresh
        case .confirm: return .confirm
        case .cancel: return .cancel
        case .convert: return .convert
        case .detail: return .showDetail
        }
    }

    private func mapConceptToActionObject(_ concept: BitcoinConcept) -> (ResolvedAction, ResolvedObject) {
        switch concept {
        case .balance, .money, .amount: return (.checkBalance, .balance)
        case .fee: return (.showFees, .fee)
        case .address: return (.receive, .unspecified)
        case .transaction: return (.showHistory, .history)
        case .utxo: return (.utxoList, .utxo)
        case .price: return (.showPrice, .price)
        case .block, .network: return (.networkStatus, .network)
        case .wallet: return (.walletHealth, .wallet)
        case .history: return (.showHistory, .history)
        }
    }

    private func mapConceptToObject(_ concept: BitcoinConcept) -> ResolvedObject {
        switch concept {
        case .balance, .money, .amount: return .balance
        case .fee: return .fee
        case .address: return .unspecified
        case .transaction, .history: return .history
        case .utxo: return .utxo
        case .price: return .price
        case .block, .network: return .network
        case .wallet: return .wallet
        }
    }

    private func mapComparative(_ dir: ComparisonDirection) -> ResolvedModifier {
        switch dir {
        case .more, .higher, .better: return .increase
        case .less, .lower, .worse, .slower: return .decrease
        case .faster: return .fastest
        case .cheaper: return .cheapest
        }
    }

    private func objectToAction(_ obj: ResolvedObject) -> ResolvedAction {
        switch obj {
        case .balance, .money: return .checkBalance
        case .fee: return .showFees
        case .price: return .showPrice
        case .history: return .showHistory
        case .utxo: return .utxoList
        case .network: return .networkStatus
        case .wallet: return .walletHealth
        case .address: return .receive
        case .transaction: return .showDetail
        case .amount, .unspecified: return .checkBalance
        }
    }

    private func isEmotionOrStructure(_ word: ClassifiedWord) -> Bool {
        guard let type = word.type else { return true } // Unknown words are OK
        switch type {
        case .emotionWord, .article, .preposition, .conjunction, .pronoun:
            return true
        default:
            return false
        }
    }

    private func isActionWord(_ word: ClassifiedWord) -> Bool {
        guard let type = word.type else { return false }
        switch type {
        case .walletVerb, .generalVerb, .bitcoinNoun:
            return true
        default:
            return false
        }
    }
}
