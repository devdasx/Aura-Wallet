// MARK: - MultiIntentHandler.swift
// Bitcoin AI Wallet
//
// Splits compound user messages into multiple intents.
// "Check balance and show fees" → [balance, feeEstimate]
// Only splits when BOTH parts contain recognizable wallet keywords.
//
// Handles:
// - Connector-based splitting ("and then", "also", "plus", etc.)
// - Sentence-boundary splitting ("balance? What's the price?")
// - Action-intent prioritization (send/receive flows suppress secondary intents)
// - Conflict detection (cannot send AND receive simultaneously)
// - Punctuation-tolerant keyword matching
//
// Platform: iOS 17.0+
// Framework: Foundation

import Foundation

// MARK: - MultiIntentHandler

final class MultiIntentHandler {

    // MARK: - Public API

    /// Splits a compound sentence into separate parts if both halves
    /// contain wallet-related keywords, then applies prioritization rules.
    ///
    /// Prioritization:
    /// - Action intents (send, receive, bumpFee) take precedence over informational ones
    /// - Conflicting flows are reduced to the first action intent
    /// - Single-intent messages pass through with no overhead
    func splitIfCompound(_ input: String) -> [String] {
        // Fast path: if there's only one keyword, no split is possible.
        if countWalletKeywords(input) <= 1 {
            return [input]
        }

        var parts = [input]

        // Phase 1: Split on explicit connectors
        parts = splitOnConnectors(parts)

        // Phase 2: Split on sentence boundaries (". " and "? ") when both
        // sentences contain wallet keywords
        parts = splitOnSentenceBoundaries(parts)

        // Clean up: trim whitespace and leading/trailing punctuation
        parts = parts
            .map { cleanPart($0) }
            .filter { !$0.isEmpty }

        // Phase 3: Prioritize action intents and resolve conflicts
        parts = prioritize(parts)

        return parts
    }

    // MARK: - Connector Splitting

    private let connectors = [
        " and then ", " and also ", " then ", " also ",
        " plus ", " and check ", " and show ", " and get ",
    ]

    private func splitOnConnectors(_ parts: [String]) -> [String] {
        var result = parts
        for conn in connectors {
            result = result.flatMap { segment -> [String] in
                let lower = segment.lowercased()
                guard let range = lower.range(of: conn) else { return [segment] }

                let beforeEnd = lower.distance(from: lower.startIndex, to: range.lowerBound)
                let afterStart = lower.distance(from: lower.startIndex, to: range.upperBound)

                let before = String(segment.prefix(beforeEnd))
                let after = String(segment.suffix(segment.count - afterStart))

                if containsWalletKeyword(before) && containsWalletKeyword(after) {
                    return [before, after]
                }
                return [segment]
            }
        }
        return result
    }

    // MARK: - Sentence Boundary Splitting

    /// Splits on sentence boundaries (". " or "? ") when both resulting
    /// parts contain wallet keywords.
    private func splitOnSentenceBoundaries(_ parts: [String]) -> [String] {
        parts.flatMap { segment -> [String] in
            splitOnBoundary(segment)
        }
    }

    private func splitOnBoundary(_ text: String) -> [String] {
        // Try splitting at ". " or "? " boundaries
        let sentenceEnders: [String] = [". ", "? "]

        for ender in sentenceEnders {
            let lower = text.lowercased()
            guard let range = lower.range(of: ender) else { continue }

            let beforeEnd = lower.distance(from: lower.startIndex, to: range.lowerBound)
            // Include the punctuation in the first part for natural reading
            let afterStart = lower.distance(from: lower.startIndex, to: range.upperBound)

            let before = String(text.prefix(beforeEnd + 1)) // include . or ?
            let after = String(text.suffix(text.count - afterStart))

            if containsWalletKeyword(before) && containsWalletKeyword(after) {
                // Recursively try to split the remainder
                return [before] + splitOnBoundary(after)
            }
        }

        return [text]
    }

    // MARK: - Prioritization

    /// Action intents that represent multi-step flows.
    private let actionKeywords: Set<String> = [
        "send", "enviar", "ارسل",
        "receive", "recibir",
    ]

