// MARK: - CurrencyParser.swift
// Bitcoin AI Wallet
//
// Detects and parses amounts in any world currency from natural language text.
// Supports symbol-prefix (e.g. "$50"), symbol-suffix (e.g. "100€"),
// code-suffix (e.g. "100 EUR"), name-suffix (e.g. "100 dollars"),
// and contextual extraction (e.g. "in euros", "to USD").
//
// Uses the existing PriceService to convert detected fiat amounts to BTC.
//
// Platform: iOS 17.0+
// Framework: Foundation

import Foundation

// MARK: - CurrencyParser

/// Parses fiat currency amounts from natural language text and converts to BTC.
///
/// Supports:
/// - Symbol-prefixed: "$50", "€100.50", "£25", "¥1000"
/// - Symbol-suffixed: "100€", "50$", "30£"
/// - Code-suffixed: "50 USD", "100 EUR", "1000 SAR"
/// - Named: "50 dollars", "100 euros", "50 bucks", "30 quid"
/// - Comma-formatted: "$1,000", "1,234.56 EUR"
/// - Contextual: "in USD", "to euros", "in gbp"
/// - Bare amounts with context clues
final class CurrencyParser {

    // MARK: - Currency Detection Result

    /// Result of parsing a fiat amount from text.
    struct FiatAmount: Equatable {
        let amount: Decimal
        let currencyCode: String
        let currencySymbol: String
    }

    // MARK: - Supported Currencies

    /// Maps currency symbols to ISO 4217 codes.
    /// Ordered from most-specific (multi-character) to least-specific (single-character)
    /// so that longer symbols match before shorter ones.
    private static let symbolToCurrency: [(symbol: String, code: String)] = [
        // Multi-character symbols first (order matters for matching)
        ("HK$", "HKD"),
        ("NZ$", "NZD"),
        ("R$", "BRL"),
        ("C$", "CAD"),
        ("A$", "AUD"),
        ("S$", "SGD"),
        // Single-character currency symbols
        ("$", "USD"),
        ("€", "EUR"),
        ("£", "GBP"),
        ("¥", "JPY"),
        ("₹", "INR"),
        ("₩", "KRW"),
        ("₽", "RUB"),
        ("₺", "TRY"),
        ("₪", "ILS"),
        ("₦", "NGN"),
        ("₱", "PHP"),
        // Thai baht (not in regex patterns to avoid confusion with Bitcoin symbol)
        ("฿", "THB"),
        // Non-symbol text-based prefixes
        ("kr", "SEK"),
        ("zł", "PLN"),
        ("Fr", "CHF"),
    ]

    /// All recognized ISO 4217 currency codes.
    static let supportedCurrencyCodes: Set<String> = [
        "USD", "EUR", "GBP", "JPY", "CNY", "KRW", "INR", "RUB", "TRY",
        "BRL", "CAD", "AUD", "CHF", "SEK", "NOK", "DKK", "PLN", "THB",
        "MXN", "ZAR", "SGD", "HKD", "NZD", "ILS", "ARS", "NGN", "PHP",
        "CZK", "TWD", "SAR", "AED", "QAR", "KWD", "BHD", "OMR", "EGP",
        "MAD", "IDR", "MYR", "VND", "CLP", "COP", "PEN",
    ]

    /// Maps common currency names (including multilingual and slang) to ISO codes.
    private static let nameToCurrency: [String: String] = [
        // English names
        "dollar": "USD", "dollars": "USD", "usd": "USD",
        "buck": "USD", "bucks": "USD",
        "euro": "EUR", "euros": "EUR", "eur": "EUR",
        "pound": "GBP", "pounds": "GBP", "gbp": "GBP",
        "sterling": "GBP", "quid": "GBP",
        "yen": "JPY", "jpy": "JPY",
        "yuan": "CNY", "cny": "CNY", "renminbi": "CNY", "rmb": "CNY",
        "won": "KRW", "krw": "KRW",
        "rupee": "INR", "rupees": "INR", "inr": "INR",
        "ruble": "RUB", "rubles": "RUB", "rub": "RUB",
        "lira": "TRY", "try": "TRY",
        "real": "BRL", "reais": "BRL", "brl": "BRL",
        "franc": "CHF", "francs": "CHF", "chf": "CHF",
        "peso": "MXN", "pesos": "MXN", "mxn": "MXN",
        "rand": "ZAR", "zar": "ZAR",
        "shekel": "ILS", "shekels": "ILS", "ils": "ILS",
        "ringgit": "MYR", "myr": "MYR",
        "baht": "THB", "thb": "THB",
        "krona": "SEK", "kronor": "SEK", "sek": "SEK",
        "krone": "NOK", "nok": "NOK",
        "zloty": "PLN", "pln": "PLN",
        "cad": "CAD", "aud": "AUD",
        // Arabic
        "دولار": "USD", "دولارات": "USD",
        "يورو": "EUR",
        "جنيه": "GBP",
        "ين": "JPY",
        "ريال": "SAR", "ريالات": "SAR",
        "درهم": "AED", "دراهم": "AED",
        "دينار": "KWD",
        "جنيه مصري": "EGP",
        // Spanish
        "dólar": "USD", "dólares": "USD",
        "libra": "GBP", "libras": "GBP",
        "franco": "CHF", "francos": "CHF",
    ]

