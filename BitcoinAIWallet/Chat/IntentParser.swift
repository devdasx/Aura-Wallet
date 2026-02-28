// MARK: - IntentParser.swift
// Bitcoin AI Wallet
//
// Parses natural language user input into structured wallet intents.
// Uses regex and keyword matching — NO AI/LLM API calls.
// Supports English, Arabic, and Spanish with typo tolerance.
//
// Priority order:
// 1. Confirm / Cancel (stateful)
// 2. Greeting
// 3. Send (most complex)
// 4. Price / Convert
// 5. Receive / New Address
// 6. Hide / Show balance
// 7. Refresh
// 8. Balance
// 9. History / Export
// 10. Fee / Bump Fee
// 11. Wallet Health / UTXO / Network Status
// 12. Transaction detail (by txid)
// 13. Settings / About
// 14. Help
// 15. Fallback — bare addresses/amounts as implicit send
// 16. Smart fallback — never say "unknown command"
//
// Platform: iOS 17.0+
// Framework: Foundation

import Foundation

// MARK: - IntentParser

/// Parses user input text into structured `WalletIntent` values.
final class IntentParser {

    // MARK: - Dependencies

    private let patternMatcher: PatternMatcher
    private let entityExtractor: EntityExtractor
    private let addressValidator: AddressValidator
    private let currencyParser: CurrencyParser

    // MARK: - Initialization

    init() {
        self.patternMatcher = PatternMatcher()
        self.entityExtractor = EntityExtractor()
        self.addressValidator = AddressValidator()
        self.currencyParser = CurrencyParser()
    }

    init(patternMatcher: PatternMatcher, entityExtractor: EntityExtractor, addressValidator: AddressValidator) {
        self.patternMatcher = patternMatcher
        self.entityExtractor = entityExtractor
        self.addressValidator = addressValidator
        self.currencyParser = CurrencyParser()
    }

    // MARK: - Public API

    /// Parses user input text into a structured `WalletIntent`.
    func parse(_ input: String) -> WalletIntent {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .unknown(rawText: input)
        }

        let normalized = trimmed.lowercased()

        // 1. Confirm / Cancel — stateful, highest priority
        if patternMatcher.isConfirmation(normalized) {
            return .confirmAction
        }
        if patternMatcher.isCancellation(normalized) {
            return .cancelAction
        }

        // 2. Greeting
        if patternMatcher.isGreeting(normalized) {
            return .greeting
        }

        // 3. Send intent
        if patternMatcher.isSendIntent(normalized) {
            return buildSendIntent(from: trimmed)
        }

        // 4. Price / Convert
        if patternMatcher.isPriceIntent(normalized) {
            // Check if there's a specific currency mentioned
            if let fiat = currencyParser.parseFiatAmount(from: trimmed) {
                return .convertAmount(amount: fiat.amount, fromCurrency: fiat.currencyCode)
            }
            let currency = extractCurrencyCode(from: normalized)
            return .price(currency: currency)
        }

        // Check for fiat currency amounts — implicit conversion
        if let fiat = currencyParser.parseFiatAmount(from: trimmed) {
            // If the text also has a send keyword or address, it's a send in fiat
            if patternMatcher.isSendIntent(normalized) {
                return buildSendIntent(from: trimmed)
            }
            return .convertAmount(amount: fiat.amount, fromCurrency: fiat.currencyCode)
        }

        // 5a. New Address (before generic receive)
        if patternMatcher.isNewAddressIntent(normalized) {
            return .newAddress
        }

        // 5b. Receive intent
        if patternMatcher.isReceiveIntent(normalized) {
            return .receive
        }

        // 6a. Hide balance
        if patternMatcher.isHideBalanceIntent(normalized) {
            return .hideBalance
        }

        // 6b. Show balance (unhide)
        if patternMatcher.isShowBalanceIntent(normalized) {
            return .showBalance
        }

        // 7. Refresh/sync
        if patternMatcher.isRefreshIntent(normalized) {
            return .refreshWallet
        }

        // 8. Balance inquiry
        if patternMatcher.isBalanceIntent(normalized) {
            return .balance
        }

        // 9a. Export history
        if patternMatcher.isExportIntent(normalized) {
            return .exportHistory
        }

        // 9b. Transaction history
        if patternMatcher.isHistoryIntent(normalized) {
            let count = entityExtractor.extractCount(from: normalized)
            return .history(count: count)
        }

        // 10a. Bump fee / RBF
        if patternMatcher.isBumpFeeIntent(normalized) {
            let txid = entityExtractor.extractTxId(from: trimmed)
            return .bumpFee(txid: txid)
        }

        // 10b. Fee estimate
        if patternMatcher.isFeeIntent(normalized) {
            return .feeEstimate
        }

        // 11a. Wallet health
        if patternMatcher.isWalletHealthIntent(normalized) {
            return .walletHealth
        }

        // 11b. UTXO list
        if patternMatcher.isUTXOIntent(normalized) {
            return .utxoList
        }

        // 11c. Network status
        if patternMatcher.isNetworkStatusIntent(normalized) {
            return .networkStatus
        }

        // 12. Transaction detail — bare txid
        if let txid = entityExtractor.extractTxId(from: trimmed) {
            return .transactionDetail(txid: txid)
        }

        // 13a. About
        if patternMatcher.isAboutIntent(normalized) {
            return .about
        }

        // 13b. Settings
        if patternMatcher.isSettingsIntent(normalized) {
            return .settings
        }

        // 14. Help
        if patternMatcher.isHelpIntent(normalized) {
            return .help
        }

        // 15. Fallback — bare address or amount implies send
        let fallbackEntities = entityExtractor.extract(from: trimmed)
        if let address = fallbackEntities.address, addressValidator.isValid(address) {
            return .send(
                amount: fallbackEntities.amount,
                unit: fallbackEntities.unit,
                address: address,
                feeLevel: fallbackEntities.feeLevel
            )
        }

        // 16. Smart fallback — never say "unknown command"
        // Instead, try to be helpful based on what we can detect
        return .unknown(rawText: input)
    }

    // MARK: - Private Helpers

    /// Builds a `.send` intent by extracting all relevant entities from the input.
    private func buildSendIntent(from originalInput: String) -> WalletIntent {
        let entities = entityExtractor.extract(from: originalInput)

        let validatedAddress: String?
        if let address = entities.address {
            validatedAddress = addressValidator.isValid(address) ? address : nil
        } else {
            validatedAddress = nil
        }

        return .send(
            amount: entities.amount,
            unit: entities.unit,
            address: validatedAddress,
            feeLevel: entities.feeLevel
        )
    }

    /// Extracts a currency code from text (e.g., "price in EUR" -> "EUR").
    private func extractCurrencyCode(from text: String) -> String? {
        let codePattern = try? NSRegularExpression(
            pattern: #"\bin\s+([A-Z]{3})\b"#,
            options: [.caseInsensitive]
        )
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)

        if let match = codePattern?.firstMatch(in: text, options: [], range: range),
           match.range(at: 1).location != NSNotFound {
            let code = nsText.substring(with: match.range(at: 1)).uppercased()
            if CurrencyParser.supportedCurrencyCodes.contains(code) {
                return code
            }
        }
        return nil
    }
}
