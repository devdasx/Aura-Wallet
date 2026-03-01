// MARK: - IntentParser.swift
// Bitcoin AI Wallet
//
// Hybrid intent classifier with two layers:
//
// PRIMARY: Language Engine (WordClassifier → SentenceAnalyzer → MeaningResolver)
//   - Classifies words by grammatical category, analyzes sentence structure,
//     resolves meaning to WalletIntent. Confidence ≥ 0.7 wins.
//
// FALLBACK: Pattern Matcher (7 signal sources)
//   1. Keyword matching (PatternMatcher — existing keyword lists)
//   2. Entity presence (address → send, txid → transaction detail)
//   3. Conversation context (flow state, what was last discussed)
//   4. Reference resolution (memory-resolved entities boost matching intent)
//   5. Semantic verb mapping (synonyms, sentence structure)
//   6. Social/meta detection (thanks, complaints, emoji)
//   7. Negation detection (reduces confidence of action intents)
//
// Language Engine PRIMARY (≥0.7), PatternMatcher FALLBACK.
// Context (0.95) beats Language (0.7+) beats keywords (0.6).
//
// Platform: iOS 17.0+
// Framework: Foundation

import Foundation

// MARK: - PunctuationContext

struct PunctuationContext {
    let isQuestion: Bool
    let isExclamation: Bool
    let isEllipsis: Bool
    let isHesitant: Bool
    let hasComma: Bool
    let isPurePunctuation: Bool
    let sentimentModifier: Double // -0.3 to +0.3

    static func analyze(_ text: String) -> PunctuationContext {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let lower = trimmed.lowercased()

        let isQuestion = trimmed.hasSuffix("?")
        let isExclamation = trimmed.hasSuffix("!")
        let isEllipsis = trimmed.hasSuffix("...") || trimmed.hasSuffix("..") || trimmed.contains("\u{2026}")
        let isHesitant = lower.hasPrefix("hmm") || lower.hasPrefix("um ") || lower.hasPrefix("uh ") || lower.hasPrefix("well ")
        let hasComma = trimmed.contains(",")
        let isPure = !trimmed.isEmpty && trimmed.allSatisfy { "?!.,\u{2026}  ".contains($0) }

        var modifier: Double = 0
        if isQuestion { modifier += 0.1 }
        if isExclamation { modifier += 0.15 }
        if isEllipsis { modifier -= 0.2 }
        if isHesitant { modifier -= 0.15 }

        return PunctuationContext(
            isQuestion: isQuestion, isExclamation: isExclamation,
            isEllipsis: isEllipsis, isHesitant: isHesitant,
            hasComma: hasComma, isPurePunctuation: isPure,
            sentimentModifier: modifier
        )
    }
}

// MARK: - IntentParser (SmartIntentClassifier)

/// Scored intent classifier. Replaces the old waterfall parser.
/// Each message is classified using 7 signal sources, and the highest-confidence
/// intent wins. If confidence is below 0.5, the result is flagged for clarification.
final class IntentParser {

    // MARK: - Dependencies

    private let patternMatcher: PatternMatcher
    private let entityExtractor: EntityExtractor
    private let addressValidator: AddressValidator
    private let currencyParser: CurrencyParser

    // Language Engine (V18)
    private let wordClassifier: WordClassifier
    private let sentenceAnalyzer: SentenceAnalyzer
    private let meaningResolver: MeaningResolver

    // MARK: - Initialization

    init() {
        self.patternMatcher = PatternMatcher()
        self.entityExtractor = EntityExtractor()
        self.addressValidator = AddressValidator()
        self.currencyParser = CurrencyParser()
        self.wordClassifier = WordClassifier()
        self.sentenceAnalyzer = SentenceAnalyzer()
        self.meaningResolver = MeaningResolver()
    }

    init(patternMatcher: PatternMatcher, entityExtractor: EntityExtractor, addressValidator: AddressValidator) {
        self.patternMatcher = patternMatcher
        self.entityExtractor = entityExtractor
        self.addressValidator = addressValidator
        self.currencyParser = CurrencyParser()
        self.wordClassifier = WordClassifier()
        self.sentenceAnalyzer = SentenceAnalyzer()
        self.meaningResolver = MeaningResolver()
    }

    // MARK: - Legacy API (backward compatible)

    /// Simple parse without memory context. Falls back to keyword-only classification.
    func parse(_ input: String) -> WalletIntent {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unknown(rawText: input) }

