// MARK: - CurrencyParser.swift
// Bitcoin AI Wallet
//
// Detects and parses amounts in any world currency from natural language text.
// Supports symbol-prefix (e.g. "$50"), code-suffix (e.g. "100 EUR"),
// and Arabic/Spanish currency names.
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
/// - Symbol-prefixed: "$50", "€100", "£25", "¥1000"
/// - Code-suffixed: "50 USD", "100 EUR", "1000 SAR"
/// - Named: "50 dollars", "100 euros", "50 ريال"
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
    private static let symbolToCurrency: [(symbol: String, code: String)] = [
        ("$", "USD"),
        ("€", "EUR"),
        ("£", "GBP"),
        ("¥", "JPY"),
        ("₹", "INR"),
        ("₩", "KRW"),
        ("₽", "RUB"),
        ("₺", "TRY"),
        ("R$", "BRL"),
        ("C$", "CAD"),
        ("A$", "AUD"),
        ("HK$", "HKD"),
        ("S$", "SGD"),
        ("NZ$", "NZD"),
        ("₪", "ILS"),
        ("₦", "NGN"),
        ("₱", "PHP"),
        ("kr", "SEK"),
        ("zł", "PLN"),
        ("฿", "THB"),
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

    /// Maps common currency names (including multilingual) to ISO codes.
    private static let nameToCurrency: [String: String] = [
        // English
        "dollar": "USD", "dollars": "USD", "usd": "USD",
        "euro": "EUR", "euros": "EUR", "eur": "EUR",
        "pound": "GBP", "pounds": "GBP", "gbp": "GBP", "sterling": "GBP",
        "yen": "JPY", "jpy": "JPY",
        "yuan": "CNY", "cny": "CNY", "renminbi": "CNY", "rmb": "CNY",
        "won": "KRW", "krw": "KRW",
        "rupee": "INR", "rupees": "INR", "inr": "INR",
        "ruble": "RUB", "rubles": "RUB", "rub": "RUB",
        "lira": "TRY", "try": "TRY",
        "real": "BRL", "reais": "BRL", "brl": "BRL",
        "franc": "CHF", "francs": "CHF", "chf": "CHF",
        "peso": "MXN", "pesos": "MXN",
        "rand": "ZAR", "zar": "ZAR",
        "shekel": "ILS", "shekels": "ILS", "ils": "ILS",
        "ringgit": "MYR", "myr": "MYR",
        "baht": "THB", "thb": "THB",
        "krona": "SEK", "kronor": "SEK",
        "krone": "NOK",
        "zloty": "PLN", "pln": "PLN",
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

    /// Matches symbol-prefixed amounts: "$50", "€100.50", "£25"
    private let symbolPrefixPattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"([$€£¥₹₩₽₺₪₦₱]|R\$|C\$|A\$|HK\$|S\$|NZ\$|zł|kr|Fr)\s*(\d+(?:[.,]\d+)?)"#,
            options: []
        )
    }()

    /// Matches code-suffixed amounts: "50 USD", "100 EUR", "1000 SAR"
    private let codeSuffixPattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"(\d+(?:[.,]\d+)?)\s*([A-Z]{3})\b"#,
            options: [.caseInsensitive]
        )
    }()

    /// Matches name-suffixed amounts: "50 dollars", "100 euros", "50 ريال"
    private let nameSuffixPattern: NSRegularExpression = {
        let names = nameToCurrency.keys.joined(separator: "|")
        // swiftlint:disable:next force_try
        return try! NSRegularExpression(
            pattern: "(\(#"\d+(?:[.,]\d+)?"#))\\s*(\(names))",
            options: [.caseInsensitive]
        )
    }()

    // MARK: - Public API

    /// Attempts to parse a fiat currency amount from the given text.
    ///
    /// Checks patterns in order: symbol-prefix, code-suffix, name-suffix.
    /// Returns the first match found.
    ///
    /// - Parameter text: The raw user input text.
    /// - Returns: A `FiatAmount` if a fiat amount was detected, `nil` otherwise.
    func parseFiatAmount(from text: String) -> FiatAmount? {
        // 1. Symbol-prefix: "$50", "€100"
        if let result = matchSymbolPrefix(in: text) {
            return result
        }

        // 2. Code-suffix: "50 USD", "100 EUR"
        if let result = matchCodeSuffix(in: text) {
            return result
        }

        // 3. Name-suffix: "50 dollars", "100 euros"
        if let result = matchNameSuffix(in: text) {
            return result
        }

        return nil
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
        let numberStr = nsText.substring(with: match.range(at: 2)).replacingOccurrences(of: ",", with: ".")

        guard let amount = Decimal(string: numberStr), amount > 0 else { return nil }

        // Resolve symbol to currency code
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

        let numberStr = nsText.substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: ".")
        let code = nsText.substring(with: match.range(at: 2)).uppercased()

        guard let amount = Decimal(string: numberStr), amount > 0 else { return nil }

        // Verify it's a known currency code, not BTC/SAT
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

        let numberStr = nsText.substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: ".")
        let name = nsText.substring(with: match.range(at: 2)).lowercased()

        guard let amount = Decimal(string: numberStr), amount > 0 else { return nil }

        guard let code = Self.nameToCurrency[name] else { return nil }

        return FiatAmount(amount: amount, currencyCode: code, currencySymbol: Self.symbol(for: code))
    }
}
