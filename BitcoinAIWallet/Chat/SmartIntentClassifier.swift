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

        // LAYER 4: Follow-up detection (e.g., "And EUR" after price query)
        if let followUp = detectFollowUpCurrency(normalizedInput, meaning: meaning, memory: memory) {
            return followUp
        }

        return ClassificationResult(
            intent: .unknown(rawText: normalizedInput),
            confidence: 0.2,
            needsClarification: true,
            alternatives: Array(patternScores.prefix(3)),
            meaning: meaning
        )
    }

    // MARK: - Follow-Up Currency Detection

    /// Detects follow-up currency queries like "And EUR", "EUR?", "in GBP" after a price intent.
    @MainActor
    private func detectFollowUpCurrency(_ input: String, meaning: SentenceMeaning, memory: ConversationMemory) -> ClassificationResult? {
        guard let lastIntent = memory.lastUserIntent else { return nil }
        guard case .price = lastIntent else { return nil }

        let currencyMap: [String: String] = [
            "usd": "USD", "dollar": "USD", "dollars": "USD", "bucks": "USD",
            "eur": "EUR", "euro": "EUR", "euros": "EUR",
            "gbp": "GBP", "pound": "GBP", "pounds": "GBP", "quid": "GBP",
            "jpy": "JPY", "yen": "JPY",
            "cad": "CAD", "aud": "AUD", "chf": "CHF",
            "cny": "CNY", "yuan": "CNY",
            "krw": "KRW", "inr": "INR", "brl": "BRL",
            "mxn": "MXN", "sek": "SEK", "nok": "NOK",
        ]

        // Strip conjunction/preposition prefixes: "and EUR", "in GBP", "also EUR"
        var cleaned = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["and ", "in ", "also ", "plus ", "what about ", "how about "] {
            if cleaned.hasPrefix(prefix) {
                cleaned = String(cleaned.dropFirst(prefix.count))
                break
            }
        }
        cleaned = cleaned.trimmingCharacters(in: .punctuationCharacters).trimmingCharacters(in: .whitespaces)

        if let currency = currencyMap[cleaned] {
            return ClassificationResult(
                intent: .price(currency: currency),
                confidence: 0.85,
                needsClarification: false,
                alternatives: [],
                meaning: meaning
            )
        }

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