        let normalized = trimmed.lowercased()
        let entities = entityExtractor.extract(from: trimmed)

        // SIGNAL 1: Keyword scores
        var allScores = patternMatcher.scoredMatch(normalized)

        // SIGNAL 2: Entity presence
        allScores += entityPresenceScores(entities, input: trimmed)

        // SIGNAL 5: Semantic scores
        allScores += semanticScores(normalized)

        // SIGNAL 6: Social scores
        allScores += socialScores(normalized)

        // SIGNAL 7: Negation penalty
        allScores = applyNegationPenalty(normalized, scores: allScores)

        // Check for fiat conversion (special case)
        if let fiat = currencyParser.parseFiatAmount(from: trimmed) {
            allScores.append(IntentScore(
                intent: .convertAmount(amount: fiat.amount, fromCurrency: fiat.currencyCode),
                confidence: SignalWeight.entityPresence,
                source: "entity_fiat"
            ))
        }

        // Bare txid detection
        if let txid = entityExtractor.extractTxId(from: trimmed) {
            allScores.append(IntentScore(
                intent: .transactionDetail(txid: txid),
                confidence: SignalWeight.entityPresence,
                source: "entity_txid"
            ))
        }

        // Merge and pick best
        let merged = mergeScores(allScores)
        guard let best = merged.first else {
            return .unknown(rawText: input)
        }

        // For send intents, enrich with extracted entities
        if case .send = best.intent {
            return buildSendIntent(from: trimmed)
        }

        // For history, include count
        if case .history = best.intent {
            let count = entityExtractor.extractCount(from: normalized)
            return .history(count: count)
        }

        // For bump fee, include txid
        if case .bumpFee = best.intent {
            let txid = entityExtractor.extractTxId(from: trimmed)
            return .bumpFee(txid: txid)
        }

        // For price, include currency
        if case .price = best.intent {
            let currency = extractCurrencyCode(from: normalized)
            return .price(currency: currency)
        }

