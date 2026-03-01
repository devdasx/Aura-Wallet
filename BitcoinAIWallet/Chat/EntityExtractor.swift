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

    // MARK: - Smart Character Normalization

    /// Normalizes iOS smart quotes, em-dashes, and other typographic variants
    /// to their ASCII equivalents so regex patterns work reliably.
    private func normalizeText(_ text: String) -> String {
        var s = text
        // Smart single quotes -> ASCII apostrophe
        s = s.replacingOccurrences(of: "\u{2018}", with: "'")
        s = s.replacingOccurrences(of: "\u{2019}", with: "'")
        // Smart double quotes -> ASCII double quote
        s = s.replacingOccurrences(of: "\u{201C}", with: "\"")
        s = s.replacingOccurrences(of: "\u{201D}", with: "\"")
        // Em-dash / en-dash -> hyphen
        s = s.replacingOccurrences(of: "\u{2014}", with: "-")
        s = s.replacingOccurrences(of: "\u{2013}", with: "-")
        // Non-breaking space -> regular space
        s = s.replacingOccurrences(of: "\u{00A0}", with: " ")
        // Collapse multiple whitespace/tabs into a single space
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Amount Patterns

    /// Matches currency-symbol-prefixed amounts: "$100", "€50", "£30", "¥1000"
    /// Group 1: currency symbol
    /// Group 2: numeric part (with optional commas and decimal)
    /// Group 3: optional multiplier (k, m)
    private let symbolPrefixAmountPattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"([$€£¥])\s*(\d[\d,]*\.?\d*|\.\d+)(k|m)?"#,
            options: [.caseInsensitive]
        )
    }()

    /// Matches amounts with trailing currency symbol: "100€", "50$", "30£"
    /// Group 1: numeric part
    /// Group 2: optional multiplier (k, m)
    /// Group 3: currency symbol
    private let symbolSuffixAmountPattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"(\d[\d,]*\.?\d*|\.\d+)(k|m)?\s*([$€£¥])"#,
            options: [.caseInsensitive]
        )
    }()

    /// Matches numeric amounts with optional unit suffix:
    /// "0.005", ".005", "500000", "0.005 btc", "500000 sats",
    /// "500k sats", "1.5m sats", "100 dollars", "50 bucks", etc.
    /// Group 1: numeric part (with optional commas and decimal)
    /// Group 2: optional multiplier suffix (k, m)
    /// Group 3: optional unit/currency word
    private let numericAmountPattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"(?:^|\s)(\d[\d,]*\.?\d*|\.\d+)(k|m)?\s*(btc|bitcoin|bitcoins|sat|sats|satoshi|satoshis|dollars?|bucks?|usd|euros?|eur|pounds?|quid|gbp|yen|jpy|yuan|cny|rupees?|inr|real|reais|brl|pesos?|mxn|won|krw|francs?|chf|krona|kronor|sek|krone|nok|cad|aud)?\b"#,
            options: [.caseInsensitive]
        )
    }()

    /// Matches "all" / "max" / "everything" / "entire balance" keywords for full balance.
    private let allAmountPattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"\b(all|max|everything|entire\s+balance)\b"#,
            options: [.caseInsensitive]
        )
    }()

    /// Matches "half" or "half a bitcoin" for 50% of balance.
    private let halfAmountPattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"\bhalf\s*(?:a\s+)?(?:bitcoin|btc)?\b"#,
            options: [.caseInsensitive]
        )
    }()

    /// Matches word numbers: "one bitcoin", "two btc", "half a bitcoin", "a quarter btc"
    private let wordNumberPattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"\b(one|two|three|four|five|six|seven|eight|nine|ten|a\s+quarter|a\s+half|quarter)\s+(bitcoin|btc|sat|sats|satoshi|satoshis)\b"#,
            options: [.caseInsensitive]
        )
    }()

    // MARK: - Address Patterns

    /// Matches Bitcoin addresses in text, including inside BIP21 URIs.
    /// Handles mainnet (bc1q, bc1p, 1..., 3...) and testnet (tb1, m, n, 2).
    private let addressPattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"(?:^|[\s,;:(])(bc1[qp][a-zA-HJ-NP-Za-km-z02-9]{38,58}|tb1[qp][a-zA-HJ-NP-Za-km-z02-9]{38,58}|[13][a-km-zA-HJ-NP-Z1-9]{24,33}|[mn2][a-km-zA-HJ-NP-Z1-9]{24,33})"#,
            options: []
        )
    }()

    /// Matches BIP21 URIs: "bitcoin:ADDRESS?amount=X&label=Y"
    /// Group 1: address
    /// Group 2: optional query string
    private let bip21Pattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"bitcoin:([a-zA-Z0-9]{25,90})(\?[^\s]*)?"#,
            options: [.caseInsensitive]
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
        (#"\b(medium|normal|standard|regular|default|moderate|average)\b"#, .medium),
        (#"\b(slow|low|economy|cheap|no\s*rush|eco|saver|cheapest|minimum)\b"#, .slow),
        (#"\b(custom)\s*(?:fee|rate)?\b"#, .custom),
    ]

    /// Matches custom fee rates: "5 sat/vb", "5 sats per byte", "5 sat/vbyte", "10 sat/byte"
    /// Group 1: numeric fee rate
    private let customFeeRatePattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"(\d+(?:\.\d+)?)\s*(?:sat(?:s|oshi|oshis)?[\s/]*(?:per\s*)?(?:v?byte|vb))"#,
            options: [.caseInsensitive]
        )
    }()

    /// Pre-compiled fee level patterns.
    private let feeLevelPatterns: [(regex: NSRegularExpression, level: FeeLevel)]

    // MARK: - Currency-in-context pattern

    /// Matches "in USD", "to EUR", "in dollars", "in gbp", "to euros", etc.
    private let currencyContextPattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"(?:in|to|as)\s+(usd|eur|gbp|jpy|cny|cad|aud|chf|sek|nok|inr|brl|mxn|krw|dollars?|euros?|pounds?|yen|yuan|bucks?|quid|francs?|rupees?|pesos?|won|krona|kronor|krone)\b"#,
            options: [.caseInsensitive]
        )
    }()

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
        let normalized = normalizeText(text)
        var entity = ParsedEntity()

        // Extract BIP21 URI first (may contain both address and amount)
        let bip21Result = extractBIP21(from: normalized)

        if let result = extractAmount(from: normalized) {
            entity.amount = result.amount
            entity.unit = result.unit
            entity.currency = result.currency
        }

        // BIP21 amount overrides if present and no explicit amount was found
        if entity.amount == nil, let bip21Amount = bip21Result?.amount {
            entity.amount = bip21Amount
            entity.unit = .btc
        }

        entity.address = bip21Result?.address ?? extractAddress(from: normalized)
        entity.txid = extractTxId(from: normalized)
        entity.count = extractCount(from: normalized)
        entity.feeLevel = extractFeeLevel(from: normalized)

        // Extract currency from context if not already set
        if entity.currency == nil {
            entity.currency = extractCurrencyFromContext(from: normalized)
        }

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
    /// - `"100€"` -> (100, .btc, "EUR")
    /// - `"100 dollars"` -> (100, .btc, "USD")
    /// - `"50 bucks"` -> (50, .btc, "USD")
    /// - `"all"` / `"max"` -> (-1, .btc, nil) sentinel value for "send everything"
    /// - `"half"` -> (-0.5, .btc, nil) sentinel value for "send half"
    /// - `"one bitcoin"` -> (1, .btc, nil)
    /// - `"1,000 sats"` -> (1000, .sats, nil)
    /// - `"1,234.56"` -> (1234.56, nil, nil)
    ///
    /// - Parameter text: The raw user input.
    /// - Returns: A tuple of (amount, unit, currency) or nil if no amount was found.
    func extractAmount(from text: String) -> (amount: Decimal, unit: BitcoinUnit, currency: String?)? {
        let normalized = normalizeText(text)
        let nsText = normalized as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        // 1. Check for "all" / "max" / "everything" first
        if allAmountPattern.firstMatch(in: normalized, options: [], range: fullRange) != nil {
            return (Decimal(-1), .btc, nil)
        }

        // 2. Check for "half" / "half a bitcoin"
        if halfAmountPattern.firstMatch(in: normalized, options: [], range: fullRange) != nil {
            return (Decimal(string: "-0.5")!, .btc, nil)
        }

        // 3. Check for word numbers: "one bitcoin", "two btc", "a quarter btc"
        if let wordResult = extractWordNumber(from: normalized) {
            return wordResult
        }

        // 4. Check for symbol-prefix amounts: "$100", "€50"
        if let symbolResult = extractSymbolPrefixAmount(from: normalized) {
            return symbolResult
        }

        // 5. Check for symbol-suffix amounts: "100€", "50$"
        if let suffixResult = extractSymbolSuffixAmount(from: normalized) {
            return suffixResult
        }

        // 6. Try numeric amount pattern with optional unit
        if let numericResult = extractNumericAmount(from: normalized) {
            return numericResult
        }

        return nil
    }

    /// Extracts a Bitcoin address from text.
    ///
    /// Matches mainnet addresses (1..., 3..., bc1q..., bc1p...) and
    /// testnet addresses (m/n..., 2..., tb1q..., tb1p...).
    /// Strips trailing punctuation that might accidentally be captured.
    ///
    /// - Parameter text: The raw user input.
    /// - Returns: The first valid address found, or nil.
    func extractAddress(from text: String) -> String? {
        let normalized = normalizeText(text)

        // Try BIP21 URI first
        if let bip21 = extractBIP21(from: normalized) {
            return bip21.address
        }

        let nsText = normalized as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        let matches = addressPattern.matches(in: normalized, options: [], range: fullRange)
        for match in matches {
            guard match.range(at: 1).location != NSNotFound else { continue }
            var candidate = nsText.substring(with: match.range(at: 1))

            // Strip trailing punctuation that might have been captured
            candidate = stripTrailingPunctuation(candidate)

            // Quick structural validation
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
    /// - Parameter text: The raw user input.
    /// - Returns: The extracted count, or nil.
    func extractCount(from text: String) -> Int? {
        let normalized = normalizeText(text)
        let nsText = normalized as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        guard let match = countPattern.firstMatch(in: normalized, options: [], range: fullRange) else {
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
        let normalized = normalizeText(text)
        let nsText = normalized as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        guard let match = txidPattern.firstMatch(in: normalized, options: [], range: fullRange) else {
            return nil
        }

        guard match.range(at: 1).location != NSNotFound else { return nil }
        let txid = nsText.substring(with: match.range(at: 1))

        // Ensure it's exactly 64 hex characters
        guard txid.count == 64 else { return nil }

        return txid.lowercased()
    }

    /// Extracts a fee level keyword from text.
    ///
    /// Supports named levels (fast/medium/slow) and custom rates like "5 sat/vb".
    ///
    /// - Parameter text: The raw user input.
    /// - Returns: The matched `FeeLevel`, or nil.
    func extractFeeLevel(from text: String) -> FeeLevel? {
        let normalized = normalizeText(text)
        let nsText = normalized as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        // Check for custom fee rate first: "5 sat/vb", "10 sats per byte"
        if customFeeRatePattern.firstMatch(in: normalized, options: [], range: fullRange) != nil {
            return .custom
        }

        for (regex, level) in feeLevelPatterns {
            if regex.firstMatch(in: normalized, options: [], range: fullRange) != nil {
                return level
            }
        }

        return nil
    }

    /// Extracts a custom fee rate value in sat/vB from text.
    ///
    /// - Parameter text: The raw user input.
    /// - Returns: The custom fee rate as a Decimal, or nil.
    func extractCustomFeeRate(from text: String) -> Decimal? {
        let normalized = normalizeText(text)
        let nsText = normalized as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        guard let match = customFeeRatePattern.firstMatch(in: normalized, options: [], range: fullRange) else {
            return nil
        }

        guard match.range(at: 1).location != NSNotFound else { return nil }
        let rateString = nsText.substring(with: match.range(at: 1))
        guard let rate = Decimal(string: rateString), rate > 0 else { return nil }
        return rate
    }

    // MARK: - Private Amount Extraction Helpers

    /// Extracts amounts prefixed with a currency symbol: "$100", "€50.25"
    private func extractSymbolPrefixAmount(from text: String) -> (amount: Decimal, unit: BitcoinUnit, currency: String?)? {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        guard let match = symbolPrefixAmountPattern.firstMatch(in: text, options: [], range: fullRange) else {
            return nil
        }

        guard match.range(at: 1).location != NSNotFound,
              match.range(at: 2).location != NSNotFound else {
            return nil
        }

        let symbol = nsText.substring(with: match.range(at: 1))
        let rawNumber = nsText.substring(with: match.range(at: 2))
        let numberString = stripCommas(rawNumber)

        guard var amount = Decimal(string: numberString) else { return nil }

        // Apply multiplier
        if match.range(at: 3).location != NSNotFound {
            let suffix = nsText.substring(with: match.range(at: 3)).lowercased()
            amount = applyMultiplier(amount, suffix: suffix)
        }

        guard amount > 0, amount <= 21_000_000_000 else { return nil }

        guard let currencyCode = currencyCodeFromSymbol(symbol) else { return nil }

        return (amount, .btc, currencyCode)
    }

    /// Extracts amounts followed by a currency symbol: "100€", "50$"
    private func extractSymbolSuffixAmount(from text: String) -> (amount: Decimal, unit: BitcoinUnit, currency: String?)? {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        guard let match = symbolSuffixAmountPattern.firstMatch(in: text, options: [], range: fullRange) else {
            return nil
        }

        guard match.range(at: 1).location != NSNotFound,
              match.range(at: 3).location != NSNotFound else {
            return nil
        }

        let rawNumber = nsText.substring(with: match.range(at: 1))
        let numberString = stripCommas(rawNumber)
        let symbol = nsText.substring(with: match.range(at: 3))

        guard var amount = Decimal(string: numberString) else { return nil }

        // Apply multiplier
        if match.range(at: 2).location != NSNotFound {
            let suffix = nsText.substring(with: match.range(at: 2)).lowercased()
            amount = applyMultiplier(amount, suffix: suffix)
        }

        guard amount > 0, amount <= 21_000_000_000 else { return nil }

        guard let currencyCode = currencyCodeFromSymbol(symbol) else { return nil }

        return (amount, .btc, currencyCode)
    }

    /// Extracts numeric amounts with optional unit suffix.
    private func extractNumericAmount(from text: String) -> (amount: Decimal, unit: BitcoinUnit, currency: String?)? {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        guard let match = numericAmountPattern.firstMatch(in: text, options: [], range: fullRange) else {
            return nil
        }

        guard match.range(at: 1).location != NSNotFound else { return nil }

        let rawNumber = nsText.substring(with: match.range(at: 1))
        let numberString = stripCommas(rawNumber)

        guard var amount = Decimal(string: numberString) else { return nil }

        // Apply multiplier suffix if present (group 2)
        if match.range(at: 2).location != NSNotFound {
            let suffix = nsText.substring(with: match.range(at: 2)).lowercased()
            amount = applyMultiplier(amount, suffix: suffix)
        }

        // Sanity check: amount must be positive and within Bitcoin supply
        guard amount > 0 else { return nil }

        // Determine unit and fiat currency from group 3
        var unit: BitcoinUnit?
        var fiatCurrency: String?

        if match.range(at: 3).location != NSNotFound {
            let unitString = nsText.substring(with: match.range(at: 3)).lowercased()
            if let btcUnit = parseUnit(unitString) {
                unit = btcUnit
            } else {
                fiatCurrency = parseFiatCurrency(unitString)
            }
        }

        // Validate range based on unit
        if let detectedUnit = unit {
            switch detectedUnit {
            case .btc:
                guard amount <= 21_000_000 else { return nil }
            case .sats, .satoshis:
                guard amount <= 2_100_000_000_000_000 else { return nil }
            }
        } else if fiatCurrency != nil {
            guard amount <= 21_000_000_000 else { return nil }
        } else {
            // No unit specified
            guard amount <= 21_000_000_000 else { return nil }
        }

        // If a fiat currency was detected, set unit to .btc (system will convert)
        if let fiat = fiatCurrency {
            return (amount, .btc, fiat)
        }

        // Heuristic: if no unit was specified but the amount is a large integer,
        // assume satoshis. Amounts >= 1000 without a decimal are likely sats.
        if unit == nil, amount >= 1_000, !numberString.contains(".") {
            unit = .sats
        }

        return (amount, unit ?? .btc, nil)
    }

    /// Extracts word-based numbers: "one bitcoin", "two btc", "a quarter btc"
    private func extractWordNumber(from text: String) -> (amount: Decimal, unit: BitcoinUnit, currency: String?)? {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        guard let match = wordNumberPattern.firstMatch(in: text, options: [], range: fullRange) else {
            return nil
        }

        guard match.range(at: 1).location != NSNotFound,
              match.range(at: 2).location != NSNotFound else {
            return nil
        }

        let wordPart = nsText.substring(with: match.range(at: 1)).lowercased()
            .trimmingCharacters(in: .whitespaces)
        let unitPart = nsText.substring(with: match.range(at: 2)).lowercased()

        guard let amount = wordToNumber(wordPart) else { return nil }
        guard amount > 0 else { return nil }

        let unit = parseUnit(unitPart) ?? .btc

        return (amount, unit, nil)
    }

    /// Maps a word to its numeric equivalent.
    private func wordToNumber(_ word: String) -> Decimal? {
        switch word {
        case "one": return Decimal(1)
        case "two": return Decimal(2)
        case "three": return Decimal(3)
        case "four": return Decimal(4)
        case "five": return Decimal(5)
        case "six": return Decimal(6)
        case "seven": return Decimal(7)
        case "eight": return Decimal(8)
        case "nine": return Decimal(9)
        case "ten": return Decimal(10)
        case "a half": return Decimal(string: "0.5")
        case "a quarter": return Decimal(string: "0.25")
        case "quarter": return Decimal(string: "0.25")
        default: return nil
        }
    }

    // MARK: - BIP21 URI Extraction

    /// Extracts address and optional amount from a BIP21 URI.
    ///
    /// Format: `bitcoin:ADDRESS?amount=X&label=Y`
    ///
    /// - Parameter text: The raw user input.
    /// - Returns: A tuple of (address, amount) or nil.
    private func extractBIP21(from text: String) -> (address: String, amount: Decimal?)? {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        guard let match = bip21Pattern.firstMatch(in: text, options: [], range: fullRange) else {
            return nil
        }

        guard match.range(at: 1).location != NSNotFound else { return nil }
        let address = nsText.substring(with: match.range(at: 1))

        // Validate the address
        let validator = AddressValidator()
        let strippedAddress = stripTrailingPunctuation(address)
        guard validator.isValid(strippedAddress) else { return nil }

        // Parse query parameters for amount
        var amount: Decimal?
        if match.range(at: 2).location != NSNotFound {
            let queryString = nsText.substring(with: match.range(at: 2))
            // Remove leading '?'
            let params = String(queryString.dropFirst())
            let pairs = params.split(separator: "&")
            for pair in pairs {
                let parts = pair.split(separator: "=", maxSplits: 1)
                if parts.count == 2, parts[0].lowercased() == "amount" {
                    amount = Decimal(string: String(parts[1]))
                }
            }
        }

        return (strippedAddress, amount)
    }

    // MARK: - Currency Context Extraction

    /// Extracts a currency mentioned in context phrases like "in USD", "to euros".
    private func extractCurrencyFromContext(from text: String) -> String? {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        guard let match = currencyContextPattern.firstMatch(in: text, options: [], range: fullRange) else {
            return nil
        }

        guard match.range(at: 1).location != NSNotFound else { return nil }
        let currencyText = nsText.substring(with: match.range(at: 1)).lowercased()

        // Try as ISO code first
        let upper = currencyText.uppercased()
        if CurrencyParser.supportedCurrencyCodes.contains(upper) {
            return upper
        }

        // Try as currency name
        return parseFiatCurrency(currencyText)
    }

    // MARK: - Private Helpers

    /// Strips commas from a number string: "1,000" -> "1000", "1,234.56" -> "1234.56"
    private func stripCommas(_ text: String) -> String {
        return text.replacingOccurrences(of: ",", with: "")
    }

    /// Strips trailing punctuation from an address string.
    private func stripTrailingPunctuation(_ address: String) -> String {
        var s = address
        while let last = s.last, ".,:;!?)\"'".contains(last) {
            s = String(s.dropLast())
        }
        return s
    }

    /// Applies a k/m multiplier to an amount.
    private func applyMultiplier(_ amount: Decimal, suffix: String) -> Decimal {
        switch suffix {
        case "k":
            return amount * 1_000
        case "m":
            return amount * 1_000_000
        default:
            return amount
        }
    }

    /// Maps a unit string to a `BitcoinUnit` enum value.
    private func parseUnit(_ unitString: String) -> BitcoinUnit? {
        switch unitString.lowercased() {
        case "btc", "bitcoin", "bitcoins":
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
        case "pounds", "pound", "quid", "gbp", "sterling":
            return "GBP"
        case "yen", "jpy":
            return "JPY"
        case "yuan", "cny", "renminbi", "rmb":
            return "CNY"
        case "rupee", "rupees", "inr":
            return "INR"
        case "real", "reais", "brl":
            return "BRL"
        case "peso", "pesos", "mxn":
            return "MXN"
        case "won", "krw":
            return "KRW"
        case "franc", "francs", "chf":
            return "CHF"
        case "krona", "kronor", "sek":
            return "SEK"
        case "krone", "nok":
            return "NOK"
        case "cad":
            return "CAD"
        case "aud":
            return "AUD"
        default:
            return nil
        }
    }
}
