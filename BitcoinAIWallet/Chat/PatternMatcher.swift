// MARK: - PatternMatcher.swift
// Bitcoin AI Wallet
//
// Regex and keyword pattern matching for intent classification.
// Supports English, Arabic, Spanish, and French triggers with typo tolerance.
// Classifies user input into wallet operation categories.
//
// Platform: iOS 17.0+
// Framework: Foundation

import Foundation

// MARK: - PatternMatcher

/// Classifies normalized user input into intent categories.
///
/// Supports:
/// - English, Arabic, Spanish, and French keyword triggers
/// - Regex patterns for complex sentence structures
/// - Levenshtein-distance typo tolerance for single-word commands
/// - Emoji shortcut detection
final class PatternMatcher {

    // MARK: - Typo Tolerance

    /// Maximum Levenshtein distance for fuzzy keyword matching.
    /// Uses 1 for short words (<=5 chars), 2 for longer words.
    private func maxDistance(for keyword: String) -> Int {
        keyword.count <= 5 ? 1 : 2
    }

    /// Computes Levenshtein edit distance between two strings.
    private func levenshteinDistance(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        let m = aChars.count
        let n = bChars.count

        if m == 0 { return n }
        if n == 0 { return m }

        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 0...m { dp[i][0] = i }
        for j in 0...n { dp[0][j] = j }

        for i in 1...m {
            for j in 1...n {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                dp[i][j] = min(dp[i - 1][j] + 1, dp[i][j - 1] + 1, dp[i - 1][j - 1] + cost)
            }
        }
        return dp[m][n]
    }

