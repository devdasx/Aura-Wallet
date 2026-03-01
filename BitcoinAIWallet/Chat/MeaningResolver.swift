// MARK: - MeaningResolver.swift
// Bitcoin AI Wallet
//
// Maps SentenceMeaning -> ClassificationResult -> WalletIntent.
// Bridges language analysis to the existing intent system.
//
// Every ResolvedAction + ResolvedObject combination maps to the correct
// WalletIntent with appropriate confidence scoring:
//   - Direct matches (exact action+object): 0.9+
//   - Inferred matches (action only, object guessed): 0.7-0.85
//   - Weak matches (only object, no action): 0.5-0.65
//   - Unknown: 0.2
//
// Platform: iOS 17.0+

import Foundation

// MARK: - MeaningResolver

final class MeaningResolver {

    @MainActor
    func resolve(_ meaning: SentenceMeaning, memory: ConversationMemory, entityExtractor: EntityExtractor, input: String) -> ClassificationResult {

        // Emotion-only -> greeting/social
        if meaning.type == .emotional {
            return ClassificationResult(intent: .greeting, confidence: 0.8, needsClarification: false, alternatives: [], meaning: meaning)
        }

        // Evaluation -> pass through with meaning
        if meaning.type == .evaluation {
            return resolveEvaluation(meaning, memory: memory)
        }

        // Navigation
        if meaning.type == .navigation {
            return resolveNavigation(meaning, memory: memory)
        }

        guard let action = meaning.action else {
            // No action detected. Check if the object alone can infer an intent (weak match).
            if let object = meaning.object {
                return resolveObjectOnly(object, meaning: meaning, input: input, entityExtractor: entityExtractor)
            }
            return ClassificationResult(intent: .unknown(rawText: input), confidence: meaning.confidence, needsClarification: true, alternatives: [], meaning: meaning)
        }

        switch action {

        // MARK: - Send

        case .send:
            if meaning.isNegated {
                return ClassificationResult(intent: .cancelAction, confidence: 0.8, needsClarification: false, alternatives: [], meaning: meaning)
            }
            if meaning.type == .question {
                return ClassificationResult(
                    intent: .help, confidence: 0.7, needsClarification: false,
                    alternatives: [IntentScore(intent: .send(amount: nil, unit: nil, address: nil, feeLevel: nil), confidence: 0.4, source: "question")],
                    meaning: meaning
                )
            }
            let e = entityExtractor.extract(from: input)
            // Safety net: if EntityExtractor missed a bare number, use the modifier from SentenceAnalyzer
            var amount = e.amount
            if amount == nil, let mod = meaning.modifier, case .specific(let n) = mod {
                amount = n
            }
            return ClassificationResult(
                intent: .send(amount: amount, unit: e.unit, address: e.address, feeLevel: e.feeLevel),
                confidence: meaning.confidence,
                needsClarification: false, alternatives: [], meaning: meaning
            )

        // MARK: - Receive

        case .receive:
            return ClassificationResult(intent: .receive, confidence: meaning.confidence, needsClarification: false, alternatives: [], meaning: meaning)

        // MARK: - Check Balance

        case .checkBalance:
            return ClassificationResult(intent: .balance, confidence: meaning.confidence, needsClarification: false, alternatives: [], meaning: meaning)

        // MARK: - Show Fees

        case .showFees:
            return ClassificationResult(intent: .feeEstimate, confidence: meaning.confidence, needsClarification: false, alternatives: [], meaning: meaning)

        // MARK: - Show Price

        case .showPrice:
            let detectedCurrency = extractCurrencyFromInput(input)
            return ClassificationResult(intent: .price(currency: detectedCurrency), confidence: meaning.confidence, needsClarification: false, alternatives: [], meaning: meaning)

        // MARK: - Show History

        case .showHistory:
            // Check if user pasted a txid -> transaction detail instead of history
            if let txid = entityExtractor.extractTxId(from: input) {
                return ClassificationResult(intent: .transactionDetail(txid: txid), confidence: meaning.confidence, needsClarification: false, alternatives: [], meaning: meaning)
            }
            let count = entityExtractor.extractCount(from: input)
            return ClassificationResult(intent: .history(count: count), confidence: meaning.confidence, needsClarification: false, alternatives: [], meaning: meaning)

        // MARK: - Show Address

        case .showAddress:
            return ClassificationResult(intent: .receive, confidence: meaning.confidence, needsClarification: false, alternatives: [], meaning: meaning)

        // MARK: - Show UTXOs

        case .showUTXO:
            return ClassificationResult(intent: .utxoList, confidence: meaning.confidence, needsClarification: false, alternatives: [], meaning: meaning)

        // MARK: - Show Health

        case .showHealth:
            return ClassificationResult(intent: .walletHealth, confidence: meaning.confidence, needsClarification: false, alternatives: [], meaning: meaning)

        // MARK: - Show Network

        case .showNetwork:
            return ClassificationResult(intent: .networkStatus, confidence: meaning.confidence, needsClarification: false, alternatives: [], meaning: meaning)

        // MARK: - Confirm

        case .confirm:
            return ClassificationResult(intent: .confirmAction, confidence: meaning.confidence, needsClarification: false, alternatives: [], meaning: meaning)

        // MARK: - Cancel / Undo

        case .cancel, .undo:
            return ClassificationResult(intent: .cancelAction, confidence: meaning.confidence, needsClarification: false, alternatives: [], meaning: meaning)

        // MARK: - Repeat Last

        case .repeatLast:
            if let last = memory.lastUserIntent {
                return ClassificationResult(intent: last, confidence: 0.8, needsClarification: false, alternatives: [], meaning: meaning)
            }
            return ClassificationResult(intent: .help, confidence: 0.5, needsClarification: true, alternatives: [], meaning: meaning)

        // MARK: - Explain

        case .explain:
            let topic = resolveExplainTopic(from: meaning, input: input)
            return ClassificationResult(intent: .explain(topic: topic), confidence: meaning.confidence, needsClarification: false, alternatives: [], meaning: meaning)

        // MARK: - Help

        case .help:
            return ClassificationResult(intent: .help, confidence: 0.9, needsClarification: false, alternatives: [], meaning: meaning)

        // MARK: - Export

        case .export:
            return ClassificationResult(intent: .exportHistory, confidence: 0.85, needsClarification: false, alternatives: [], meaning: meaning)

        // MARK: - Bump Fee

        case .bump:
            let txid = entityExtractor.extractTxId(from: input)
            return ClassificationResult(intent: .bumpFee(txid: txid), confidence: 0.8, needsClarification: false, alternatives: [], meaning: meaning)

        // MARK: - Refresh

        case .refresh:
            return ClassificationResult(intent: .refreshWallet, confidence: 0.85, needsClarification: false, alternatives: [], meaning: meaning)

        // MARK: - Hide Balance

        case .hide:
            return ClassificationResult(intent: .hideBalance, confidence: 0.85, needsClarification: false, alternatives: [], meaning: meaning)

        // MARK: - Show Balance (unhide)

        case .show:
            return ClassificationResult(intent: .showBalance, confidence: 0.85, needsClarification: false, alternatives: [], meaning: meaning)

        // MARK: - Generate New Address

        case .generate:
            return ClassificationResult(intent: .newAddress, confidence: 0.85, needsClarification: false, alternatives: [], meaning: meaning)

        // MARK: - Convert

        case .convert:
            return resolveConvert(meaning: meaning, entityExtractor: entityExtractor, input: input)

        // MARK: - Compare (affordability check)

        case .compare:
            return ClassificationResult(intent: .balance, confidence: 0.8, needsClarification: false, alternatives: [], meaning: meaning)

        // MARK: - Select (transaction from list)

        case .select(let idx):
            if let txs = memory.lastShownTransactions {
                let safeIdx = idx == -1 ? txs.count - 1 : min(idx, txs.count - 1)
                if safeIdx >= 0 && safeIdx < txs.count {
                    return ClassificationResult(intent: .transactionDetail(txid: txs[safeIdx].txid), confidence: 0.85, needsClarification: false, alternatives: [], meaning: meaning)
                }
            }
            return ClassificationResult(intent: .help, confidence: 0.4, needsClarification: true, alternatives: [], meaning: meaning)

        // MARK: - Modify (fee or amount adjustment)

        case .modify(let what):
            return resolveModify(what: what, meaning: meaning, memory: memory, entityExtractor: entityExtractor, input: input)

        // MARK: - Settings

        case .settings:
            return ClassificationResult(intent: .settings, confidence: 0.9, needsClarification: false, alternatives: [], meaning: meaning)

        // MARK: - About

        case .about:
            return ClassificationResult(intent: .about, confidence: 0.9, needsClarification: false, alternatives: [], meaning: meaning)

        // MARK: - Backup

        case .backup:
            return ClassificationResult(intent: .settings, confidence: 0.7, needsClarification: false, alternatives: [], meaning: meaning)
        }
    }

