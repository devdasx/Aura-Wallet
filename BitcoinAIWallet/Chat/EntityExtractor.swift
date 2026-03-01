// MARK: - EntityExtractor.swift
// Bitcoin AI Wallet
//
// Extracts structured entities (amounts, addresses, transaction IDs,
// counts, fee levels) from natural language text using regex patterns.
// No AI/LLM API calls — pure regex and string matching.
//
// Platform: iOS 17.0+
// Framework: Foundation

import Foundation

// MARK: - EntityExtractor

/// Extracts structured entities from user input text.
///
/// Scans for Bitcoin amounts (with optional unit), addresses, transaction IDs,
/// numeric counts, and fee level keywords. All extraction is performed locally
/// using regular expressions and string matching.
final class EntityExtractor {

    // MARK: - Amount Patterns

    /// Matches amounts like: "0.005", ".005", "500000", "0.005 btc", "500000 sats",
    /// "500k sats", "1.5m sats", "0.5M", "$50", "€100", "£75", "¥1000",
    /// "100 dollars", "50 bucks", "200 euros", "all", "max", "everything"
    /// Group 1: optional leading currency symbol ($, €, £, ¥)
    /// Group 2: numeric part (with optional decimal)
    /// Group 3: optional multiplier suffix (k, m)
    /// Group 4: optional unit (btc, sat, sats, satoshi, satoshis, bitcoin,
    ///          dollars, dollar, bucks, usd, euros, euro, eur, pounds, pound,
    ///          quid, gbp, yen, jpy, cad, aud)
    private let amountPattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"(?:^|\s)([$€£¥])?(\d+\.?\d*|\.\d+)(k|m)?(?:\s*(btc|sat|sats|satoshi|satoshis|bitcoin|dollars?|bucks?|usd|euros?|eur|pounds?|quid|gbp|yen|jpy|cad|aud))?"#,
            options: [.caseInsensitive]
        )
    }()

    /// Matches the "all" / "max" / "everything" keyword for sending entire balance.
    private let allAmountPattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"\b(all|max|everything|entire\s+balance)\b"#,
            options: [.caseInsensitive]
        )
    }()

    // MARK: - Address Pattern

    /// Matches Bitcoin mainnet addresses:
    /// - Legacy P2PKH: 1[base58]{24,33}
    /// - P2SH: 3[base58]{24,33}
    /// - SegWit v0: bc1q[bech32]{38,58}
    /// - Taproot v1: bc1p[bech32]{58}
    /// Also matches testnet:
    /// - tb1q..., tb1p..., m/n..., 2...
    private let addressPattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"(?:^|\s)(bc1[qp][a-zA-HJ-NP-Za-km-z02-9]{38,58}|tb1[qp][a-zA-HJ-NP-Za-km-z02-9]{38,58}|[13][a-km-zA-HJ-NP-Z1-9]{24,33}|[mn2][a-km-zA-HJ-NP-Z1-9]{24,33})"#,
            options: []
        )
    }()

    // MARK: - Transaction ID Pattern

    /// Matches a 64-character hexadecimal transaction ID.
    private let txidPattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"\b([a-fA-F0-9]{64})\b"#,
            options: []
        )
    }()

    // MARK: - Count Patterns

    /// Matches "last N", "N transactions", "show N", "recent N", "top N".
    private let countPattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"(?:last|show|recent|top|past|previous)\s+(\d+)|(\d+)\s+(?:transactions?|txs?|transfers?)"#,
            options: [.caseInsensitive]
        )
    }()

    // MARK: - Fee Level Keywords

    private let feeLevelMappings: [(pattern: String, level: FeeLevel)] = [
        (#"\b(fast|priority|urgent|high|rush|asap|fastest|next\s*block)\b"#, .fast),
        (#"\b(medium|normal|standard|regular|default|moderate)\b"#, .medium),
        (#"\b(slow|low|economy|cheap|no\s*rush|eco|saver|cheapest)\b"#, .slow),
        (#"\b(custom)\s*(?:fee|rate)?\b"#, .custom)
    ]

    /// Pre-compiled fee level patterns.
    private let feeLevelPatterns: [(regex: NSRegularExpression, level: FeeLevel)]

    // MARK: - Initialization

    init() {
        self.feeLevelPatterns = feeLevelMappings.compactMap { mapping in
            guard let regex = try? NSRegularExpression(pattern: mapping.pattern, options: [.caseInsensitive]) else {
                return nil
            }
            return (regex, mapping.level)
        }
    }

    // MARK: - Public API

    /// Extracts all recognized entities from the input text.
    ///
    /// Scans for amounts, addresses, transaction IDs, counts, and fee levels.
    /// Returns a `ParsedEntity` with all found values populated.
    ///
    /// - Parameter text: The raw user input.
    /// - Returns: A `ParsedEntity` containing all extracted values.
    func extract(from text: String) -> ParsedEntity {
        var entity = ParsedEntity()

        if let result = extractAmount(from: text) {
            entity.amount = result.amount
            entity.unit = result.unit
            entity.currency = result.currency
        }

        entity.address = extractAddress(from: text)
        entity.txid = extractTxId(from: text)
        entity.count = extractCount(from: text)
        entity.feeLevel = extractFeeLevel(from: text)

        return entity
    }

    /// Extracts a Bitcoin amount and optional unit from text, with optional fiat currency.
    ///
    /// Supports formats:
    /// - `"0.005"` -> (0.005, nil, nil)
    /// - `"0.005 BTC"` -> (0.005, .btc, nil)
    /// - `"500000 sats"` -> (500000, .sats, nil)
    /// - `".005"` -> (0.005, nil, nil)
    /// - `"500k sats"` -> (500000, .sats, nil)
    /// - `"1.5m sats"` -> (1500000, .sats, nil)
    /// - `"$50"` -> (50, .btc, "USD")
    /// - `"€100"` -> (100, .btc, "EUR")
    /// - `"100 dollars"` -> (100, .btc, "USD")
    /// - `"50 bucks"` -> (50, .btc, "USD")
    /// - `"all"` / `"max"` -> (-1, .btc, nil) sentinel value for "send everything"
    ///
    /// - Parameter text: The raw user input.
    /// - Returns: A tuple of (amount, unit, currency) or nil if no amount was found.
    func extractAmount(from text: String) -> (amount: Decimal, unit: BitcoinUnit, currency: String?)? {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        // Check for "all" / "max" / "everything" first
        if allAmountPattern.firstMatch(in: text, options: [], range: fullRange) != nil {
            // Return -1 as sentinel for "send entire balance"
            return (Decimal(-1), .btc, nil)
        }

        // Try numeric amount pattern
        guard let match = amountPattern.firstMatch(in: text, options: [], range: fullRange) else {
            return nil
        }

        // Group 1: optional currency symbol prefix ($, €, £, ¥)
        var currencyFromSymbol: String?
        if match.range(at: 1).location != NSNotFound {
            let symbol = nsText.substring(with: match.range(at: 1))
            currencyFromSymbol = currencyCodeFromSymbol(symbol)
        }

        // Extract the numeric part (group 2)
        guard match.range(at: 2).location != NSNotFound else { return nil }
        let numberString = nsText.substring(with: match.range(at: 2))
        guard var amount = Decimal(string: numberString) else { return nil }

        // Apply multiplier suffix if present (group 3)
        if match.range(at: 3).location != NSNotFound {
            let suffix = nsText.substring(with: match.range(at: 3)).lowercased()
            switch suffix {
            case "k":
                amount = amount * 1_000
            case "m":
                amount = amount * 1_000_000
            default:
                break
            }
        }

        // Determine unit and fiat currency from group 4
        var unit: BitcoinUnit?
        var fiatCurrency: String?
        if match.range(at: 4).location != NSNotFound {
            let unitString = nsText.substring(with: match.range(at: 4)).lowercased()
            // Try BTC units first
            if let btcUnit = parseUnit(unitString) {
                unit = btcUnit
            } else {
                // Try fiat currency synonyms
                fiatCurrency = parseFiatCurrency(unitString)
            }
        }

        // Currency symbol prefix takes precedence if no trailing unit was found
        if fiatCurrency == nil, let symbolCurrency = currencyFromSymbol {
            fiatCurrency = symbolCurrency
        }

        // Sanity check: amount must be positive (except -1 sentinel)
        guard amount > 0 else { return nil }

        // If a fiat currency was detected, set unit to .btc (system will convert)
        if fiatCurrency != nil {
            return (amount, .btc, fiatCurrency)
        }

        // Heuristic: if no unit was specified but the amount is a large integer,
        // assume satoshis. Amounts >= 1000 without a decimal are likely sats.
        if unit == nil, amount >= 1_000, !numberString.contains(".") {
            unit = .sats
        }

        return (amount, unit ?? .btc, nil)
    }

    /// Extracts a Bitcoin address from text.
    ///
    /// Matches mainnet addresses (1..., 3..., bc1q..., bc1p...) and
    /// testnet addresses (m/n..., 2..., tb1q..., tb1p...).
    ///
    /// - Parameter text: The raw user input.
    /// - Returns: The first valid address found, or nil.
    func extractAddress(from text: String) -> String? {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        let matches = addressPattern.matches(in: text, options: [], range: fullRange)
        for match in matches {
            guard match.range(at: 1).location != NSNotFound else { continue }
            let candidate = nsText.substring(with: match.range(at: 1))

            // Quick structural validation — don't return garbage
            let validator = AddressValidator()
            if validator.isValid(candidate) {
                return candidate
            }
        }

        return nil
    }

    /// Extracts a numeric count from text.
    ///
    /// Matches patterns like "last 5 transactions", "show 10", "recent 3".
    ///
    /// - Parameter text: The raw user input (should be lowercased).
    /// - Returns: The extracted count, or nil.
    func extractCount(from text: String) -> Int? {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        guard let match = countPattern.firstMatch(in: text, options: [], range: fullRange) else {
            return nil
        }

        // Try group 1 first ("last N")
        if match.range(at: 1).location != NSNotFound {
            let numberString = nsText.substring(with: match.range(at: 1))
            return Int(numberString)
        }

        // Try group 2 ("N transactions")
        if match.range(at: 2).location != NSNotFound {
            let numberString = nsText.substring(with: match.range(at: 2))
            return Int(numberString)
        }

        return nil
    }

    /// Extracts a transaction ID (64-character hex string) from text.
    ///
    /// - Parameter text: The raw user input.
    /// - Returns: The first valid transaction ID found, or nil.
    func extractTxId(from text: String) -> String? {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        guard let match = txidPattern.firstMatch(in: text, options: [], range: fullRange) else {
            return nil
        }

        guard match.range(at: 1).location != NSNotFound else { return nil }
        let txid = nsText.substring(with: match.range(at: 1))

        // Ensure it's exactly 64 hex characters (the regex should guarantee this,
        // but we double-check for safety).
        guard txid.count == 64 else { return nil }

        return txid.lowercased()
    }

    /// Extracts a fee level keyword from text.
    ///
    /// - Parameter text: The raw user input.
    /// - Returns: The matched `FeeLevel`, or nil.
    func extractFeeLevel(from text: String) -> FeeLevel? {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        for (regex, level) in feeLevelPatterns {
            if regex.firstMatch(in: text, options: [], range: fullRange) != nil {
                return level
            }
        }

        return nil
    }

    // MARK: - Private Helpers

    /// Maps a unit string to a `BitcoinUnit` enum value.
    private func parseUnit(_ unitString: String) -> BitcoinUnit? {
        switch unitString.lowercased() {
        case "btc", "bitcoin":
            return .btc
        case "sat", "sats":
            return .sats
        case "satoshi", "satoshis":
            return .satoshis
        default:
            return nil
        }
    }

    /// Maps a currency symbol character to its ISO 4217 code.
    private func currencyCodeFromSymbol(_ symbol: String) -> String? {
        switch symbol {
        case "$": return "USD"
        case "€": return "EUR"
        case "£": return "GBP"
        case "¥": return "JPY"
        default: return nil
        }
    }

    /// Maps a fiat currency synonym to its ISO 4217 code.
    private func parseFiatCurrency(_ text: String) -> String? {
        switch text.lowercased() {
        case "dollars", "dollar", "bucks", "buck", "usd":
            return "USD"
        case "euros", "euro", "eur":
            return "EUR"
        case "pounds", "pound", "quid", "gbp":
            return "GBP"
        case "yen", "jpy":
            return "JPY"
        case "cad":
            return "CAD"
        case "aud":
            return "AUD"
        default:
            return nil
        }
    }
}
