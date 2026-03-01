// MARK: - SmartIntentClassifier.swift
// Bitcoin AI Wallet
//
// Hybrid intent classifier: Language Engine PRIMARY (≥0.7),
// PatternMatcher FALLBACK. Replaces IntentParser with a scored,
// meaning-aware classification system.
//
// Platform: iOS 17.0+

import Foundation

// MARK: - SmartIntentClassifier

final class SmartIntentClassifier {
    private let sentenceAnalyzer: SentenceAnalyzer
    private let meaningResolver: MeaningResolver
    private let patternMatcher: PatternMatcher
    private let entityExtractor: EntityExtractor
    private let referenceResolver: ReferenceResolver

    init(patternMatcher: PatternMatcher, entityExtractor: EntityExtractor, referenceResolver: ReferenceResolver) {
        self.sentenceAnalyzer = SentenceAnalyzer()
        self.meaningResolver = MeaningResolver()
        self.patternMatcher = patternMatcher
        self.entityExtractor = entityExtractor
        self.referenceResolver = referenceResolver
    }

    @MainActor
    func classify(_ input: String, memory: ConversationMemory) -> ClassificationResult {
        // Normalize smart quotes from iOS keyboard (U+2018/U+2019 → U+0027)
        let normalizedInput = input
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")

        // LAYER 1: Language Understanding (V18 — PRIMARY)
        let meaning = sentenceAnalyzer.analyze(normalizedInput, memory: memory)
        let languageResult = meaningResolver.resolve(meaning, memory: memory, entityExtractor: entityExtractor, input: normalizedInput)

        // LAYER 2: Pattern Matching (existing — BACKUP)
        let patternScores = patternMatcher.scoredMatch(normalizedInput.lowercased())
        let bestPattern = patternScores.max()

        // LAYER 3: Reference Resolution (V16)
        let refs = referenceResolver.resolve(normalizedInput, memory: memory)

        // ── Decision ──

        // LAYER 4 (early): Follow-up context detection runs BEFORE language engine
        // to catch "And EUR?", "What about pounds?", "In sats?", "Is that a lot?" etc.
        if let followUp = detectFollowUp(normalizedInput, meaning: meaning, memory: memory) {
            return followUp
        }

        // Language engine confident? Use it.
        if languageResult.confidence >= 0.7 { return languageResult }

        // Pattern matcher stronger? Use it but carry meaning.
        if let pattern = bestPattern, pattern.confidence > languageResult.confidence {
            return ClassificationResult(
                intent: pattern.intent,
                confidence: pattern.confidence,
                needsClarification: false,
                alternatives: [],
                meaning: meaning
            )
        }

        // References resolved? Boost.
        if !refs.isEmpty {
            return boostWithReferences(refs, base: languageResult, memory: memory, input: normalizedInput)
        }

        // Use whichever is more confident
        if languageResult.confidence > 0.3 { return languageResult }

        return ClassificationResult(
            intent: .unknown(rawText: normalizedInput),
            confidence: 0.2,
            needsClarification: true,
            alternatives: Array(patternScores.prefix(3)),
            meaning: meaning
        )
    }

    // MARK: - Follow-Up Detection