    // MARK: - Explain Topic Resolution

    /// Maps a SentenceMeaning's object to an explain topic string.
    /// Covers all Bitcoin concepts from the WordClassifier's BitcoinConcept enum
    /// plus additional educational topics detected from the raw input.
    private func resolveExplainTopic(from meaning: SentenceMeaning, input: String) -> String {
        // First try to resolve from the meaning's object
        if let object = meaning.object {
            switch object {
            case .balance:
                return "wallet"
            case .fee:
                return "fees"
            case .amount:
                return "transactions"
            case .address:
                return "addresses"
            case .transaction:
                return "transactions"
            case .price:
                return "bitcoin"
            case .wallet:
                return "wallet"
            case .network:
                return "network"
            case .history:
                return "transactions"
            case .utxo:
                return "utxo"
            case .specific(let topic):
                return topic.lowercased()
            case .lastMentioned:
                // Fall through to input-based detection
                break
            }
        }

        // Scan the raw input for topic keywords not captured by the object
        let lower = input.lowercased()
        let topicKeywords: [(keywords: [String], topic: String)] = [
            (["mining", "miner", "miners", "mine", "proof of work", "pow"], "mining"),
            (["halving", "halvening", "block reward"], "halving"),
            (["mempool", "memory pool", "mem pool"], "mempool"),
            (["segwit", "segregated witness", "bech32"], "segwit"),
            (["taproot", "schnorr", "bc1p"], "taproot"),
            (["lightning", "lightning network", "layer 2", "l2", "payment channel"], "lightning"),
            (["private key", "public key", "keys", "keypair", "key pair"], "keys"),
            (["address", "addresses", "receive address"], "addresses"),
            (["utxo", "utxos", "unspent"], "utxo"),
            (["blockchain", "block chain", "chain", "ledger", "blocks"], "blockchain"),
            (["transaction", "transactions", "tx", "txs"], "transactions"),
            (["fee", "fees", "sat/vb", "sat per byte", "gas"], "fees"),
            (["wallet", "wallets"], "wallet"),
            (["network", "node", "nodes", "peer"], "network"),
            (["bitcoin", "btc", "satoshi"], "bitcoin"),
            (["seed", "seed phrase", "mnemonic", "recovery phrase", "backup phrase"], "keys"),
            (["signature", "sign", "signing"], "keys"),
            (["confirmation", "confirmations", "confirmed", "unconfirmed"], "transactions"),
        ]

        for (keywords, topic) in topicKeywords {
            for keyword in keywords {
                if lower.contains(keyword) {
                    return topic
                }
            }
        }

        // Default fallback: general bitcoin explanation
        return "bitcoin"
    }