    // MARK: - Patterns

    /// Matches symbol-prefixed amounts: "$50", "€100.50", "£25", "¥1,000"
    /// Also handles multi-char symbols: "R$50", "C$100", "A$200", "HK$500"
    private let symbolPrefixPattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"(HK\$|NZ\$|R\$|C\$|A\$|S\$|[$€£¥₹₩₽₺₪₦₱]|zł|kr|Fr)\s*(\d[\d,]*(?:\.\d+)?|\.\d+)"#,
            options: []
        )
    }()

    /// Matches symbol-suffixed amounts: "100€", "50$", "30£"
    private let symbolSuffixPattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"(\d[\d,]*(?:\.\d+)?|\.\d+)\s*([$€£¥₹₩₽₺₪₦₱])"#,
            options: []
        )
    }()

    /// Matches code-suffixed amounts: "50 USD", "100 EUR", "1000 SAR"
    private let codeSuffixPattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"(\d[\d,]*(?:\.\d+)?|\.\d+)\s+([A-Z]{3})\b"#,
            options: [.caseInsensitive]
        )
    }()

    /// Matches name-suffixed amounts: "50 dollars", "100 euros", "50 bucks", "30 quid"
    private let nameSuffixPattern: NSRegularExpression = {
        let names = nameToCurrency.keys
            .sorted { $0.count > $1.count } // Longer names first for greedy match
            .joined(separator: "|")
        // swiftlint:disable:next force_try
        return try! NSRegularExpression(
            pattern: "(\(#"\d[\d,]*(?:\.\d+)?|\.\d+"#))\\s+(\(names))\\b",
            options: [.caseInsensitive]
        )
    }()

    /// Matches contextual currency references: "in USD", "to euros", "in dollars"
    private let contextPattern: NSRegularExpression = {
        let names = nameToCurrency.keys
            .sorted { $0.count > $1.count }
            .joined(separator: "|")
        // swiftlint:disable:next force_try
        return try! NSRegularExpression(
            pattern: "(?:in|to|as)\\s+([A-Z]{3}|\(names))\\b",
            options: [.caseInsensitive]
        )
    }()

    // MARK: - Text Normalization

    /// Normalizes smart quotes, dashes, and whitespace for consistent parsing.
    private func normalizeText(_ text: String) -> String {
        var s = text
        s = s.replacingOccurrences(of: "\u{2018}", with: "'")
        s = s.replacingOccurrences(of: "\u{2019}", with: "'")
        s = s.replacingOccurrences(of: "\u{201C}", with: "\"")
        s = s.replacingOccurrences(of: "\u{201D}", with: "\"")
        s = s.replacingOccurrences(of: "\u{2014}", with: "-")
        s = s.replacingOccurrences(of: "\u{2013}", with: "-")
        s = s.replacingOccurrences(of: "\u{00A0}", with: " ")
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Strips commas from number strings: "1,000" -> "1000"
    private func stripCommas(_ text: String) -> String {
        return text.replacingOccurrences(of: ",", with: "")
    }

    // MARK: - Public API

    /// Attempts to parse a fiat currency amount from the given text.
    ///
    /// Checks patterns in order: symbol-prefix, symbol-suffix, code-suffix, name-suffix.
    /// Returns the first match found.
    ///
    /// - Parameter text: The raw user input text.
    /// - Returns: A `FiatAmount` if a fiat amount was detected, `nil` otherwise.
    func parseFiatAmount(from text: String) -> FiatAmount? {
        let normalized = normalizeText(text)

        // 1. Symbol-prefix: "$50", "€100", "HK$500"
        if let result = matchSymbolPrefix(in: normalized) {
            return result
        }

        // 2. Symbol-suffix: "100€", "50$"
        if let result = matchSymbolSuffix(in: normalized) {
            return result
        }

        // 3. Code-suffix: "50 USD", "100 EUR"
        if let result = matchCodeSuffix(in: normalized) {
            return result
        }

        // 4. Name-suffix: "50 dollars", "100 euros", "30 quid"
        if let result = matchNameSuffix(in: normalized) {
            return result
        }

        return nil
    }

    /// Attempts to extract just the currency code from contextual phrases.
    ///
    /// Matches "in USD", "to euros", "in dollars", "to gbp", etc.
    ///
    /// - Parameter text: The raw user input text.
    /// - Returns: An ISO 4217 currency code if found, `nil` otherwise.
    func parseCurrencyFromContext(from text: String) -> String? {
        let normalized = normalizeText(text)
        let nsText = normalized as NSString
        let range = NSRange(location: 0, length: nsText.length)

        guard let match = contextPattern.firstMatch(in: normalized, options: [], range: range) else {
            return nil
        }

        guard match.range(at: 1).location != NSNotFound else { return nil }
        let currencyText = nsText.substring(with: match.range(at: 1))

        // Try as ISO code
        let upper = currencyText.uppercased()
        if Self.supportedCurrencyCodes.contains(upper) {
            return upper
        }

        // Try as name/slang
        let lower = currencyText.lowercased()
        return Self.nameToCurrency[lower]
    }

    /// Returns the currency symbol for a given ISO currency code.
    static func symbol(for code: String) -> String {
        let upper = code.uppercased()
        for entry in symbolToCurrency {
            if entry.code == upper {
                return entry.symbol
            }
        }
        return upper
    }

    /// Resolves a currency name or code to its ISO 4217 code.
    ///
    /// Accepts ISO codes ("USD"), names ("dollars"), and slang ("bucks", "quid").
    ///
    /// - Parameter input: The currency identifier to resolve.
    /// - Returns: The ISO 4217 code if recognized, `nil` otherwise.
    static func resolveCurrencyCode(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try as ISO code
        let upper = trimmed.uppercased()
        if supportedCurrencyCodes.contains(upper) {
            return upper
        }

        // Try as name/slang
        let lower = trimmed.lowercased()
        return nameToCurrency[lower]
    }

    // MARK: - Pattern Matching

    private func matchSymbolPrefix(in text: String) -> FiatAmount? {
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)

        guard let match = symbolPrefixPattern.firstMatch(in: text, options: [], range: range) else {
            return nil
        }

        guard match.range(at: 1).location != NSNotFound,
              match.range(at: 2).location != NSNotFound else {
            return nil
        }

        let symbol = nsText.substring(with: match.range(at: 1))
        let rawNumber = nsText.substring(with: match.range(at: 2))
        let numberStr = stripCommas(rawNumber)

        guard let amount = Decimal(string: numberStr), amount > 0 else { return nil }

        // Resolve symbol to currency code
        let code = Self.symbolToCurrency.first { $0.symbol == symbol }?.code ?? "USD"

        return FiatAmount(amount: amount, currencyCode: code, currencySymbol: symbol)
    }

    private func matchSymbolSuffix(in text: String) -> FiatAmount? {
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)

        guard let match = symbolSuffixPattern.firstMatch(in: text, options: [], range: range) else {
            return nil
        }

        guard match.range(at: 1).location != NSNotFound,
              match.range(at: 2).location != NSNotFound else {
            return nil
        }

        let rawNumber = nsText.substring(with: match.range(at: 1))
        let numberStr = stripCommas(rawNumber)
        let symbol = nsText.substring(with: match.range(at: 2))

        guard let amount = Decimal(string: numberStr), amount > 0 else { return nil }

        let code = Self.symbolToCurrency.first { $0.symbol == symbol }?.code ?? "USD"

        return FiatAmount(amount: amount, currencyCode: code, currencySymbol: symbol)
    }

    private func matchCodeSuffix(in text: String) -> FiatAmount? {
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)

        guard let match = codeSuffixPattern.firstMatch(in: text, options: [], range: range) else {
            return nil
        }

        guard match.range(at: 1).location != NSNotFound,
              match.range(at: 2).location != NSNotFound else {
            return nil
        }

        let rawNumber = nsText.substring(with: match.range(at: 1))
        let numberStr = stripCommas(rawNumber)
        let code = nsText.substring(with: match.range(at: 2)).uppercased()

        guard let amount = Decimal(string: numberStr), amount > 0 else { return nil }

        // Verify it's a known currency code (not BTC/SAT/etc.)
        guard Self.supportedCurrencyCodes.contains(code) else { return nil }

        return FiatAmount(amount: amount, currencyCode: code, currencySymbol: Self.symbol(for: code))
    }

    private func matchNameSuffix(in text: String) -> FiatAmount? {
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)

        guard let match = nameSuffixPattern.firstMatch(in: text, options: [], range: range) else {
            return nil
        }

        guard match.range(at: 1).location != NSNotFound,
              match.range(at: 2).location != NSNotFound else {
            return nil
        }

        let rawNumber = nsText.substring(with: match.range(at: 1))
        let numberStr = stripCommas(rawNumber)
        let name = nsText.substring(with: match.range(at: 2)).lowercased()

        guard let amount = Decimal(string: numberStr), amount > 0 else { return nil }

        guard let code = Self.nameToCurrency[name] else { return nil }

        return FiatAmount(amount: amount, currencyCode: code, currencySymbol: Self.symbol(for: code))
    }
}