    /// Detects follow-up queries after price/balance: currencies, units, evaluative reactions.
    @MainActor
    private func detectFollowUp(_ input: String, meaning: SentenceMeaning, memory: ConversationMemory) -> ClassificationResult? {
        guard let lastIntent = memory.lastUserIntent else { return nil }

        let currencyMap: [String: String] = [
            "usd": "USD", "dollar": "USD", "dollars": "USD", "bucks": "USD",
            "eur": "EUR", "euro": "EUR", "euros": "EUR",
            "gbp": "GBP", "pound": "GBP", "pounds": "GBP", "quid": "GBP",
            "jpy": "JPY", "yen": "JPY", "japanese yen": "JPY",
            "cad": "CAD", "aud": "AUD", "chf": "CHF",
            "cny": "CNY", "yuan": "CNY",
            "krw": "KRW", "inr": "INR", "brl": "BRL",
            "mxn": "MXN", "sek": "SEK", "nok": "NOK",
        ]

        // Strip conjunction/preposition prefixes: "and EUR", "in GBP", "also EUR"
        var cleaned = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["and ", "in ", "also ", "plus ", "what about ", "how about ", "what about in ", "and in "] {
            if cleaned.hasPrefix(prefix) {
                cleaned = String(cleaned.dropFirst(prefix.count))
                break
            }
        }
        cleaned = cleaned.trimmingCharacters(in: .punctuationCharacters).trimmingCharacters(in: .whitespaces)

        // After price: follow-up currency or sats
        if case .price = lastIntent {
            if let currency = currencyMap[cleaned] {
                return ClassificationResult(
                    intent: .price(currency: currency),
                    confidence: 0.85,
                    needsClarification: false,
                    alternatives: [],
                    meaning: meaning
                )
            }
            // "in sats?" after price → sats conversion
            let satKeywords = ["sats", "sat", "satoshi", "satoshis"]
            if satKeywords.contains(cleaned) {
                return ClassificationResult(
                    intent: .price(currency: nil),
                    confidence: 0.85,
                    needsClarification: false,
                    alternatives: [],
                    meaning: meaning
                )
            }
        }

        // After balance: "How much is that in dollars?" / "And in sats?" / "And in euros?"
        if case .balance = lastIntent {
            // Sats/satoshis conversion
            let satKeywords = ["sats", "sat", "satoshi", "satoshis"]
            if satKeywords.contains(cleaned) {
                return ClassificationResult(
                    intent: .balance,
                    confidence: 0.85,
                    needsClarification: false,
                    alternatives: [],
                    meaning: meaning
                )
            }
            // Fiat conversion
            if let currency = currencyMap[cleaned] {
                return ClassificationResult(
                    intent: .price(currency: currency),
                    confidence: 0.85,
                    needsClarification: false,
                    alternatives: [],
                    meaning: meaning
                )
            }
            // "How much is that in dollars?" — detect currency words in full input
            let lower = input.lowercased()
            for (keyword, code) in currencyMap {
                if lower.contains(keyword) {
                    return ClassificationResult(
                        intent: .price(currency: code),
                        confidence: 0.8,
                        needsClarification: false,
                        alternatives: [],
                        meaning: meaning
                    )
                }
            }
        }

        // After balance: "Is that a lot?" / "Is that good?" → contextual balance question
        if case .balance = lastIntent {
            let lower = input.lowercased()
            let balanceFollowUps = ["is that a lot", "is that good", "is that enough",
                                    "is that much", "is that little", "is that ok",
                                    "can i send some", "can i send"]
            if balanceFollowUps.contains(where: { lower.contains($0) }) {
                // Return a meaning-driven response about the balance
                let evalMeaning = SentenceMeaning(
                    type: .question, action: .explain, subject: .user,
                    object: .balance, modifier: nil, emotion: nil,
                    isNegated: false, confidence: 0.85
                )
                return ClassificationResult(
                    intent: .balance,
                    confidence: 0.85,
                    needsClarification: false,
                    alternatives: [],
                    meaning: evalMeaning
                )
            }
        }

        // After price: "Convert 0.1 BTC" handled by language engine already.
        // After price: "Is it going up?" / "That's expensive" - let language engine handle.

        return nil
    }

    // MARK: - Reference Boosting

    @MainActor
    private func boostWithReferences(_ refs: [ResolvedEntity], base: ClassificationResult, memory: ConversationMemory, input: String) -> ClassificationResult {
        for ref in refs {
            switch ref {
            case .address(let addr):
                return ClassificationResult(
                    intent: .send(amount: nil, unit: nil, address: addr, feeLevel: nil),
                    confidence: 0.85,
                    needsClarification: false,
                    alternatives: base.alternatives,
                    meaning: base.meaning
                )
            case .amount(let amt, let unit):
                return ClassificationResult(
                    intent: .send(amount: amt, unit: unit, address: nil, feeLevel: nil),
                    confidence: 0.85,
                    needsClarification: false,
                    alternatives: base.alternatives,
                    meaning: base.meaning
                )
            default:
                break
            }
        }
        return base
    }
}