    // MARK: - Convert Resolution

    /// Resolves .convert action to either .convertAmount or .price depending
    /// on whether a fiat amount was detected.
    private func resolveConvert(meaning: SentenceMeaning, entityExtractor: EntityExtractor, input: String) -> ClassificationResult {
        // Try to extract a fiat amount for conversion: "$50", "100 EUR"
        let extracted = entityExtractor.extractAmount(from: input)
        if let extracted = extracted, let currency = extracted.currency {
            return ClassificationResult(
                intent: .convertAmount(amount: extracted.amount, fromCurrency: currency),
                confidence: meaning.confidence,
                needsClarification: false, alternatives: [], meaning: meaning
            )
        }

        // Check if there's a BTC amount to convert: "convert 0.5 BTC", "how much is 0.1 BTC"
        if let extracted = extracted, extracted.currency == nil {
            // User has a BTC amount, wants to know fiat value
            let detectedCurrency = extractCurrencyFromInput(input)
            return ClassificationResult(
                intent: .price(currency: detectedCurrency),
                confidence: 0.75,
                needsClarification: false, alternatives: [], meaning: meaning
            )
        }

        // Fallback: try to extract currency from input: "convert to EUR", "convert that to euros"
        let detectedCurrency = extractCurrencyFromInput(input)
        return ClassificationResult(
            intent: .price(currency: detectedCurrency),
            confidence: 0.7,
            needsClarification: false, alternatives: [], meaning: meaning
        )
    }

