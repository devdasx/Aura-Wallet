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
        // LAYER 1: Language Understanding (V18 — PRIMARY)
        let meaning = sentenceAnalyzer.analyze(input, memory: memory)
        let languageResult = meaningResolver.resolve(meaning, memory: memory, entityExtractor: entityExtractor, input: input)

        // LAYER 2: Pattern Matching (existing — BACKUP)
        let patternScores = patternMatcher.scoredMatch(input.lowercased())
        let bestPattern = patternScores.max()

        // LAYER 3: Reference Resolution (V16)
        let refs = referenceResolver.resolve(input, memory: memory)

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
            return boostWithReferences(refs, base: languageResult, memory: memory, input: input)
        }

        // Use whichever is more confident
        if languageResult.confidence > 0.3 { return languageResult }

        return ClassificationResult(
            intent: .unknown(rawText: input),
            confidence: 0.2,
            needsClarification: true,
            alternatives: Array(patternScores.prefix(3)),
            meaning: meaning
        )
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