        return best.intent
    }

    // MARK: - Smart Classification API (with memory)

    /// Classifies user input using Language Engine (primary) + PatternMatcher (fallback).
    /// Language confidence ≥ 0.7 wins. Below 0.7, PatternMatcher is checked.
    /// Context signals (flow state) always override both at 0.95.
    @MainActor
    func classify(_ input: String, memory: ConversationMemory, references: [ResolvedEntity] = []) -> ClassificationResult {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ClassificationResult(intent: .unknown(rawText: input), confidence: 0, needsClarification: true, alternatives: [])
        }

        let normalized = trimmed.lowercased()
        let entities = entityExtractor.extract(from: trimmed)

        // SIGNAL 8: Punctuation intelligence (check early)
        let punctuation = PunctuationContext.analyze(input)

        // Pure punctuation (e.g. "...") → unknown with low confidence
        if punctuation.isPurePunctuation {
            return ClassificationResult(
                intent: .unknown(rawText: input),
                confidence: 0.1,
                needsClarification: true,
                alternatives: []
            )
        }

        // PRIORITY 0: Context signals (flow state) — highest priority (0.95)
        let contextResults = contextScores(normalized, entities: entities, memory: memory)
        if let topContext = contextResults.max(by: { $0.confidence < $1.confidence }),
           topContext.confidence >= 0.9 {
            let resolved = resolveIntentDetails(topContext.intent, input: trimmed, normalized: normalized)
            return ClassificationResult(
                intent: resolved,
                confidence: topContext.confidence,
                needsClarification: false,
                alternatives: []
            )
        }

        // PRIORITY 1: Entity-based detection (address, txid, fiat)
        // These are high-signal: a Bitcoin address in the input almost certainly means send
        if let entityResult = entityBasedClassification(entities, input: trimmed, normalized: normalized) {
            return entityResult
        }

        // PRIORITY 2: Language Engine (PRIMARY)
        let classifiedWords = wordClassifier.classify(trimmed)
        let meaning = sentenceAnalyzer.analyze(classifiedWords)
        let languageResult = meaningResolver.resolve(meaning, memory: memory)

        // PRIORITY 3: PatternMatcher (FALLBACK)
        let patternResult = patternMatcherClassification(normalized, entities: entities,
                                                          memory: memory, references: references,
                                                          input: trimmed)

        // Decision: Language ≥ 0.7 wins. Otherwise, use best of both.
        var bestResult: ClassificationResult

        if languageResult.confidence >= 0.7 {
            bestResult = languageResult
        } else if patternResult.confidence > languageResult.confidence {
            bestResult = patternResult
        } else {
            bestResult = languageResult
        }

        // Apply punctuation adjustments
        var adjustedConfidence = bestResult.confidence

        if punctuation.isQuestion {
            switch bestResult.intent {
            case .send, .confirmAction:
                adjustedConfidence -= 0.2
            default:
                break
            }
        }

        if punctuation.isEllipsis {
            adjustedConfidence -= 0.2
        }

        adjustedConfidence += punctuation.sentimentModifier
        adjustedConfidence = min(max(adjustedConfidence, 0), 1.0)

        // Resolve the final intent with entity details (enrich send/history/price/bumpFee)
        let resolvedIntent = resolveIntentDetails(bestResult.intent, input: trimmed, normalized: normalized)

        return ClassificationResult(
            intent: resolvedIntent,
            confidence: adjustedConfidence,
            needsClarification: adjustedConfidence < 0.5,
            alternatives: bestResult.alternatives
        )
    }

    // MARK: - Entity-Based Classification

    /// High-signal entity detection: addresses, txids, fiat amounts.
    private func entityBasedClassification(_ entities: ParsedEntity, input: String, normalized: String) -> ClassificationResult? {
        // Address found → send
        if let addr = entities.address, addressValidator.isValid(addr) {
            let intent = buildSendIntent(from: input)
            return ClassificationResult(intent: intent, confidence: SignalWeight.entityPresence,
                                        needsClarification: false, alternatives: [])
        }

        // Bare txid
        if let txid = entityExtractor.extractTxId(from: input) {
            return ClassificationResult(intent: .transactionDetail(txid: txid),
                                        confidence: SignalWeight.entityPresence,
                                        needsClarification: false, alternatives: [])
        }

        // Fiat conversion
        if let fiat = currencyParser.parseFiatAmount(from: input) {
            return ClassificationResult(
                intent: .convertAmount(amount: fiat.amount, fromCurrency: fiat.currencyCode),
                confidence: SignalWeight.entityPresence,
                needsClarification: false, alternatives: [])
        }

        return nil
    }

    // MARK: - PatternMatcher Classification (Fallback)

    /// Runs the original 7-signal classification pipeline.
    @MainActor
    private func patternMatcherClassification(_ normalized: String, entities: ParsedEntity,
                                               memory: ConversationMemory, references: [ResolvedEntity],
                                               input: String) -> ClassificationResult {
        var allScores: [IntentScore] = []

        // SIGNAL 1: Keyword matching
        allScores += patternMatcher.scoredMatch(normalized)

        // SIGNAL 2: Entity presence
        allScores += entityPresenceScores(entities, input: input)

        // SIGNAL 3: Conversation context
        allScores += contextScores(normalized, entities: entities, memory: memory)

        // SIGNAL 4: Reference resolution
        allScores += referenceScores(references, memory: memory)

        // SIGNAL 5: Semantic verb mapping
        allScores += semanticScores(normalized)

        // SIGNAL 6: Social/meta detection
        allScores += socialScores(normalized)

        // SIGNAL 7: Negation detection
        allScores = applyNegationPenalty(normalized, scores: allScores)

        let merged = mergeScores(allScores)

        guard let best = merged.first else {
            return ClassificationResult(
                intent: .unknown(rawText: input),
                confidence: 0,
                needsClarification: true,
                alternatives: []
            )
        }

        return ClassificationResult(
            intent: best.intent,
            confidence: best.confidence,
            needsClarification: best.confidence < 0.5,
            alternatives: Array(merged.prefix(3))
        )
    }

    // MARK: - Signal 2: Entity Presence

    private func entityPresenceScores(_ entities: ParsedEntity, input: String) -> [IntentScore] {
        var scores: [IntentScore] = []

        // Address found → likely send
        if let addr = entities.address, addressValidator.isValid(addr) {
            scores.append(IntentScore(
                intent: .send(amount: entities.amount, unit: entities.unit, address: addr, feeLevel: entities.feeLevel),
                confidence: SignalWeight.entityPresence,
                source: "entity_address"
            ))
        }

        return scores
    }

    // MARK: - Signal 3: Conversation Context

    @MainActor
    private func contextScores(_ text: String, entities: ParsedEntity, memory: ConversationMemory) -> [IntentScore] {
        var scores: [IntentScore] = []

        // In awaitingAddress + message has address → send flow (very high confidence)
        if case .awaitingAddress = memory.currentFlowState, entities.address != nil {
            scores.append(IntentScore(
                intent: .send(amount: nil, unit: nil, address: entities.address, feeLevel: nil),
                confidence: SignalWeight.context,
                source: "context_flow_address"
            ))
        }

        // In awaitingAmount + message has number → it's the amount
        if case .awaitingAmount = memory.currentFlowState, entities.amount != nil {
            scores.append(IntentScore(
                intent: .send(amount: entities.amount, unit: entities.unit, address: nil, feeLevel: nil),
                confidence: SignalWeight.context,
                source: "context_flow_amount"
            ))
        }

        // In awaitingAmount + bare number → it's the amount
        if case .awaitingAmount = memory.currentFlowState {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if let _ = Decimal(string: trimmed) {
                scores.append(IntentScore(
                    intent: .send(amount: nil, unit: nil, address: nil, feeLevel: nil),
                    confidence: SignalWeight.context,
                    source: "context_bare_number"
                ))
            }
        }

        // Just saw fees + follow-up question → fee follow-up
        if let lastIntent = memory.lastUserIntent, lastIntent == .feeEstimate {
            let followUps = ["enough", "fast enough", "good enough", "too slow", "too high",
                             "reasonable", "will it", "is that", "ok?"]
            if followUps.contains(where: { text.contains($0) }) {
                scores.append(IntentScore(
                    intent: .feeEstimate,
                    confidence: 0.8,
                    source: "context_followup"
                ))
            }
        }

        // Just completed send + asking about balance → definitely balance
        if memory.lastSentTx != nil && memory.turnsSinceLastSend() < 4 {
            let balanceIndicators = ["balance", "left", "remaining", "have now", "how much"]
            if balanceIndicators.contains(where: { text.contains($0) }) {
                scores.append(IntentScore(
                    intent: .balance,
                    confidence: 0.9,
                    source: "context_post_send"
                ))
            }
        }

        // After showing history + "the second one" → transaction detail
        if memory.lastShownTransactions != nil {
            let detailIndicators = ["details", "more about", "tell me about", "show me"]
            if detailIndicators.contains(where: { text.contains($0) }) {
                scores.append(IntentScore(
                    intent: .history(count: nil),
                    confidence: 0.7,
                    source: "context_history_followup"
                ))
            }
        }

        return scores
    }

    // MARK: - Signal 4: Reference Scores

    @MainActor
    private func referenceScores(_ refs: [ResolvedEntity], memory: ConversationMemory) -> [IntentScore] {
        var scores: [IntentScore] = []

        for ref in refs {
            switch ref {
            case .address:
                scores.append(IntentScore(
                    intent: .send(amount: nil, unit: nil, address: nil, feeLevel: nil),
                    confidence: SignalWeight.reference,
                    source: "ref_address"
                ))
            case .amount:
                scores.append(IntentScore(
                    intent: .send(amount: nil, unit: nil, address: nil, feeLevel: nil),
                    confidence: SignalWeight.reference,
                    source: "ref_amount"
                ))
            case .intent(let intent):
                scores.append(IntentScore(
                    intent: intent,
                    confidence: SignalWeight.reference,
                    source: "ref_repeat"
                ))
            case .transaction(let tx):
                scores.append(IntentScore(
                    intent: .transactionDetail(txid: tx.txid),
                    confidence: SignalWeight.reference,
                    source: "ref_ordinal"
                ))
            }
        }

        return scores
    }

    // MARK: - Signal 5: Semantic Scores

    private func semanticScores(_ text: String) -> [IntentScore] {
        var scores: [IntentScore] = []

        // "show me my money" → balance
        let showMoneyPatterns = ["show me my money", "my money", "my coins", "my btc",
                                  "show me my", "how much money", "my wallet"]
        if showMoneyPatterns.contains(where: { text.contains($0) }) {
            scores.append(IntentScore(intent: .balance, confidence: SignalWeight.semantic, source: "semantic"))
        }

        // "what's the going rate" → price
        let ratePatterns = ["going rate", "exchange rate", "market rate", "what is bitcoin worth",
                            "how much is bitcoin worth", "how much is one bitcoin"]
        if ratePatterns.contains(where: { text.contains($0) }) {
            scores.append(IntentScore(intent: .price(currency: nil), confidence: SignalWeight.semantic, source: "semantic"))
        }

        // "is the network busy" → fee or network
        if text.contains("network busy") || text.contains("congested") || text.contains("congestion") {
            scores.append(IntentScore(intent: .feeEstimate, confidence: SignalWeight.semantic, source: "semantic"))
        }

        // "how much was" → could be history or balance context
        if text.contains("how much was") || text.contains("how much did i") {
            scores.append(IntentScore(intent: .history(count: nil), confidence: SignalWeight.semantic, source: "semantic"))
        }

        return scores
    }

    // MARK: - Signal 6: Social Scores

    private func socialScores(_ text: String) -> [IntentScore] {
        var scores: [IntentScore] = []

        if patternMatcher.isSocialPositive(text) {
            scores.append(IntentScore(intent: .greeting, confidence: SignalWeight.social, source: "social_positive"))
        }

        if patternMatcher.isSocialNegative(text) {
            scores.append(IntentScore(intent: .help, confidence: SignalWeight.semantic, source: "social_negative"))
        }

        // Emoji-only or very short
        if text.count <= 3 {
            if text == "lol" || text == "haha" || text == "😂" || text == "😊" || text == "🙏" {
                scores.append(IntentScore(intent: .greeting, confidence: 0.4, source: "social_emoji"))
            }
        }

        return scores
    }

    // MARK: - Signal 7: Negation Penalty

    private func applyNegationPenalty(_ text: String, scores: [IntentScore]) -> [IntentScore] {
        guard patternMatcher.containsNegation(text) else { return scores }

        return scores.map { score in
            switch score.intent {
            case .send, .confirmAction:
                return IntentScore(
                    intent: score.intent,
                    confidence: score.confidence * SignalWeight.negation,
                    source: score.source + "_negated"
                )
            default:
                return score
            }
        }
    }

    // MARK: - Score Merging

    /// Merges scores for each unique intent type. Uses weighted average of top 2 signals.
    private func mergeScores(_ scores: [IntentScore]) -> [IntentScore] {
        guard !scores.isEmpty else { return [] }

        let grouped = Dictionary(grouping: scores) { $0.intent.intentKey }
        let merged: [IntentScore] = grouped.compactMap { (_, group) in
            let sorted = group.sorted(by: { $0.confidence > $1.confidence })
            if sorted.count >= 2 {
                // 70% from top signal, 30% from second
                let combined = sorted[0].confidence * 0.7 + sorted[1].confidence * 0.3
                return IntentScore(intent: sorted[0].intent, confidence: min(combined, 1.0), source: "merged")
            }
            return sorted.first
        }

        return merged.sorted(by: { $0.confidence > $1.confidence })
    }

    // MARK: - Intent Detail Resolution

    /// Enriches a generic intent match with extracted entity details.
    private func resolveIntentDetails(_ intent: WalletIntent, input: String, normalized: String) -> WalletIntent {
        switch intent {
        case .send:
            return buildSendIntent(from: input)
        case .history:
            let count = entityExtractor.extractCount(from: normalized)
            return .history(count: count)
        case .bumpFee:
            let txid = entityExtractor.extractTxId(from: input)
            return .bumpFee(txid: txid)
        case .price:
            let currency = extractCurrencyCode(from: normalized)
            return .price(currency: currency)
        default:
            return intent
        }
    }

    // MARK: - Private Helpers

    private func buildSendIntent(from originalInput: String) -> WalletIntent {
        let entities = entityExtractor.extract(from: originalInput)
        let validatedAddress: String?
        if let address = entities.address {
            validatedAddress = addressValidator.isValid(address) ? address : nil
        } else {
            validatedAddress = nil
        }
        return .send(
            amount: entities.amount,
            unit: entities.unit,
            address: validatedAddress,
            feeLevel: entities.feeLevel
        )
    }

    private func extractCurrencyCode(from text: String) -> String? {
        let codePattern = try? NSRegularExpression(
            pattern: #"\bin\s+([A-Z]{3})\b"#,
            options: [.caseInsensitive]
        )
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        if let match = codePattern?.firstMatch(in: text, options: [], range: range),
           match.range(at: 1).location != NSNotFound {
            let code = nsText.substring(with: match.range(at: 1)).uppercased()
            if CurrencyParser.supportedCurrencyCodes.contains(code) { return code }
        }
        return nil
    }
}