    // MARK: - Modify Resolution

    /// Resolves .modify(what:) into a contextual intent based on what is being modified
    /// and the current conversation state.
    @MainActor
    private func resolveModify(what: String, meaning: SentenceMeaning, memory: ConversationMemory, entityExtractor: EntityExtractor, input: String) -> ClassificationResult {
        let e = entityExtractor.extract(from: input)

        switch what {
        case "fee":
            // Fee modification: extract fee level from modifier or input
            var feeLevel = e.feeLevel
            if feeLevel == nil, let modifier = meaning.modifier {
                switch modifier {
                case .fastest:
                    feeLevel = .fast
                case .cheapest:
                    feeLevel = .slow
                case .middle:
                    feeLevel = .medium
                case .increase:
                    feeLevel = .fast
                case .decrease:
                    feeLevel = .slow
                default:
                    break
                }
            }

            // If we're in a send flow, modify the pending transaction's fee
            if memory.currentFlowState != .idle {
                // Return send with only feeLevel populated to signal fee adjustment
                return ClassificationResult(
                    intent: .send(amount: nil, unit: nil, address: nil, feeLevel: feeLevel ?? .medium),
                    confidence: 0.85,
                    needsClarification: false, alternatives: [], meaning: meaning
                )
            }

            // Not in a flow: show fee estimates
            return ClassificationResult(intent: .feeEstimate, confidence: 0.8, needsClarification: false, alternatives: [], meaning: meaning)

        case "amount":
            // Amount modification: extract new amount from input or modifier
            var amount = e.amount
            if amount == nil, let modifier = meaning.modifier, case .specific(let n) = modifier {
                amount = n
            }

            // If we're in a send flow, modify the pending transaction's amount
            if memory.currentFlowState != .idle {
                return ClassificationResult(
                    intent: .send(amount: amount, unit: e.unit, address: nil, feeLevel: nil),
                    confidence: 0.85,
                    needsClarification: false, alternatives: [], meaning: meaning
                )
            }

            // Not in a flow: generic send with amount
            return ClassificationResult(
                intent: .send(amount: amount, unit: e.unit, address: nil, feeLevel: nil),
                confidence: 0.7,
                needsClarification: amount == nil,
                alternatives: [], meaning: meaning
            )

        default:
            // Unknown modification target: treat as generic send adjustment
            return ClassificationResult(
                intent: .send(amount: nil, unit: nil, address: nil, feeLevel: nil),
                confidence: 0.6,
                needsClarification: true, alternatives: [], meaning: meaning
            )
        }
    }

    // MARK: - Object-Only Resolution (no action detected)

