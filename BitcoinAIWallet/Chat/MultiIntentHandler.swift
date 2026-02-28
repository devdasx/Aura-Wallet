// MARK: - MultiIntentHandler.swift
// Bitcoin AI Wallet
//
// Splits compound user messages into multiple intents.
// "Check balance and show fees" → [balance, feeEstimate]
// Only splits when BOTH parts contain recognizable wallet keywords.
//
// Platform: iOS 17.0+
// Framework: Foundation

import Foundation

// MARK: - MultiIntentHandler

final class MultiIntentHandler {

    private let patternMatcher: PatternMatcher

    init(patternMatcher: PatternMatcher = PatternMatcher()) {
        self.patternMatcher = patternMatcher
    }

    // MARK: - Public API

    /// Splits a compound sentence into separate parts if both halves
    /// contain wallet-related keywords.
    func splitIfCompound(_ input: String) -> [String] {
        let connectors = [
            " and then ", " and also ", " then ", " also ",
            " plus ", " and check ", " and show ",
        ]

        var parts = [input]
        for conn in connectors {
            parts = parts.flatMap { segment -> [String] in
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

        return parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Private

    private let walletKeywords: Set<String> = [
        "balance", "send", "receive", "fee", "fees", "price", "history",
        "transactions", "utxo", "address", "health", "network", "export",
        "help", "settings", "refresh", "hide", "show", "convert",
        "saldo", "enviar", "recibir", "رصيد", "ارسل",
    ]

    private func containsWalletKeyword(_ text: String) -> Bool {
        let lower = text.lowercased()
        let words = Set(lower.split(separator: " ").map { String($0) })
        return !words.isDisjoint(with: walletKeywords)
    }
}