    /// Checks if a word approximately matches any keyword (within dynamic max distance).
    private func fuzzyContains(_ text: String, keywords: [String]) -> Bool {
        let words = text.split(separator: " ").map { String($0) }
        for word in words {
            for keyword in keywords {
                // Skip very short keywords (1-2 chars) for fuzzy matching
                if keyword.count <= 2 {
                    if word == keyword { return true }
                    continue
                }
                if levenshteinDistance(word, keyword) <= maxDistance(for: keyword) {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Helper

    /// Checks if text contains any keyword from the list (exact substring).
    private func containsAny(_ text: String, keywords: [String]) -> Bool {
        for keyword in keywords {
            if text.contains(keyword) { return true }
        }
        return false
    }

    /// Checks if a word appears with word boundaries.
    private func containsWord(_ text: String, word: String) -> Bool {
        guard let regex = try? NSRegularExpression(
            pattern: "\\b\(NSRegularExpression.escapedPattern(for: word))\\b",
            options: [.caseInsensitive]
        ) else {
            return text.contains(word)
        }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    /// Checks text against regex patterns.
    private func matchesAny(_ text: String, patterns: [NSRegularExpression]) -> Bool {
        let range = NSRange(location: 0, length: (text as NSString).length)
        for pattern in patterns {
            if pattern.firstMatch(in: text, options: [], range: range) != nil {
                return true
            }
        }
        return false
    }

    // MARK: - Greeting Intent

    private let greetingKeywords: [String] = [
        // English
        "hello", "hi", "hey", "good morning", "good afternoon", "good evening",
        "howdy", "sup", "what's up", "whats up", "yo",
        "heya", "g'day", "greetings", "gm", "gn",
        "what's good", "whats good", "what's happening", "whats happening",
        "how's it going", "hows it going", "how ya doing", "how you doing",
        "hey hey", "yo yo",
        // Arabic
        "مرحبا", "سلام", "اهلا", "أهلا", "صباح الخير", "مساء الخير",
        // Spanish
        "hola", "buenos días", "buenas tardes", "buenas noches", "qué tal",
        // French
        "bonjour", "bonsoir", "salut", "coucou", "bonne journ\u{00E9}e",
    ]

    /// Emoji greetings
    private let greetingEmojis: [String] = ["👋", "🙋", "🙋‍♂️", "🙋‍♀️"]

    func isGreeting(_ text: String) -> Bool {
        // Exact match for short greetings
        if greetingKeywords.contains(text) { return true }
        // Starts with greeting
        for kw in greetingKeywords where text.hasPrefix(kw + " ") || text.hasPrefix(kw + "!") {
            return true
        }
        // Emoji
        for emoji in greetingEmojis where text.contains(emoji) { return true }
        return false
    }

    // MARK: - Send Intent

    private let sendKeywords: [String] = [
        // English
        "send", "transfer", "pay", "withdraw", "forward",
        "wire", "dispatch", "remit", "zap",
        // Arabic
        "ارسل", "أرسل", "حول", "ادفع", "ارسال", "تحويل", "دفع",
        // Spanish
        "enviar", "envía", "envia", "transferir", "pagar", "mandar",
        // French
        "envoyer", "transf\u{00E9}rer", "transferer", "payer",
    ]

    private let sendPatterns: [NSRegularExpression] = {
        let patterns = [
            #"\bsend\s+[\d.]+\s*(?:btc|sats?|satoshis?|bitcoin)?\s*(?:to\s+)?\S+"#,
            #"\bsend\s+[\d.]+\s+(?:btc|sats?|satoshis?|bitcoin)\s+to\s+\S+"#,
            #"\btransfer\s+[\d.]+\s*(?:btc|sats?|satoshis?|bitcoin)?\s*(?:to\s+)?\S+"#,
            #"\bpay\s+(?:bc1|tb1|[13mn2])\S+\s+[\d.]+"#,
            #"\bpay\s+[\d.]+\s*(?:btc|sats?|satoshis?|bitcoin)?\s*(?:to\s+)?\S+"#,
            #"\bmove\s+[\d.]+\s*(?:btc|sats?|satoshis?|bitcoin)?\s*(?:to\s+)?\S+"#,
            #"\bsend\s+(?:all|max|everything)\s+(?:to\s+)?\S+"#,
            #"\bsend\s+to\s+(?:bc1|tb1|[13mn2])\S+"#,
            #"\bi\s+want\s+to\s+send\b"#,
            #"\bi'?d\s+like\s+to\s+send\b"#,
            #"\blet\s+me\s+send\b"#,
            #"\bcan\s+i\s+send\b"#,
            #"\bsend\s+(?:btc|bitcoin|sats?|satoshis?)\b"#,
            #"\btransfer\s+(?:btc|bitcoin|sats?|satoshis?)\b"#,
            #"\bmove\s+(?:btc|bitcoin|sats?|satoshis?)\b"#,
            #"\bsend\s+.*\s+to\b"#,
            #"\btransfer\s+.*\s+to\b"#,
            #"\bpay\s+.*\s+to\b"#,
            #"\bpush\s+.*\s+to\b"#,
            // Spanish
            #"\benviar?\s+[\d.]+\s*(?:btc|sats?|bitcoin)?\s*(?:a\s+)?\S+"#,
            // Arabic partial
            #"\bارسل\s+[\d.]+"#,
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    }()

    /// Negative lookahead words: if these appear, demote "send" to history instead.
    private let sendPastTenseIndicators: [String] = [
        "sent", "i sent", "what i sent", "what did i send", "already sent",
        "was sent", "been sent", "have sent", "had sent",
    ]

    func isSendIntent(_ text: String) -> Bool {
        // Avoid matching past-tense "sent" as a send intent
        if sendPastTenseIndicators.contains(where: { text.contains($0) }) { return false }
        for keyword in sendKeywords {
            if containsWord(text, word: keyword) { return true }
        }
        if matchesAny(text, patterns: sendPatterns) { return true }
        // Fuzzy match on single-word input
        if !text.contains(" ") { return fuzzyContains(text, keywords: ["send", "enviar", "envoyer"]) }
        return false
    }

    // MARK: - Receive Intent

    private let receiveKeywords: [String] = [
        // English
        "receive", "my address", "show address", "get address",
        "qr code", "qr", "deposit", "show qr",
        "receiving address", "give me an address",
        "new address", "generate address", "create address",
        "display address", "display qr", "want to receive",
        "deposit address", "give address",
        "request payment", "invoice",
        // Arabic
        "استقبال", "عنواني", "اظهر العنوان", "رمز qr",
        "إيداع", "عنوان الاستقبال", "اعطني عنوان",
        // Spanish
        "recibir", "mi dirección", "mi direccion", "mostrar dirección",
        "mostrar direccion", "código qr", "codigo qr", "depositar",
        "dirección de recepción",
        // French
        "recevoir", "mon adresse", "afficher adresse", "code qr",
        "adresse de r\u{00E9}ception",
    ]

    private let receivePatterns: [NSRegularExpression] = {
        let patterns = [
            #"\bwhere\s+.*receive\b"#,
            #"\bhow\s+.*receive\b"#,
            #"\bi\s+want\s+to\s+receive\b"#,
            #"\bshow\s+(?:me\s+)?(?:my\s+)?(?:qr|address)\b"#,
            #"\bgenerate\s+(?:a\s+)?(?:new\s+)?address\b"#,
            #"\bcreate\s+(?:a\s+)?(?:new\s+)?address\b"#,
            #"\bgive\s+(?:me\s+)?(?:an?\s+)?address\b"#,
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    }()

    func isReceiveIntent(_ text: String) -> Bool {
        if containsAny(text, keywords: receiveKeywords) { return true }
        if matchesAny(text, patterns: receivePatterns) { return true }
        if !text.contains(" ") { return fuzzyContains(text, keywords: ["receive", "recibir", "recevoir"]) }
        return false
    }

    // MARK: - Balance Intent

    private let balanceKeywords: [String] = [
        // English
        "balance", "my btc", "my bitcoin",
        "funds", "what do i have", "how many bitcoin",
        "how many sats", "how many satoshi", "how many satoshis",
        "how much bitcoin", "how much btc",
        "wallet balance", "total balance", "available balance",
        "what's my balance", "whats my balance",
        "what do i owe", "how much i got", "show me the money",
        "stack check", "wallet check", "what's in my wallet",
        "whats in my wallet", "am i rich", "am i broke",
        "remaining balance", "available funds", "how much can i spend",
        "my money", "my funds", "my coins", "my holdings",
        "what have i got", "my stack",
        "how much money", "how much do i",
        "show balance", "show my balance", "show funds", "show my funds",
        // Arabic
        "رصيدي", "رصيد", "كم عندي", "كم لدي", "ما رصيدي",
        "كم بتكوين", "رصيد المحفظة",
        // Spanish
        "saldo", "cuánto tengo", "cuanto tengo", "mi saldo",
        "fondos", "cuántos bitcoin", "saldo de la cartera", "mostrar saldo",
        // French
        "solde", "mon solde", "combien j'ai", "combien ai-je",
        "solde du portefeuille", "mes fonds",
    ]

    private let balancePatterns: [NSRegularExpression] = {
        let patterns = [
            #"\bhow\s+much\s+(?:do\s+)?i\s+have\b"#,
            #"\bhow\s+much\s+(?:do\s+)?i\s+own\b"#,
            #"\bhow\s+much\s+(?:have\s+)?i\s+got\b"#,
            #"\bwhat(?:'s|\s+is)\s+my\s+(?:balance|btc|bitcoin)\b"#,
            #"\bwhat\s+.*\s+i\s+have\b"#,
            #"\bwhat\s+.*\s+in\s+(?:my\s+)?wallet\b"#,
            #"\bwhat\s+.*\s+my\s+btc\b"#,
            #"\bcheck\s+(?:my\s+)?(?:wallet|balance|funds)\b"#,
            #"\bshow\s+(?:me\s+)?(?:my\s+)?(?:balance|wallet|funds|btc|bitcoin)\b"#,
            #"\bshow\s+me\s+what\s+i\s+have\b"#,
            #"\bwhat\s+.*sitting\s+.*wallet\b"#,
            #"\bshow\s+(?:my\s+)?balance\b"#,
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    }()

    func isBalanceIntent(_ text: String) -> Bool {
        if containsAny(text, keywords: balanceKeywords) { return true }
        if matchesAny(text, patterns: balancePatterns) { return true }
        if text == "stack" { return true }
        if !text.contains(" ") { return fuzzyContains(text, keywords: ["balance", "saldo", "solde"]) }
        return false
    }

    // MARK: - Price Intent

    private let priceKeywords: [String] = [
        // English
        "price", "btc price", "bitcoin price", "how much is bitcoin",
        "what is bitcoin worth", "current price", "market price",
        "how much is btc", "btc value", "bitcoin value",
        "price of bitcoin", "price of btc", "price check",
        "bitcoin trading", "btc to usd", "btc to eur",
        "btc usd", "bitcoin usd", "bitcoin to usd", "bitcoin to eur",
        "bitcoin up or down", "is bitcoin up", "is bitcoin down",
        "spot price", "exchange rate",
        // Arabic
        "سعر", "السعر", "سعر البتكوين", "كم سعر البتكوين", "سعر بتكوين",
        "سعر البيتكوين", "ما السعر",
        // Spanish
        "precio", "precio del bitcoin", "cuánto vale bitcoin",
        "cuanto vale bitcoin", "valor del bitcoin",
        // French
        "prix", "prix du bitcoin", "combien vaut bitcoin",
        "cours du bitcoin", "valeur du bitcoin",
        // Emoji
        "\u{1F4C8}", "\u{1F4C9}",
    ]

    private let pricePatterns: [NSRegularExpression] = {
        let patterns = [
            #"\bhow\s+much\s+is\s+(?:one\s+)?(?:btc|bitcoin)\b"#,
            #"\bhow\s+much\s+.*bitcoin\s+worth\b"#,
            #"\bwhat\s+.*\s+price\b"#,
            #"\bshow\s+.*\s+price\b"#,
            #"\bbitcoin\s+.*worth\b"#,
            #"\bbtc\s+.*worth\b"#,
            #"\bwhat\s+.*bitcoin\s+cost\b"#,
            #"\bprice\s+of\s+(?:btc|bitcoin)\b"#,
            #"\b1\s+btc\s+.*worth\b"#,
            #"\bone\s+bitcoin\s+.*worth\b"#,
            #"\bhow\s+much\s+is\s+[\d.]+\s*(?:btc|bitcoin|sats?|satoshis?)\b"#,
            #"\bwhat(?:'s|\s+is)\s+[\d.]+\s*(?:btc|bitcoin|sats?|satoshis?)\s+(?:in|worth)\b"#,
            #"\b[\d.]+\s*(?:btc|bitcoin)\s+(?:in|to)\s+(?:usd|eur|gbp|dollars?|euros?|pounds?)\b"#,
            #"\bhow\s+much\s+is\s+[\d.]+\s*(?:sats?|satoshis?)\s+worth\b"#,
            #"\b(?:is\s+)?(?:btc|bitcoin)\s+(?:going\s+)?(?:up|down)\b"#,
            #"\bhow\s+many\s+(?:sats?|satoshis?)\s+(?:is|in|are)\s+[\d.]+\s*(?:btc|bitcoin)\b"#,
            #"\bhow\s+much\s+.*one\s+bitcoin\b"#,
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    }()

    func isPriceIntent(_ text: String) -> Bool {
        if containsAny(text, keywords: priceKeywords) { return true }
        if matchesAny(text, patterns: pricePatterns) { return true }
        if text == "price" || text == "precio" || text == "سعر" || text == "السعر" || text == "prix" || text == "rate" { return true }
        if !text.contains(" ") { return fuzzyContains(text, keywords: ["price", "precio", "prix"]) }
        return false
    }

    // MARK: - Convert Amount Intent

    private let convertKeywords: [String] = [
        // English
        "convert", "calculate", "swap",
        // Arabic
        "حول", "احسب",
        // Spanish
        "convertir", "calcular",
        // French
        "convertir", "calculer",
    ]

    private let convertPatterns: [NSRegularExpression] = {
        let patterns = [
            #"\bconvert\s+[\d.]+\s*(?:btc|bitcoin|sats?|satoshis?)?\b"#,
            #"\bhow\s+much\s+is\s+[\d.]+\s*.*\s+in\b"#,
            #"\bhow\s+much\s+(?:is|are)\s+[\d.]+\s*.*worth\b"#,
            #"\b[\d.]+\s*(?:btc|bitcoin)\s+in\b"#,
            #"\b[\d.]+\s*(?:sats?|satoshis?)\s+in\b"#,
            #"\b[\d.]+\s*(?:dollars?|usd)\s+(?:in\s+)?(?:btc|bitcoin|sats?)\b"#,
            #"\b[\d.]+\s*usd\s+(?:to\s+)?(?:btc|bitcoin)\b"#,
            #"\bcalculate\s+[\d.]+"#,
            #"\bwhat\s+(?:is|are)\s+[\d.]+\s*(?:btc|bitcoin|sats?|satoshis?)\b"#,
            #"\$[\d.]+\s+(?:in\s+)?(?:btc|bitcoin|sats?)\b"#,
            #"\b[\d.]+\s*(?:bitcoin|btc)\s+(?:in|to)\s+(?:dollars?|usd|eur|gbp)\b"#,
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    }()

    func isConvertIntent(_ text: String) -> Bool {
        // Convert requires a numeric amount in the text to differentiate from price
        let hasNumber = text.range(of: #"\d"#, options: .regularExpression) != nil
        if hasNumber && containsAny(text, keywords: convertKeywords) { return true }
        if matchesAny(text, patterns: convertPatterns) { return true }
        return false
    }

    // MARK: - Hide Balance Intent

    private let hideBalanceKeywords: [String] = [
        "hide balance", "hide my balance", "hide the balance",
        "private mode", "privacy mode", "go private",
        "hide funds", "hide my funds", "conceal balance",
        // Arabic
        "اخفاء الرصيد", "إخفاء", "وضع خاص",
        // Spanish
        "ocultar saldo", "modo privado",
    ]

    func isHideBalanceIntent(_ text: String) -> Bool {
        if text == "hide" || text == "privacy" { return true }
        return containsAny(text, keywords: hideBalanceKeywords)
    }

    // MARK: - Show Balance Intent

    private let showBalanceKeywords: [String] = [
        // Only explicit "unhide" / "reveal" phrasing triggers the privacy toggle.
        // "show balance" / "show my balance" are handled as .balance intent.
        "unhide", "unhide balance", "reveal balance",
        "reveal my balance",
        // Arabic
        "اظهر الرصيد", "إظهار",
        // Spanish
        "revelar saldo",
    ]

    func isShowBalanceIntent(_ text: String) -> Bool {
        if text == "reveal" { return true }
        return containsAny(text, keywords: showBalanceKeywords)
    }

    // MARK: - Refresh Intent

    private let refreshKeywords: [String] = [
        "refresh", "sync", "resync", "reload", "update",
        "refresh wallet", "sync wallet", "update wallet",
        "resync wallet", "reload wallet",
        "refresh balance", "sync balance", "update balance",
        "fetch balance", "fetch data", "pull data",
        // Arabic
        "تحديث", "تحديث المحفظة", "مزامنة",
        // Spanish
        "actualizar", "sincronizar", "recargar",
    ]

    func isRefreshIntent(_ text: String) -> Bool {
        return containsAny(text, keywords: refreshKeywords)
    }

    // MARK: - History Intent

    private let historyKeywords: [String] = [
        // English
        "history", "transactions", "tx history", "activity",
        "recent transactions", "past transactions", "transaction list",
        "show transactions", "list transactions", "my transactions",
        "transaction history", "show history", "view history",
        "show activity", "recent activity",
        "transfers", "my transfers", "show transfers",
        "last transaction", "recent transfers",
        "show sent", "show received", "pending",
        "payment history", "ledger", "log",
        // Arabic
        "سجل", "المعاملات", "سجل المعاملات", "النشاط",
        "المعاملات الأخيرة",
        // Spanish
        "historial", "transacciones", "actividad reciente",
        "historial de transacciones", "mostrar transacciones",
        // French
        "historique", "transactions", "activit\u{00E9} r\u{00E9}cente",
        "historique des transactions",
    ]

    private let historyPatterns: [NSRegularExpression] = {
        let patterns = [
            #"\blast\s+\d+\s+(?:transactions?|txs?|transfers?)\b"#,
            #"\bshow\s+(?:me\s+)?\d+\s+(?:transactions?|txs?|transfers?)\b"#,
            #"\brecent\s+\d+\b"#,
            #"\bwhat\s+(?:did\s+)?i\s+(?:send|sent|receive|received|transfer)\s*(?:recently|lately)?\b"#,
            #"\bwhat\s+(?:have\s+)?i\s+sent\b"#,
            #"\bwhat\s+(?:have\s+)?i\s+received\b"#,
            #"\bshow\s+(?:me\s+)?(?:my\s+)?(?:transaction|history)\b"#,
            #"\brecent\s+(?:transaction|activity)\b"#,
            #"\bmy\s+transaction\b"#,
            #"\bpast\s+transaction\b"#,
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    }()

    func isHistoryIntent(_ text: String) -> Bool {
        if containsAny(text, keywords: historyKeywords) { return true }
        if matchesAny(text, patterns: historyPatterns) { return true }
        if !text.contains(" ") { return fuzzyContains(text, keywords: ["history", "historial", "historique", "transaction", "transactions"]) }
        return false
    }

    // MARK: - Fee Intent

    private let feeKeywords: [String] = [
        // English
        "fee estimate", "fee rate", "network fee", "mempool",
        "how much to send", "transaction fee", "current fees",
        "fee cost", "what are fees", "what are the fees",
        "fees right now", "fee info", "sat per byte",
        "sats per vbyte", "sat/vb", "sats/vb", "estimated fee",
        "check fees", "show fees", "mempool fee",
        "sending cost", "cost to send",
        // Arabic
        "رسوم", "الرسوم", "رسوم الشبكة", "تقدير الرسوم", "كم الرسوم",
        // Spanish
        "comisión", "comision", "comisiones", "tarifa", "tarifas de red",
        "cuánto cuesta enviar",
        // French
        "frais", "frais de r\u{00E9}seau", "frais de transaction",
        "co\u{00FB}t d'envoi", "estimation des frais",
    ]

    private let feePatterns: [NSRegularExpression] = {
        let patterns = [
            #"\bhow\s+much\s+(?:are\s+)?(?:the\s+)?fees?\b"#,
            #"\bwhat(?:'s|\s+is)\s+(?:the\s+)?(?:current\s+)?fee\b"#,
            #"\bhow\s+(?:expensive|much)\s+(?:is\s+it\s+)?to\s+send\b"#,
            #"\bhow\s+much\s+(?:does\s+it\s+)?cost\s+to\s+send\b"#,
            #"\bshow\s+(?:me\s+)?(?:the\s+)?fees?\b"#,
            #"\bcurrent\s+fee\b"#,
            #"\bfee\s+estimate\b"#,
            #"\bsats?\s+per\s+(?:byte|vbyte|vb)\b"#,
            #"\bnetwork\s+fee\b"#,
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    }()

    func isFeeIntent(_ text: String) -> Bool {
        if containsAny(text, keywords: feeKeywords) { return true }
        if text == "fees" || text == "fee" || text == "gas" || text == "رسوم" || text == "الرسوم" || text == "comisiones" || text == "frais" { return true }
        if matchesAny(text, patterns: feePatterns) { return true }
        if !text.contains(" ") { return fuzzyContains(text, keywords: ["fees", "comision", "frais"]) }
        return false
    }

    // MARK: - Wallet Health Intent

    private let walletHealthKeywords: [String] = [
        "wallet health", "health check", "wallet status", "wallet info",
        "wallet summary", "wallet overview", "wallet details",
        "how is my wallet", "wallet report",
        // Arabic
        "صحة المحفظة", "حالة المحفظة", "تقرير المحفظة",
        // Spanish
        "salud de la cartera", "estado de la cartera", "resumen de la cartera",
    ]

    func isWalletHealthIntent(_ text: String) -> Bool {
        return containsAny(text, keywords: walletHealthKeywords)
    }

    // MARK: - Export History Intent

    private let exportKeywords: [String] = [
        "export", "export history", "export transactions", "download history",
        "csv", "export csv",
        // Arabic
        "تصدير", "تصدير السجل",
        // Spanish
        "exportar", "exportar historial", "descargar historial",
    ]

    func isExportIntent(_ text: String) -> Bool {
        return containsAny(text, keywords: exportKeywords)
    }

    // MARK: - UTXO List Intent

    private let utxoKeywords: [String] = [
        "utxo", "utxos", "unspent", "list utxo", "show utxo",
        "unspent outputs", "coin control", "coin selection",
        "my coins", "inputs",
        // Arabic
        "المخرجات غير المنفقة",
        // Spanish
        "salidas no gastadas",
    ]

    private let utxoPatterns: [NSRegularExpression] = {
        let patterns = [
            #"\bshow\s+(?:me\s+)?(?:my\s+)?utxos?\b"#,
            #"\blist\s+(?:my\s+)?utxos?\b"#,
            #"\bcoin\s+(?:control|selection)\b"#,
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    }()

    func isUTXOIntent(_ text: String) -> Bool {
        if containsAny(text, keywords: utxoKeywords) { return true }
        if matchesAny(text, patterns: utxoPatterns) { return true }
        return false
    }

    // MARK: - Bump Fee / RBF Intent

    private let bumpFeeKeywords: [String] = [
        "bump fee", "rbf", "replace by fee", "speed up", "accelerate",
        "bump", "speed up transaction", "accelerate transaction",
        // Arabic
        "تسريع", "زيادة الرسوم",
        // Spanish
        "acelerar", "aumentar tarifa", "acelerar transacción",
    ]

    func isBumpFeeIntent(_ text: String) -> Bool {
        return containsAny(text, keywords: bumpFeeKeywords)
    }

    // MARK: - Network Status Intent

    private let networkStatusKeywords: [String] = [
        "network status", "network info", "connection status",
        "is the network working", "is the network up", "is the network down",
        "node status", "server status",
        "blockchain status", "block height", "current block",
        "connectivity", "sync status", "syncing",
        "am i connected", "are we connected", "connection check",
        // Arabic
        "حالة الشبكة", "معلومات الشبكة",
        // Spanish
        "estado de la red", "información de red",
    ]

    private let networkPatterns: [NSRegularExpression] = {
        let patterns = [
            #"\bnetwork\s+status\b"#,
            #"\bblockchain\s+status\b"#,
            #"\bblock\s+height\b"#,
            #"\bcurrent\s+block\b"#,
            #"\bnode\s+status\b"#,
            #"\bam\s+i\s+connected\b"#,
            #"\bare\s+we\s+connected\b"#,
            #"\bis\s+(?:the\s+)?network\s+(?:up|down|ok|running|online|offline)\b"#,
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    }()

    func isNetworkStatusIntent(_ text: String) -> Bool {
        if text == "network" || text == "sync" || text == "syncing" { return true }
        if containsAny(text, keywords: networkStatusKeywords) { return true }
        if matchesAny(text, patterns: networkPatterns) { return true }
        return false
    }

    // MARK: - New Address Intent

    private let newAddressKeywords: [String] = [
        "new address", "generate address", "fresh address",
        "another address", "next address",
        // Arabic
        "عنوان جديد", "توليد عنوان",
        // Spanish
        "nueva dirección", "nueva direccion", "generar dirección",
    ]

    func isNewAddressIntent(_ text: String) -> Bool {
        return containsAny(text, keywords: newAddressKeywords)
    }

    // MARK: - About Intent

    private let aboutKeywords: [String] = [
        "about", "about this app", "about the app", "who are you",
        "what are you", "version", "app info", "app version",
        // Arabic
        "عن التطبيق", "من أنت", "إصدار",
        // Spanish
        "acerca de", "sobre la app", "quién eres", "quien eres",
        // French
        "\u{00E0} propos", "qui es-tu", "version de l'app",
    ]

    func isAboutIntent(_ text: String) -> Bool {
        if text == "about" || text == "version" { return true }
        return containsAny(text, keywords: aboutKeywords)
    }

    // MARK: - Confirmation

    private let confirmKeywords: [String] = [
        // English
        "yes", "confirm", "ok", "okay", "go", "send it", "do it",
        "approve", "yeah", "yep", "yup", "sure", "go ahead", "proceed",
        "affirmative", "absolutely", "definitely", "y", "ya", "yea",
        "that's right", "correct", "right", "looks good", "i'm sure", "im sure",
        "go for it", "let's do it", "let's go", "lets go", "confirmed",
        "approved", "roger", "bet", "lgtm", "lfg",
        // Arabic
        "نعم", "أكد", "تأكيد", "موافق", "تمام", "أوافق", "يلا",
        // Spanish
        "sí", "si", "confirmar", "dale", "adelante", "correcto",
        // French
        "oui", "confirmer", "d'accord", "bien s\u{00FB}r", "absolument",
        "parfait", "entendu", "exact", "exactement",
        // Emoji
        "\u{1F44D}", "\u{2705}",
    ]

    func isConfirmation(_ text: String) -> Bool {
        if confirmKeywords.contains(text) { return true }
        for kw in confirmKeywords {
            if text.hasPrefix(kw + " ") || text.hasPrefix(kw + ",") || text.hasPrefix(kw + "!") {
                return true
            }
        }
        return false
    }

    // MARK: - Cancellation

    private let cancelKeywords: [String] = [
        // English
        "no", "cancel", "stop", "nevermind", "never mind", "back",
        "nope", "abort", "don't", "dont", "nah", "n",
        "forget it", "scratch that", "undo", "go back",
        "not now", "hold on", "wait", "cancelled", "canceled",
        "no way", "back out", "disregard", "dismiss",
        "exit", "quit", "leave", "no thanks", "no thank",
        "changed my mind", "not anymore",
        // Arabic
        "لا", "إلغاء", "الغاء", "توقف", "ارجع",
        // Spanish
        "no", "cancelar", "detener", "volver", "parar",
        // French
        "non", "annuler", "arr\u{00EA}ter", "arreter", "retour",
        "pas maintenant", "laisse tomber",
        // Emoji
        "\u{1F44E}", "\u{274C}",
    ]

    func isCancellation(_ text: String) -> Bool {
        if cancelKeywords.contains(text) { return true }
        for kw in cancelKeywords {
            if text.hasPrefix(kw + " ") || text.hasPrefix(kw + ",") || text.hasPrefix(kw + "!") {
                return true
            }
        }
        return false
    }

    // MARK: - Settings Intent

    private let settingsKeywords: [String] = [
        "settings", "preferences", "configure", "setup",
        "configuration", "set up", "options", "change settings",
        "open settings", "show settings",
        // Arabic
        "إعدادات", "اعدادات", "الإعدادات",
        // Spanish
        "ajustes", "configuración", "configuracion", "preferencias",
        // French
        "param\u{00E8}tres", "parametres", "configuration", "r\u{00E9}glages", "reglages",
    ]

    func isSettingsIntent(_ text: String) -> Bool {
        if text == "settings" || text == "إعدادات" || text == "ajustes" || text == "param\u{00E8}tres" { return true }
        return containsAny(text, keywords: settingsKeywords)
    }

    // MARK: - Help Intent

    private let helpKeywords: [String] = [
        // English
        "help", "what can you do", "commands", "how to",
        "what do you do", "how does this work", "instructions",
        "guide", "tutorial", "what commands", "list commands",
        "show commands", "available commands", "menu",
        "what are my options", "what can i do", "how do i",
        "man page", "documentation", "how to use",
        // Arabic
        "مساعدة", "ساعدني", "كيف", "ماذا تفعل", "الأوامر",
        // Spanish
        "ayuda", "ayúdame", "ayudame", "cómo", "como",
        "qué puedes hacer", "que puedes hacer", "comandos",
        // French
        "aide", "aidez-moi", "aide-moi", "comment faire",
        "que peux-tu faire", "commandes",
        // Emoji
        "\u{2753}", "\u{1F198}",
    ]

    private let helpPatterns: [NSRegularExpression] = {
        let patterns = [
            #"\bwhat\s+can\s+(?:you|i)\s+do\b"#,
            #"\bhow\s+(?:do\s+)?i\s+(?:use|start|begin)\b"#,
            #"\bhow\s+does\s+(?:this|it)\s+work\b"#,
            #"\bwhat\s+.*commands\b"#,
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    }()

    func isHelpIntent(_ text: String) -> Bool {
        if text == "help" || text == "?" || text == "مساعدة" || text == "ayuda" || text == "aide" { return true }
        if containsAny(text, keywords: helpKeywords) { return true }
        if matchesAny(text, patterns: helpPatterns) { return true }
        if !text.contains(" ") { return fuzzyContains(text, keywords: ["help", "ayuda", "aide"]) }
        return false
    }

    // MARK: - Explain / Knowledge Intent

    private let explainKeywords: [String] = [
        // English
        "what is bitcoin", "explain bitcoin", "tell me about",
        "what is blockchain", "what is mining", "what is halving",
        "what is mempool", "what is segwit", "what is taproot",
        "what is lightning", "what is seed phrase", "what is private key",
        "what is utxo", "teach me", "learn about", "educate me",
        "help me understand",
        // Arabic
        "ما هو البتكوين", "ما هو البيتكوين", "اشرح", "علمني",
        // Spanish
        "qué es bitcoin", "que es bitcoin", "explícame", "explicame",
        "enséñame", "ensename",
        // French
        "qu'est-ce que bitcoin", "qu'est-ce que le bitcoin",
        "explique-moi", "apprends-moi",
    ]

    private let explainPatterns: [NSRegularExpression] = {
        let patterns = [
            #"\bwhat\s+is\s+bitcoin\b"#,
            #"\bwhat\s+.*bitcoin\?"#,
            #"\bexplain\s+.*bitcoin\b"#,
            #"\btell\s+me\s+about\b"#,
            #"\bwhat\s+is\s+.*blockchain\b"#,
            #"\bhow\s+does\s+.*work\b"#,
            #"\bwhat\s+.*mining\b"#,
            #"\bwhat\s+.*halving\b"#,
            #"\bwhat\s+.*mempool\b"#,
            #"\bwhat\s+.*segwit\b"#,
            #"\bwhat\s+.*taproot\b"#,
            #"\bwhat\s+.*lightning\b"#,
            #"\bwhat\s+.*seed\s+phrase\b"#,
            #"\bwhat\s+.*private\s+key\b"#,
            #"\bwhat\s+.*utxo\b"#,
            #"\bteach\s+me\b"#,
            #"\blearn\s+about\b"#,
            #"\beducate\s+me\b"#,
            #"\bhelp\s+me\s+understand\b"#,
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    }()

    func isExplainIntent(_ text: String) -> Bool {
        if containsAny(text, keywords: explainKeywords) { return true }
        if matchesAny(text, patterns: explainPatterns) { return true }
        return false
    }

    // MARK: - Social Detection

    /// Detects "thank you", "thanks", "awesome", etc.
    private let socialPositiveKeywords: [String] = [
        "thanks", "thank you", "thx", "ty", "awesome", "great", "cool", "nice",
        "perfect", "wonderful", "good job", "well done", "appreciate",
        "brilliant", "love it", "nice one", "sweet",
        "merci", "danke", "grazie",
        "شكرا", "شكرًا", "ممتاز", "رائع",
        "gracias", "genial", "perfecto", "excelente",
    ]

    /// Detects complaints and frustration.
    private let socialNegativeKeywords: [String] = [
        "broken", "not working", "doesn't work", "wrong", "bad",
        "confused", "i don't understand", "this is broken", "bug",
        "error", "frustrated", "annoying", "useless",
    ]

    func isSocialPositive(_ text: String) -> Bool {
        containsAny(text, keywords: socialPositiveKeywords)
    }

    func isSocialNegative(_ text: String) -> Bool {
        containsAny(text, keywords: socialNegativeKeywords)
    }

    /// Detects negation / hesitation in text.
    func containsNegation(_ text: String) -> Bool {
        let negations = [
            "not sure", "don't want", "don't think", "i'm not", "im not",
            "maybe not", "not yet", "shouldn't", "wouldn't", "i won't",
            "changed my mind", "not ready", "hold on",
        ]
        return negations.contains(where: { text.contains($0) })
    }

    // MARK: - Confidence Tiers

    /// Exact single-word match or very precise multi-word phrase.
    private let confidenceExact: Double = 0.95

    /// Strong keyword or regex pattern match with clear intent signal.
    private let confidenceStrong: Double = 0.85

    /// Weaker keyword match or broader pattern that could have false positives.
    private let confidenceWeak: Double = 0.70

    /// Determines confidence tier based on how well the text matches the intent.
    /// - exactWords: single-word exact matches (e.g. "balance", "send", "price")
    /// - strongPhrases: multi-word phrases that strongly indicate the intent
    /// Returns exact (0.95) for single-word exact match, strong (0.85) for phrase/regex, weak (0.70) fallback.
    private func confidence(for text: String, exactWords: [String], strongPhrases: [String] = []) -> Double {
        // Exact single-word match
        if exactWords.contains(text) { return confidenceExact }
        // Strong multi-word phrase match
        if !strongPhrases.isEmpty && strongPhrases.contains(where: { text.contains($0) }) {
            return confidenceStrong
        }
        // Default: weak match (broader substring/regex hit)
        return confidenceWeak
    }

    // MARK: - Scored Matching

    /// Returns scored intent matches for all intent categories.
    /// Each match includes a confidence score based on match quality.
    /// Scores are tiered: exact 0.95, strong 0.85, weak 0.70.
    /// Results are sorted by confidence descending.
    func scoredMatch(_ text: String) -> [IntentScore] {
        var scores: [IntentScore] = []

        // ── Confirmation / Cancellation — highest priority ──
        if isConfirmation(text) {
            let conf = confirmKeywords.contains(text) ? confidenceExact : confidenceStrong
            scores.append(IntentScore(intent: .confirmAction, confidence: conf, source: "keyword"))
        }
        if isCancellation(text) {
            let conf = cancelKeywords.contains(text) ? confidenceExact : confidenceStrong
            scores.append(IntentScore(intent: .cancelAction, confidence: conf, source: "keyword"))
        }

        // ── Greeting ──
        if isGreeting(text) {
            let conf = greetingKeywords.contains(text) ? confidenceExact : confidenceStrong
            scores.append(IntentScore(intent: .greeting, confidence: conf, source: "keyword"))
        }

        // ── Send ──
        if isSendIntent(text) {
            let conf = confidence(for: text,
                exactWords: ["send", "transfer", "pay", "wire", "zap"],
                strongPhrases: ["send to", "transfer to", "pay to", "send btc", "send bitcoin", "send sats"])
            scores.append(IntentScore(intent: .send(amount: nil, unit: nil, address: nil, feeLevel: nil), confidence: conf, source: "keyword"))
        }

        // ── Convert (before price — more specific) ──
        if isConvertIntent(text) {
            scores.append(IntentScore(intent: .convertAmount(amount: 0, fromCurrency: ""), confidence: confidenceStrong, source: "keyword"))
        }

        // ── Price ──
        if isPriceIntent(text) {
            let conf = confidence(for: text,
                exactWords: ["price", "rate"],
                strongPhrases: ["btc price", "bitcoin price", "price of", "how much is btc", "how much is bitcoin",
                                "current price", "market price", "spot price", "exchange rate"])
            scores.append(IntentScore(intent: .price(currency: nil), confidence: conf, source: "keyword"))
        }

        // ── New Address (before generic receive — more specific) ──
        if isNewAddressIntent(text) {
            let conf = confidence(for: text,
                exactWords: [],
                strongPhrases: ["new address", "generate address", "fresh address"])
            scores.append(IntentScore(intent: .newAddress, confidence: min(conf + 0.05, confidenceExact), source: "keyword"))
        }

        // ── Receive ──
        if isReceiveIntent(text) {
            let conf = confidence(for: text,
                exactWords: ["receive", "deposit", "qr"],
                strongPhrases: ["my address", "show address", "get address", "qr code", "receiving address",
                                "deposit address", "request payment", "invoice"])
            scores.append(IntentScore(intent: .receive, confidence: conf, source: "keyword"))
        }

        // ── Hide / Show balance ──
        if isHideBalanceIntent(text) {
            let conf = confidence(for: text,
                exactWords: ["hide", "privacy"],
                strongPhrases: ["hide balance", "private mode", "privacy mode"])
            scores.append(IntentScore(intent: .hideBalance, confidence: conf, source: "keyword"))
        }
        if isShowBalanceIntent(text) {
            let conf = confidence(for: text,
                exactWords: ["reveal", "unhide"],
                strongPhrases: ["unhide balance", "reveal balance"])
            scores.append(IntentScore(intent: .showBalance, confidence: conf, source: "keyword"))
        }

        // ── Refresh ──
        if isRefreshIntent(text) {
            let conf = confidence(for: text,
                exactWords: ["refresh", "sync", "reload"],
                strongPhrases: ["refresh wallet", "sync wallet", "update wallet"])
            scores.append(IntentScore(intent: .refreshWallet, confidence: conf, source: "keyword"))
        }

        // ── Balance ──
        if isBalanceIntent(text) {
            let conf = confidence(for: text,
                exactWords: ["balance", "stack", "funds"],
                strongPhrases: ["my balance", "wallet balance", "total balance", "how much do i have",
                                "how much btc", "how much bitcoin", "what do i have", "my holdings",
                                "show balance", "show my balance", "show funds", "show my funds"])
            scores.append(IntentScore(intent: .balance, confidence: conf, source: "keyword"))
        }

        // ── Export ──
        if isExportIntent(text) {
            let conf = confidence(for: text,
                exactWords: ["export", "csv"],
                strongPhrases: ["export history", "export transactions", "download history"])
            scores.append(IntentScore(intent: .exportHistory, confidence: conf, source: "keyword"))
        }

        // ── History ──
        if isHistoryIntent(text) {
            let conf = confidence(for: text,
                exactWords: ["history", "transactions", "activity", "ledger", "log"],
                strongPhrases: ["transaction history", "show history", "recent transactions",
                                "my transactions", "payment history", "what did i send", "what did i receive"])
            scores.append(IntentScore(intent: .history(count: nil), confidence: conf, source: "keyword"))
        }

        // ── Bump fee ──
        if isBumpFeeIntent(text) {
            let conf = confidence(for: text,
                exactWords: ["rbf", "bump"],
                strongPhrases: ["bump fee", "replace by fee", "speed up", "accelerate"])
            scores.append(IntentScore(intent: .bumpFee(txid: nil), confidence: conf, source: "keyword"))
        }

        // ── Fee ──
        if isFeeIntent(text) {
            let conf = confidence(for: text,
                exactWords: ["fee", "fees", "gas"],
                strongPhrases: ["fee estimate", "fee rate", "network fee", "transaction fee",
                                "how much to send", "sat per byte", "sats/vb", "mempool fee"])
            scores.append(IntentScore(intent: .feeEstimate, confidence: conf, source: "keyword"))
        }

        // ── Wallet health ──
        if isWalletHealthIntent(text) {
            let conf = confidence(for: text,
                exactWords: [],
                strongPhrases: ["wallet health", "health check", "wallet status"])
            scores.append(IntentScore(intent: .walletHealth, confidence: conf, source: "keyword"))
        }

        // ── UTXO ──
        if isUTXOIntent(text) {
            let conf = confidence(for: text,
                exactWords: ["utxo", "utxos", "unspent", "inputs"],
                strongPhrases: ["show utxo", "list utxo", "coin control", "coin selection",
                                "unspent outputs"])
            scores.append(IntentScore(intent: .utxoList, confidence: conf, source: "keyword"))
        }

        // ── Network status ──
        if isNetworkStatusIntent(text) {
            let conf = confidence(for: text,
                exactWords: ["network", "sync", "syncing"],
                strongPhrases: ["network status", "blockchain status", "block height",
                                "node status", "current block"])
            scores.append(IntentScore(intent: .networkStatus, confidence: conf, source: "keyword"))
        }

        // ── About ──
        if isAboutIntent(text) {
            let conf = confidence(for: text,
                exactWords: ["about", "version"],
                strongPhrases: ["about this app", "who are you", "app version"])
            scores.append(IntentScore(intent: .about, confidence: conf, source: "keyword"))
        }

        // ── Settings ──
        if isSettingsIntent(text) {
            let conf = confidence(for: text,
                exactWords: ["settings", "preferences"],
                strongPhrases: ["open settings", "show settings", "change settings"])
            scores.append(IntentScore(intent: .settings, confidence: conf, source: "keyword"))
        }

        // ── Explain / Knowledge ──
        if isExplainIntent(text) {
            let conf = confidence(for: text,
                exactWords: [],
                strongPhrases: ["what is bitcoin", "explain bitcoin", "tell me about",
                                "teach me", "educate me", "help me understand",
                                "what is blockchain", "what is mining"])
            // Route educational queries to .help — WalletIntent has no .explain case.
            // The language engine handles detailed .explain via SentenceMeaning.
            scores.append(IntentScore(intent: .help, confidence: conf, source: "keyword"))
        }

        // ── Help ──
        if isHelpIntent(text) {
            let conf = confidence(for: text,
                exactWords: ["help", "?", "commands", "guide", "tutorial"],
                strongPhrases: ["what can you do", "how do i", "how to use",
                                "what commands", "how does this work"])
            scores.append(IntentScore(intent: .help, confidence: conf, source: "keyword"))
        }

        // Sort by confidence descending so the best match is first
        return scores.sorted { $0.confidence > $1.confidence }
    }

    // MARK: - Emotion Detection

    enum Emotion {
        case gratitude
        case frustration
        case confusion
        case humor
        case excitement
        case sadness
        case affirmation
        case neutral
    }

    struct EmotionResult {
        let emotion: Emotion
        let confidence: Double
    }

    func detectEmotion(_ text: String) -> EmotionResult {
        let lower = text.lowercased()

        // Gratitude
        let gratitudeWords = ["thanks", "thank you", "thx", "ty", "appreciate", "grateful",
                              "you're the best", "awesome help"]
        if gratitudeWords.contains(where: { lower.contains($0) }) {
            return EmotionResult(emotion: .gratitude, confidence: 0.9)
        }

        // Frustration
        let frustrationWords = ["broken", "doesn't work", "not working", "hate this",
                                "frustrated", "annoyed", "why won't", "stupid",
                                "wtf", "what the", "come on", "ugh"]
        if frustrationWords.contains(where: { lower.contains($0) }) {
            return EmotionResult(emotion: .frustration, confidence: 0.8)
        }

        // Confusion
        let confusionWords = ["confused", "don't understand", "what does that mean",
                              "i don't get it", "huh"]
        if confusionWords.contains(where: { lower.contains($0) }) {
            return EmotionResult(emotion: .confusion, confidence: 0.8)
        }

        // Humor
        let humorWords = ["lol", "haha", "funny", "hilarious", "rofl", "lmao"]
        if humorWords.contains(where: { lower.contains($0) }) {
            return EmotionResult(emotion: .humor, confidence: 0.7)
        }

        // Sadness/Loss (Bitcoin context)
        let sadWords = ["lost", "scammed", "stolen", "hacked", "gone", "disappeared"]
        let bitcoinWords = ["bitcoin", "btc", "wallet", "coin", "crypto", "funds", "money", "sats"]
        if sadWords.contains(where: { lower.contains($0) }) && bitcoinWords.contains(where: { lower.contains($0) }) {
            return EmotionResult(emotion: .sadness, confidence: 0.8)
        }

        // Excitement
        if lower.hasSuffix("!!") || lower.contains("awesome") || lower.contains("amazing") || lower.contains("let's go") || lower.contains("lets go") {
            return EmotionResult(emotion: .excitement, confidence: 0.6)
        }

        // Affirmation
        let affirmWords = ["great", "perfect", "nice", "cool", "sweet", "good"]
        if affirmWords.contains(where: { lower == $0 || lower.hasPrefix($0 + " ") || lower.hasPrefix($0 + "!") }) {
            return EmotionResult(emotion: .affirmation, confidence: 0.6)
        }

        return EmotionResult(emotion: .neutral, confidence: 1.0)
    }
}