    /// When only an object is detected without an action, infer a weak-confidence intent.
    private func resolveObjectOnly(_ object: ResolvedObject, meaning: SentenceMeaning, input: String, entityExtractor: EntityExtractor) -> ClassificationResult {
        switch object {
        case .balance:
            return ClassificationResult(intent: .balance, confidence: 0.6, needsClarification: false, alternatives: [], meaning: meaning)
        case .fee:
            return ClassificationResult(intent: .feeEstimate, confidence: 0.6, needsClarification: false, alternatives: [], meaning: meaning)
        case .price:
            let currency = extractCurrencyFromInput(input)
            return ClassificationResult(intent: .price(currency: currency), confidence: 0.6, needsClarification: false, alternatives: [], meaning: meaning)
        case .transaction:
            if let txid = entityExtractor.extractTxId(from: input) {
                return ClassificationResult(intent: .transactionDetail(txid: txid), confidence: 0.65, needsClarification: false, alternatives: [], meaning: meaning)
            }
            return ClassificationResult(intent: .history(count: nil), confidence: 0.55, needsClarification: false, alternatives: [], meaning: meaning)
        case .history:
            return ClassificationResult(intent: .history(count: nil), confidence: 0.6, needsClarification: false, alternatives: [], meaning: meaning)
        case .address:
            return ClassificationResult(intent: .receive, confidence: 0.55, needsClarification: false, alternatives: [], meaning: meaning)
        case .wallet:
            return ClassificationResult(intent: .balance, confidence: 0.55, needsClarification: false, alternatives: [], meaning: meaning)
        case .network:
            return ClassificationResult(intent: .networkStatus, confidence: 0.55, needsClarification: false, alternatives: [], meaning: meaning)
        case .utxo:
            return ClassificationResult(intent: .utxoList, confidence: 0.6, needsClarification: false, alternatives: [], meaning: meaning)
        case .amount:
            return ClassificationResult(intent: .balance, confidence: 0.5, needsClarification: true, alternatives: [], meaning: meaning)
        case .specific(let topic):
            return ClassificationResult(intent: .explain(topic: topic), confidence: 0.55, needsClarification: false, alternatives: [], meaning: meaning)
        case .lastMentioned:
            return ClassificationResult(intent: .unknown(rawText: input), confidence: 0.3, needsClarification: true, alternatives: [], meaning: meaning)
        }
    }

    // MARK: - Evaluation Resolution

    @MainActor
    private func resolveEvaluation(_ meaning: SentenceMeaning, memory: ConversationMemory) -> ClassificationResult {
        guard let modifier = meaning.modifier else {
            return ClassificationResult(intent: .unknown(rawText: ""), confidence: 0.3, needsClarification: true, alternatives: [], meaning: meaning)
        }
        switch modifier {
        case .enough:
            return ClassificationResult(intent: .confirmAction, confidence: 0.7, needsClarification: false, alternatives: [], meaning: meaning)
        case .tooMuch:
            if memory.lastShownFeeEstimates != nil {
                return ClassificationResult(intent: .feeEstimate, confidence: 0.8, needsClarification: false, alternatives: [], meaning: meaning)
            }
            return ClassificationResult(intent: .balance, confidence: 0.6, needsClarification: true, alternatives: [], meaning: meaning)
        case .tooLittle, .notEnough:
            return ClassificationResult(intent: .balance, confidence: 0.6, needsClarification: true, alternatives: [], meaning: meaning)
        default:
            return ClassificationResult(intent: .unknown(rawText: ""), confidence: 0.3, needsClarification: true, alternatives: [], meaning: meaning)
        }
    }

    // MARK: - Navigation Resolution

    @MainActor
    private func resolveNavigation(_ meaning: SentenceMeaning, memory: ConversationMemory) -> ClassificationResult {
        guard let action = meaning.action else {
            return ClassificationResult(intent: .help, confidence: 0.4, needsClarification: true, alternatives: [], meaning: meaning)
        }
        switch action {
        case .undo:
            return ClassificationResult(intent: .cancelAction, confidence: 0.8, needsClarification: false, alternatives: [], meaning: meaning)
        case .repeatLast:
            if let last = memory.lastUserIntent {
                return ClassificationResult(intent: last, confidence: 0.8, needsClarification: false, alternatives: [], meaning: meaning)
            }
            return ClassificationResult(intent: .help, confidence: 0.5, needsClarification: true, alternatives: [], meaning: meaning)
        case .select(let idx):
            if let txs = memory.lastShownTransactions {
                let safeIdx = idx == -1 ? txs.count - 1 : min(idx, txs.count - 1)
                if safeIdx >= 0 && safeIdx < txs.count {
                    return ClassificationResult(intent: .transactionDetail(txid: txs[safeIdx].txid), confidence: 0.85, needsClarification: false, alternatives: [], meaning: meaning)
                }
            }
            return ClassificationResult(intent: .help, confidence: 0.4, needsClarification: true, alternatives: [], meaning: meaning)
        default:
            return ClassificationResult(intent: .help, confidence: 0.4, needsClarification: true, alternatives: [], meaning: meaning)
        }
    }

