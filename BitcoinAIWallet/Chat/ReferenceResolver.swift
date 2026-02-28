// MARK: - ReferenceResolver.swift
// Bitcoin AI Wallet
//
// Resolves natural language references from conversation memory:
// "same address", "that amount", "the second one", "double",
// "actually make it 0.05", "do it again", etc.
//
// Platform: iOS 17.0+
// Framework: Foundation

import Foundation

// MARK: - ReferenceResolver

@MainActor
final class ReferenceResolver {

    private let entityExtractor: EntityExtractor

    init(entityExtractor: EntityExtractor = EntityExtractor()) {
        self.entityExtractor = entityExtractor
    }

    // MARK: - Public API

    /// Resolves all natural language references in the input using conversation memory.
    func resolve(_ input: String, memory: ConversationMemory) -> [ResolvedEntity] {
        let lower = input.lowercased()
        var resolved: [ResolvedEntity] = []

        // Address references
        if let addr = resolveAddressReference(lower, memory: memory) {
            resolved.append(.address(addr))
        }

        // Amount references
        if let (amt, unit) = resolveAmountReference(lower, memory: memory) {
            resolved.append(.amount(amt, unit))
        }

        // Repeat/again references
        if let intent = resolveRepeatReference(lower, memory: memory) {
            resolved.append(.intent(intent))
        }

        // Ordinal references ("the second one", "first transaction", "#3")
        if let tx = resolveOrdinalReference(lower, memory: memory) {
            resolved.append(.transaction(tx))
        }

        // Mid-flow modification ("actually make it 0.05", "change to bc1q...")
        let mods = resolveModification(input, lower: lower, memory: memory)
        resolved.append(contentsOf: mods)

        return resolved
    }

    /// Enriches user input text with resolved entity values.
    /// If the user said "same address" but the text has no actual address,
    /// the resolved address is appended so the classifier can extract it.
    func enrichWithReferences(_ input: String, _ refs: [ResolvedEntity]) -> String {
        var enriched = input
        for ref in refs {
            switch ref {
            case .address(let addr):
                if entityExtractor.extractAddress(from: input) == nil {
                    enriched += " \(addr)"
                }
            case .amount(let amt, let unit):
                if entityExtractor.extractAmount(from: input) == nil {
                    let unitStr = unit == .sats || unit == .satoshis ? " sats" : " BTC"
                    enriched += " \(amt)\(unitStr)"
                }
            case .intent:
                break // Intent resolution is handled separately
            case .transaction(let tx):
                enriched += " \(tx.txid)"
            }
        }
        return enriched
    }

    // MARK: - Address Reference

    private func resolveAddressReference(_ lower: String, memory: ConversationMemory) -> String? {
        let triggers = [
            "same address", "that address", "the address", "previous address",
            "last address", "there again", "same place",
            "نفس العنوان", "ذلك العنوان",
            "la misma dirección", "la misma direccion", "esa dirección",
        ]
        guard triggers.contains(where: { lower.contains($0) }) else { return nil }
        return memory.lastAddress
    }

    // MARK: - Amount Reference

    private func resolveAmountReference(_ lower: String, memory: ConversationMemory) -> (Decimal, BitcoinUnit)? {
        // Exact references
        let exactTriggers = [
            "same amount", "that amount", "the amount", "that much",
            "نفس المبلغ", "la misma cantidad",
        ]
        if exactTriggers.contains(where: { lower.contains($0) }), let amt = memory.lastAmount {
            return (amt, .btc)
        }

        // Relative references
        if let modified = resolveRelativeAmount(lower, base: memory.lastAmount) {
            return (modified, .btc)
        }

        return nil
    }

    // MARK: - Repeat Reference

    private func resolveRepeatReference(_ lower: String, memory: ConversationMemory) -> WalletIntent? {
        let triggers = [
            "again", "repeat", "do it again", "same thing", "one more time",
            "redo", "repeat that", "do that again",
            "مرة أخرى", "otra vez",
        ]
        guard triggers.contains(where: { lower.contains($0) }) else { return nil }
        return memory.lastUserIntent
    }

    // MARK: - Ordinal Reference

    private func resolveOrdinalReference(_ lower: String, memory: ConversationMemory) -> TransactionDisplayItem? {
        guard let txs = memory.lastShownTransactions, !txs.isEmpty else { return nil }

        if let idx = extractOrdinalIndex(lower) {
            if idx == -1 {
                // "last" or "latest" means the first item (most recent)
                return txs.first
            }
            guard idx >= 0, idx < txs.count else { return nil }
            return txs[idx]
        }
        return nil
    }

    // MARK: - Modification Reference

    private func resolveModification(_ input: String, lower: String, memory: ConversationMemory) -> [ResolvedEntity] {
        let modTriggers = [
            "actually", "change to", "change it to", "make it",
            "instead", "no,", "nah,", "wait,", "actually,",
        ]
        guard modTriggers.contains(where: { lower.contains($0) }) else { return [] }

        var resolved: [ResolvedEntity] = []

        if let (amt, unit) = entityExtractor.extractAmount(from: input) {
            let resolvedUnit = unit
            resolved.append(.amount(amt, resolvedUnit))
        }
        if let addr = entityExtractor.extractAddress(from: input) {
            resolved.append(.address(addr))
        }

        return resolved
    }

    // MARK: - Private Helpers

    private func extractOrdinalIndex(_ text: String) -> Int? {
        let ordinals: [(String, Int)] = [
            ("first", 0), ("1st", 0),
            ("second", 1), ("2nd", 1),
            ("third", 2), ("3rd", 2),
            ("fourth", 3), ("4th", 3),
            ("fifth", 4), ("5th", 4),
            ("sixth", 5), ("6th", 5),
            ("seventh", 6), ("7th", 6),
            ("eighth", 7), ("8th", 7),
            ("ninth", 8), ("9th", 8),
            ("tenth", 9), ("10th", 9),
            ("last", -1), ("latest", -1), ("most recent", -1),
        ]

        for (word, idx) in ordinals {
            if text.contains(word) { return idx }
        }

        // Check for "#N" pattern
        if let match = text.range(of: #"#(\d+)"#, options: .regularExpression) {
            let numStr = String(text[match]).dropFirst()
            if let num = Int(numStr), num >= 1 {
                return num - 1 // Convert 1-indexed to 0-indexed
            }
        }

        return nil
    }

    private func resolveRelativeAmount(_ text: String, base: Decimal?) -> Decimal? {
        guard let base = base, base > 0 else { return nil }
        if text.contains("double") || text.contains("twice") { return base * 2 }
        if text.contains("triple") { return base * 3 }
        if text.contains("half") { return base / 2 }
        if text.contains("bit more") || text.contains("a little more") { return base * Decimal(string: "1.1")! }
        if text.contains("bit less") || text.contains("a little less") { return base * Decimal(string: "0.9")! }
        return nil
    }
}
