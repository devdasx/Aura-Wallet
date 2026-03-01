// MARK: - PatternMatcher.swift
// Bitcoin AI Wallet
//
// Regex and keyword pattern matching for intent classification.
// Supports English, Arabic, and Spanish triggers with typo tolerance.
// Classifies user input into wallet operation categories.
//
// Platform: iOS 17.0+
// Framework: Foundation

import Foundation

// MARK: - PatternMatcher

/// Classifies normalized user input into intent categories.
///
/// Supports:
/// - English, Arabic, and Spanish keyword triggers
/// - Regex patterns for complex sentence structures
/// - Levenshtein-distance typo tolerance for single-word commands
/// - Emoji shortcut detection
final class PatternMatcher {

    // MARK: - Typo Tolerance

    /// Maximum Levenshtein distance for fuzzy keyword matching.
    private let maxTypoDistance = 1

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

    /// Checks if a word approximately matches any keyword (within maxTypoDistance).
    private func fuzzyContains(_ text: String, keywords: [String]) -> Bool {
        let words = text.split(separator: " ").map { String($0) }
        for word in words {
            for keyword in keywords {
                // Skip very short keywords (1-2 chars) for fuzzy matching
                if keyword.count <= 2 {
                    if word == keyword { return true }
                    continue
                }
                if levenshteinDistance(word, keyword) <= maxTypoDistance {
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
        // Arabic
        "مرحبا", "سلام", "اهلا", "أهلا", "صباح الخير", "مساء الخير",
        // Spanish
        "hola", "buenos días", "buenas tardes", "buenas noches", "qué tal",
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
        "send", "transfer", "pay", "move", "withdraw", "forward",
        // Arabic
        "ارسل", "أرسل", "حول", "ادفع", "ارسال", "تحويل", "دفع",
        // Spanish
        "enviar", "envía", "envia", "transferir", "pagar", "mandar",
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
            // Spanish
            #"\benviar?\s+[\d.]+\s*(?:btc|sats?|bitcoin)?\s*(?:a\s+)?\S+"#,
            // Arabic partial
            #"\bارسل\s+[\d.]+"#,
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    }()

    func isSendIntent(_ text: String) -> Bool {
        for keyword in sendKeywords {
            if containsWord(text, word: keyword) { return true }
        }
        if matchesAny(text, patterns: sendPatterns) { return true }
        // Fuzzy match on single-word input
        if !text.contains(" ") { return fuzzyContains(text, keywords: ["send", "enviar"]) }
        return false
    }

    // MARK: - Receive Intent

    private let receiveKeywords: [String] = [
        // English
        "receive", "my address", "show address", "get address",
        "qr code", "qr", "deposit", "show qr",
        "receiving address", "give me an address",
        "new address", "generate address", "display address",
        "display qr", "want to receive",
        // Arabic
        "استقبال", "عنواني", "اظهر العنوان", "رمز qr",
        "إيداع", "عنوان الاستقبال", "اعطني عنوان",
        // Spanish
        "recibir", "mi dirección", "mi direccion", "mostrar dirección",
        "mostrar direccion", "código qr", "codigo qr", "depositar",
        "dirección de recepción",
    ]

    func isReceiveIntent(_ text: String) -> Bool {
        if containsAny(text, keywords: receiveKeywords) { return true }
        if !text.contains(" ") { return fuzzyContains(text, keywords: ["receive", "recibir"]) }
        return false
    }

    // MARK: - Balance Intent

    private let balanceKeywords: [String] = [
        // English
        "balance", "how much", "my btc", "my bitcoin",
        "funds", "what do i have", "how many bitcoin",
        "how many sats", "how much bitcoin", "how much btc",
        "wallet balance", "total balance", "available balance",
        "what's my balance", "whats my balance",
        // Arabic
        "رصيدي", "رصيد", "كم عندي", "كم لدي", "ما رصيدي",
        "كم بتكوين", "رصيد المحفظة",
        // Spanish
        "saldo", "cuánto tengo", "cuanto tengo", "mi saldo",
        "fondos", "cuántos bitcoin", "saldo de la cartera",
    ]

    private let balancePatterns: [NSRegularExpression] = {
        let patterns = [
            #"\bhow\s+much\s+(?:do\s+)?i\s+have\b"#,
            #"\bwhat(?:'s|\s+is)\s+my\s+(?:balance|btc|bitcoin)\b"#,
            #"\bcheck\s+(?:my\s+)?(?:wallet|balance|funds)\b"#,
            #"\bshow\s+(?:me\s+)?(?:my\s+)?(?:balance|wallet|funds|btc|bitcoin)\b"#,
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    }()

    func isBalanceIntent(_ text: String) -> Bool {
        if containsAny(text, keywords: balanceKeywords) { return true }
        if matchesAny(text, patterns: balancePatterns) { return true }
        if !text.contains(" ") { return fuzzyContains(text, keywords: ["balance", "saldo"]) }
        return false
    }

    // MARK: - Price Intent

    private let priceKeywords: [String] = [
        // English
        "price", "btc price", "bitcoin price", "how much is bitcoin",
        "what is bitcoin worth", "current price", "market price",
        "how much is btc", "btc value", "bitcoin value",
        "price of bitcoin", "price of btc",
        // Arabic
        "سعر", "سعر البتكوين", "كم سعر البتكوين", "سعر بتكوين",
        // Spanish
        "precio", "precio del bitcoin", "cuánto vale bitcoin",
        "cuanto vale bitcoin", "valor del bitcoin",
        // Emoji
        "📈", "📉",
    ]

    func isPriceIntent(_ text: String) -> Bool {
        if containsAny(text, keywords: priceKeywords) { return true }
        if text == "price" || text == "precio" || text == "سعر" { return true }
        if !text.contains(" ") { return fuzzyContains(text, keywords: ["price", "precio"]) }
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
        "show balance", "show my balance", "show the balance",
        "unhide", "unhide balance", "reveal balance",
        "reveal my balance", "show funds", "show my funds",
        // Arabic
        "اظهر الرصيد", "إظهار",
        // Spanish
        "mostrar saldo", "revelar saldo",
    ]

    func isShowBalanceIntent(_ text: String) -> Bool {
        if text == "reveal" { return true }
        return containsAny(text, keywords: showBalanceKeywords)
    }

    // MARK: - Refresh Intent

    private let refreshKeywords: [String] = [
        "refresh", "sync", "resync", "reload", "update",
        "refresh wallet", "sync wallet", "update wallet",
        "resync wallet", "reload wallet", "check balance",
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
        // Arabic
        "سجل", "المعاملات", "سجل المعاملات", "النشاط",
        "المعاملات الأخيرة",
        // Spanish
        "historial", "transacciones", "actividad reciente",
        "historial de transacciones", "mostrar transacciones",
    ]

    private let historyPatterns: [NSRegularExpression] = {
        let patterns = [
            #"\blast\s+\d+\s+(?:transactions?|txs?|transfers?)\b"#,
            #"\bshow\s+(?:me\s+)?\d+\s+(?:transactions?|txs?|transfers?)\b"#,
            #"\brecent\s+\d+\b"#,
            #"\bwhat\s+(?:did\s+)?i\s+(?:send|receive|transfer)\s*(?:recently|lately)?\b"#,
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    }()

    func isHistoryIntent(_ text: String) -> Bool {
        if containsAny(text, keywords: historyKeywords) { return true }
        if matchesAny(text, patterns: historyPatterns) { return true }
        if !text.contains(" ") { return fuzzyContains(text, keywords: ["history", "historial"]) }
        return false
    }

    // MARK: - Fee Intent

    private let feeKeywords: [String] = [
        // English
        "fee estimate", "fee rate", "network fee", "mempool",
        "how much to send", "transaction fee", "current fees",
        "fee cost", "what are fees", "what are the fees",
        "fees right now", "fee info", "sat per byte",
        "sats per vbyte", "sat/vb", "estimated fee",
        "check fees", "show fees",
        // Arabic
        "رسوم", "رسوم الشبكة", "تقدير الرسوم", "كم الرسوم",
        // Spanish
        "comisión", "comision", "tarifa", "tarifas de red",
        "cuánto cuesta enviar",
    ]

    private let feePatterns: [NSRegularExpression] = {
        let patterns = [
            #"\bhow\s+much\s+(?:are\s+)?(?:the\s+)?fees?\b"#,
            #"\bwhat(?:'s|\s+is)\s+(?:the\s+)?(?:current\s+)?fee\b"#,
            #"\bhow\s+(?:expensive|much)\s+(?:is\s+it\s+)?to\s+send\b"#,
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    }()

    func isFeeIntent(_ text: String) -> Bool {
        if containsAny(text, keywords: feeKeywords) { return true }
        if text == "fees" || text == "fee" || text == "رسوم" { return true }
        if matchesAny(text, patterns: feePatterns) { return true }
        if !text.contains(" ") { return fuzzyContains(text, keywords: ["fees", "comision"]) }
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
        "unspent outputs", "coin control",
        // Arabic
        "المخرجات غير المنفقة",
        // Spanish
        "salidas no gastadas",
    ]

    func isUTXOIntent(_ text: String) -> Bool {
        return containsAny(text, keywords: utxoKeywords)
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
        "is the network working", "node status", "server status",
        "blockchain status",
        // Arabic
        "حالة الشبكة", "معلومات الشبكة",
        // Spanish
        "estado de la red", "información de red",
    ]

    func isNetworkStatusIntent(_ text: String) -> Bool {
        return containsAny(text, keywords: networkStatusKeywords)
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
    ]

    func isAboutIntent(_ text: String) -> Bool {
        if text == "about" || text == "version" { return true }
        return containsAny(text, keywords: aboutKeywords)
    }

    // MARK: - Confirmation

    private let confirmKeywords: [String] = [
        // English
        "yes", "confirm", "ok", "okay", "go", "send it", "do it",
        "approve", "yeah", "yep", "sure", "go ahead", "proceed",
        "affirmative", "absolutely", "y", "ya", "yea",
        "that's right", "correct", "right", "looks good",
        "go for it", "let's do it", "let's go", "confirmed",
        // Arabic
        "نعم", "أكد", "موافق", "تمام", "أوافق", "يلا",
        // Spanish
        "sí", "si", "confirmar", "dale", "adelante", "correcto",
        // Emoji
        "👍", "✅",
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
        // Arabic
        "لا", "إلغاء", "الغاء", "توقف", "ارجع",
        // Spanish
        "no", "cancelar", "detener", "volver", "parar",
        // Emoji
        "👎", "❌",
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
    ]

    func isSettingsIntent(_ text: String) -> Bool {
        if text == "settings" || text == "إعدادات" || text == "ajustes" { return true }
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
        // Arabic
        "مساعدة", "ساعدني", "كيف", "ماذا تفعل", "الأوامر",
        // Spanish
        "ayuda", "ayúdame", "ayudame", "cómo", "como",
        "qué puedes hacer", "que puedes hacer", "comandos",
        // Emoji
        "❓", "🆘",
    ]

    private let helpPatterns: [NSRegularExpression] = {
        let patterns = [
            #"\bwhat\s+can\s+(?:you|i)\s+do\b"#,
            #"\bhow\s+(?:do\s+)?i\s+(?:use|start|begin)\b"#,
            #"\bhow\s+does\s+(?:this|it)\s+work\b"#,
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    }()

    func isHelpIntent(_ text: String) -> Bool {
        if text == "help" || text == "?" || text == "مساعدة" || text == "ayuda" { return true }
        if containsAny(text, keywords: helpKeywords) { return true }
        if matchesAny(text, patterns: helpPatterns) { return true }
        return false
    }

    // MARK: - Social Detection

    /// Detects "thank you", "thanks", "awesome", etc.
    private let socialPositiveKeywords: [String] = [
        "thanks", "thank you", "thx", "ty", "awesome", "great", "cool", "nice",
        "perfect", "wonderful", "good job", "well done", "appreciate",
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

    // MARK: - Scored Matching

    /// Returns scored intent matches for all intent categories.
    /// Each match includes a confidence score based on the signal weight.
    func scoredMatch(_ text: String) -> [IntentScore] {
        var scores: [IntentScore] = []

        // Confirmation / Cancellation — highest priority with high confidence
        if isConfirmation(text) {
            scores.append(IntentScore(intent: .confirmAction, confidence: 0.9, source: "keyword"))
        }
        if isCancellation(text) {
            scores.append(IntentScore(intent: .cancelAction, confidence: 0.9, source: "keyword"))
        }

        // Greeting
        if isGreeting(text) {
            scores.append(IntentScore(intent: .greeting, confidence: SignalWeight.keyword, source: "keyword"))
        }

        // Send
        if isSendIntent(text) {
            scores.append(IntentScore(intent: .send(amount: nil, unit: nil, address: nil, feeLevel: nil), confidence: SignalWeight.keyword, source: "keyword"))
        }

        // Price
        if isPriceIntent(text) {
            scores.append(IntentScore(intent: .price(currency: nil), confidence: SignalWeight.keyword, source: "keyword"))
        }

        // New Address (before generic receive)
        if isNewAddressIntent(text) {
            scores.append(IntentScore(intent: .newAddress, confidence: SignalWeight.keyword + 0.05, source: "keyword"))
        }

        // Receive
        if isReceiveIntent(text) {
            scores.append(IntentScore(intent: .receive, confidence: SignalWeight.keyword, source: "keyword"))
        }

        // Hide / Show balance
        if isHideBalanceIntent(text) {
            scores.append(IntentScore(intent: .hideBalance, confidence: SignalWeight.keyword, source: "keyword"))
        }
        if isShowBalanceIntent(text) {
            scores.append(IntentScore(intent: .showBalance, confidence: SignalWeight.keyword, source: "keyword"))
        }

        // Refresh
        if isRefreshIntent(text) {
            scores.append(IntentScore(intent: .refreshWallet, confidence: SignalWeight.keyword, source: "keyword"))
        }

        // Balance
        if isBalanceIntent(text) {
            scores.append(IntentScore(intent: .balance, confidence: SignalWeight.keyword, source: "keyword"))
        }

        // Export
        if isExportIntent(text) {
            scores.append(IntentScore(intent: .exportHistory, confidence: SignalWeight.keyword, source: "keyword"))
        }

        // History
        if isHistoryIntent(text) {
            scores.append(IntentScore(intent: .history(count: nil), confidence: SignalWeight.keyword, source: "keyword"))
        }

        // Bump fee
        if isBumpFeeIntent(text) {
            scores.append(IntentScore(intent: .bumpFee(txid: nil), confidence: SignalWeight.keyword, source: "keyword"))
        }

        // Fee
        if isFeeIntent(text) {
            scores.append(IntentScore(intent: .feeEstimate, confidence: SignalWeight.keyword, source: "keyword"))
        }

        // Wallet health
        if isWalletHealthIntent(text) {
            scores.append(IntentScore(intent: .walletHealth, confidence: SignalWeight.keyword, source: "keyword"))
        }

        // UTXO
        if isUTXOIntent(text) {
            scores.append(IntentScore(intent: .utxoList, confidence: SignalWeight.keyword, source: "keyword"))
        }

        // Network status
        if isNetworkStatusIntent(text) {
            scores.append(IntentScore(intent: .networkStatus, confidence: SignalWeight.keyword, source: "keyword"))
        }

        // About
        if isAboutIntent(text) {
            scores.append(IntentScore(intent: .about, confidence: SignalWeight.keyword, source: "keyword"))
        }

        // Settings
        if isSettingsIntent(text) {
            scores.append(IntentScore(intent: .settings, confidence: SignalWeight.keyword, source: "keyword"))
        }

        // Help
        if isHelpIntent(text) {
            scores.append(IntentScore(intent: .help, confidence: SignalWeight.keyword, source: "keyword"))
        }

        return scores
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