    // MARK: - Currency Extraction

    /// Extracts a fiat currency code from input text.
    /// Checks symbols first, then word-based currency names.
    /// Supports USD, EUR, GBP, JPY, CAD, AUD, CHF, SEK, NOK, DKK, NZD, SGD, HKD, KRW, INR, BRL, MXN, ZAR, TRY, RUB.
    private func extractCurrencyFromInput(_ input: String) -> String? {
        let lower = input.lowercased()

        // Check currency symbols first
        let symbolMap: [(Character, String)] = [
            ("$", "USD"), ("\u{20AC}", "EUR"), ("\u{00A3}", "GBP"), ("\u{00A5}", "JPY"),
            ("\u{20B9}", "INR"), ("\u{20A9}", "KRW"), ("\u{20BD}", "RUB"),
        ]
        for (symbol, code) in symbolMap {
            if lower.contains(String(symbol)) { return code }
        }

        // Word-based currency detection (ordered from most specific to least to avoid false positives)
        let currencyMap: [(String, String)] = [
            // USD
            ("dollars", "USD"), ("dollar", "USD"), ("bucks", "USD"), ("usd", "USD"),
            // EUR
            ("euros", "EUR"), ("euro", "EUR"), ("eur", "EUR"),
            // GBP
            ("pounds", "GBP"), ("pound", "GBP"), ("sterling", "GBP"), ("gbp", "GBP"), ("quid", "GBP"),
            // JPY
            ("yen", "JPY"), ("jpy", "JPY"),
            // CAD
            ("canadian", "CAD"), ("cad", "CAD"),
            // AUD
            ("australian", "AUD"), ("aud", "AUD"),
            // CHF
            ("swiss franc", "CHF"), ("francs", "CHF"), ("franc", "CHF"), ("chf", "CHF"),
            // Others
            ("kroner", "SEK"), ("kronor", "SEK"), ("sek", "SEK"),
            ("nok", "NOK"),
            ("dkk", "DKK"),
            ("nzd", "NZD"),
            ("sgd", "SGD"),
            ("hkd", "HKD"),
            ("won", "KRW"), ("krw", "KRW"),
            ("rupee", "INR"), ("rupees", "INR"), ("inr", "INR"),
            ("real", "BRL"), ("reais", "BRL"), ("brl", "BRL"),
            ("peso", "MXN"), ("pesos", "MXN"), ("mxn", "MXN"),
            ("rand", "ZAR"), ("zar", "ZAR"),
            ("lira", "TRY"), ("try", "TRY"),
            ("ruble", "RUB"), ("rubles", "RUB"), ("rub", "RUB"),
        ]
        for (keyword, code) in currencyMap {
            // Use word boundary check to avoid false positives (e.g., "try" inside "country")
            if matchesWordBoundary(keyword, in: lower) {
                return code
            }
        }
        return nil
    }

    /// Checks if a keyword appears at a word boundary in the text.
    /// Prevents false matches like "try" in "country".
    private func matchesWordBoundary(_ keyword: String, in text: String) -> Bool {
        guard let range = text.range(of: keyword) else { return false }

        // Check character before the match (if any) is a word boundary
        if range.lowerBound != text.startIndex {
            let charBefore = text[text.index(before: range.lowerBound)]
            if charBefore.isLetter || charBefore.isNumber { return false }
        }

        // Check character after the match (if any) is a word boundary
        if range.upperBound != text.endIndex {
            let charAfter = text[range.upperBound]
            if charAfter.isLetter || charAfter.isNumber { return false }
        }

        return true
    }
}