    /// Keywords that conflict with each other (cannot run simultaneously).
    private let conflictGroups: [[String]] = [
        ["send", "enviar", "ارسل", "receive", "recibir"],
    ]

    /// Prioritizes action intents over informational ones.
    ///
    /// Rules:
    /// 1. If any part contains an action keyword (send, receive), only that
    ///    part is returned -- action flows need full user attention.
    /// 2. If multiple conflicting action intents are found (send AND receive),
    ///    only the first one is kept.
    /// 3. Purely informational multi-intents (balance + price) pass through
    ///    unchanged.
    private func prioritize(_ parts: [String]) -> [String] {
        guard parts.count > 1 else { return parts }

        // Identify which parts contain action keywords
        var actionParts: [String] = []
        var infoParts: [String] = []

        for part in parts {
            if containsActionKeyword(part) {
                actionParts.append(part)
            } else {
                infoParts.append(part)
            }
        }

        // If no action intents, return all informational parts
        if actionParts.isEmpty {
            return infoParts
        }

        // Resolve conflicts among action parts: keep only the first action
        // to avoid conflicting flows (e.g., can't send AND receive)
        let resolvedAction = resolveConflicts(actionParts)

        // Action intents suppress informational ones -- the user should
        // focus on the flow. Return only the action part(s).
        return resolvedAction
    }

    /// Keeps only the first action intent if multiple conflict with each other.
    private func resolveConflicts(_ actionParts: [String]) -> [String] {
        guard actionParts.count > 1 else { return actionParts }

        // Check if any two parts belong to the same conflict group
        var seenGroups: Set<Int> = []
        var result: [String] = []

        for part in actionParts {
            let lower = part.lowercased()
            let words = Set(lower.split(separator: " ").map { stripPunctuation(String($0)) })
            var partGroupIndex: Int?

            for (groupIndex, group) in conflictGroups.enumerated() {
                if !words.isDisjoint(with: Set(group)) {
                    partGroupIndex = groupIndex
                    break
                }
            }

            if let idx = partGroupIndex {
                if seenGroups.contains(idx) {
                    // Conflict: skip this part (keep only the first)
                    continue
                }
                seenGroups.insert(idx)
            }
            result.append(part)
        }

        return result
    }

    // MARK: - Keyword Matching

    private let walletKeywords: Set<String> = [
        "balance", "send", "receive", "fee", "fees", "price", "history",
        "transactions", "utxo", "address", "health", "network", "export",
        "help", "settings", "refresh", "hide", "show", "convert",
        "bitcoin", "btc", "sats", "satoshis",
        "saldo", "enviar", "recibir", "رصيد", "ارسل",
    ]

    /// Checks whether the text contains at least one recognized wallet keyword.
    /// Strips punctuation from individual words before matching.
    private func containsWalletKeyword(_ text: String) -> Bool {
        let lower = text.lowercased()
        let words = Set(lower.split(separator: " ").map { stripPunctuation(String($0)) })
        return !words.isDisjoint(with: walletKeywords)
    }

    /// Checks whether the text contains an action keyword.
    private func containsActionKeyword(_ text: String) -> Bool {
        let lower = text.lowercased()
        let words = Set(lower.split(separator: " ").map { stripPunctuation(String($0)) })
        return !words.isDisjoint(with: actionKeywords)
    }

    /// Counts how many distinct wallet keywords appear in the text.
    /// Used as a fast pre-check to avoid unnecessary splitting logic.
    private func countWalletKeywords(_ text: String) -> Int {
        let lower = text.lowercased()
        let words = Set(lower.split(separator: " ").map { stripPunctuation(String($0)) })
        return words.intersection(walletKeywords).count
    }

    // MARK: - Text Cleaning

    /// Strips leading/trailing punctuation from a word for keyword matching.
    private func stripPunctuation(_ word: String) -> String {
        word.trimmingCharacters(in: .punctuationCharacters)
    }

    /// Cleans a split part by trimming whitespace and leading punctuation/conjunctions.
    private func cleanPart(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip leading punctuation and whitespace (e.g., ", what's the price")
        while let first = result.first, first.isPunctuation || first == " " {
            result = String(result.dropFirst())
        }
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }
}
