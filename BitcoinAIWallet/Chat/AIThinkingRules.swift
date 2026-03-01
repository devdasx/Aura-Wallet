// MARK: - AIThinkingRules.swift
// Aura Wallet — Bitcoin AI Wallet
//
// ╔═══════════════════════════════════════════════════════════╗
// ║  THE BRAIN'S RULEBOOK                                     ║
// ║                                                           ║
// ║  Before EVERY response, the AI pauses and thinks:         ║
// ║                                                           ║
// ║  "What did the user say?"                                 ║
// ║  "What state am I in?"                                    ║
// ║  "What was I just talking about?"                         ║
// ║  "What do they ACTUALLY mean?"                            ║
// ║  "What's the BEST response?"                              ║
// ║                                                           ║
// ║  This file IS that thinking process.                      ║
// ╚═══════════════════════════════════════════════════════════╝
//
// Architecture:
//   ChatViewModel → SmartIntentClassifier → ★ AIThinkingRules ★ → Response
//
// Called AFTER classification, BEFORE response generation.
// Can override the classifier's intent, respond directly,
// or let the classifier's result proceed unchanged.
//
// Rules execute IN ORDER. First match wins.
//
// Platform: iOS 17.0+

import Foundation

// MARK: - ThinkingResult

/// What the AI decided after thinking.
enum ThinkingResult {
    /// Override the classifier — use this intent instead.
    case correctedIntent(WalletIntent, confidence: Double)
    /// Respond directly — bypass ResponseGenerator entirely.
    case directResponse([ResponseType])
    /// The input is a knowledge question — return this answer.
    case knowledgeAnswer(String)
    /// This is a follow-up to the previous conversation.
    case followUp(WalletIntent)
    /// The classifier was correct — proceed normally.
    case proceed
}

// MARK: - AIThinkingRules

@MainActor
final class AIThinkingRules {

    private let knowledgeEngine = BitcoinKnowledgeEngine()

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Main Entry Point
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// The AI thinks. Called for every user input.
    ///
    /// Returns a `ThinkingResult` that tells ChatViewModel what to do.
    func think(
        input: String,
        result: ClassificationResult,
        memory: ConversationMemory,
        flowState: ConversationState,
        context: ConversationContext
    ) -> ThinkingResult {

        let normalized = normalize(input)
        let meaning = result.meaning

        // ╔═════════════════════════════════════════════════════╗
        // ║  RULE 0: NEVER SAY "TAKE YOUR TIME" FOR REAL INPUT ║
        // ║  This is the #1 rule. It overrides everything.      ║
        // ╚═════════════════════════════════════════════════════╝
        //
        // "Take your time" / "Thinking it over?" is ONLY acceptable
        // when the user LITERALLY typed "..." or ".." or "…"
        //
        // If they typed ANY real words and the classifier returned
        // .unknown, that's a FAILURE. Give a helpful response instead.

        // ╔═════════════════════════════════════════════════════╗
        // ║  RULE 1: CONTEXT IS KING                            ║
        // ║  The same words mean different things in different   ║
        // ║  states. Always check state first.                  ║
        // ╚═════════════════════════════════════════════════════╝

        if let r = thinkAboutContext(normalized, result: result, meaning: meaning, memory: memory, flowState: flowState, context: context) {
            return r
        }

        // ╔═════════════════════════════════════════════════════╗
        // ║  RULE 2: IS THIS A FOLLOW-UP?                       ║
        // ║  "And EUR?" after showing USD price.                ║
        // ║  "In sats?" after showing balance.                  ║
        // ║  "Same address" after a send.                       ║
        // ╚═════════════════════════════════════════════════════╝

        if let r = thinkAboutFollowUp(normalized, meaning: meaning, memory: memory) {
            return r
        }

        // ╔═════════════════════════════════════════════════════╗
        // ║  RULE 3: KNOWLEDGE vs ACTION                        ║
        // ║  "What's bitcoin?" → TEACH (knowledge answer)       ║
        // ║  "How much bitcoin?" → DO (show balance/price)      ║
        // ║  "What are fees?" → TEACH                           ║
        // ║  "Show fees" → DO                                   ║
        // ╚═════════════════════════════════════════════════════╝

        if let r = thinkAboutKnowledge(normalized, result: result, meaning: meaning) {
            return r
        }

        // ╔═════════════════════════════════════════════════════╗
        // ║  RULE 4: GREETINGS                                  ║
        // ║  "hi" mid-conversation → re-greet warmly            ║
        // ║  NEVER respond to "hi" with "Glad to hear it!"      ║
        // ╚═════════════════════════════════════════════════════╝

        if let r = thinkAboutGreeting(meaning: meaning, flowState: flowState) {
            return r
        }

        // ╔═════════════════════════════════════════════════════╗
        // ║  RULE 5: SAFETY NET                                 ║
        // ║  Classifier said .unknown? Real words were typed?   ║
        // ║  → Smart fallback. NEVER ellipsis.                  ║
        // ╚═════════════════════════════════════════════════════╝

        if let r = thinkAboutUnknown(normalized, result: result, flowState: flowState, memory: memory) {
            return r
        }

        // ╔═════════════════════════════════════════════════════╗
        // ║  RULE 6: CLASSIFIER WAS RIGHT                       ║
        // ║  None of the above rules fired. Proceed normally.   ║
        // ╚═════════════════════════════════════════════════════╝

        return .proceed
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Rule 1: Context
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //
    // The same input means completely different things depending
    // on what we're currently doing:
    //
    //   "0.0001"   idle → ambiguous    awaitingAmount → THE answer
    //   "yes"      idle → confused     awaitingConfirmation → SEND
    //   "send"     idle → start flow   awaitingAmount → DON'T restart!
    //   "faster"   idle → ambiguous    awaitingFee → upgrade fee
    //   "balance?" idle → show it      awaitingAmount → PAUSE flow
    //
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func thinkAboutContext(
        _ input: String,
        result: ClassificationResult,
        meaning: SentenceMeaning?,
        memory: ConversationMemory,
        flowState: ConversationState,
        context: ConversationContext
    ) -> ThinkingResult? {

        let lower = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        switch flowState {

        // ┌─────────────────────────────────────────────────────┐
        // │  AWAITING AMOUNT                                     │
        // │  We asked "How much?" — user should give a number.   │
        // └─────────────────────────────────────────────────────┘
        case .awaitingAmount(let address):

            // Rule 1a: Bare number → this IS the amount
            //   "0.0001" → send 0.0001 BTC
            if let amount = parseAmount(lower) {
                return .correctedIntent(
                    .send(amount: amount, unit: .btc, address: address, feeLevel: nil),
                    confidence: 0.95
                )
            }

            // Rule 1b: Number + unit → convert if needed
            //   "0.0001 btc" → 0.0001 BTC
            //   "50000 sats" → 0.0005 BTC
            //   "50000 satoshis" → 0.0005 BTC
            if let (amount, unit) = parseAmountWithUnit(lower) {
                let btc = (unit == .sats || unit == .satoshis) ? amount / 100_000_000 : amount
                return .correctedIntent(
                    .send(amount: btc, unit: .btc, address: address, feeLevel: nil),
                    confidence: 0.95
                )
            }

            // Rule 1c: Quantifier → resolve against balance
            //   "all" / "max" / "everything" → full balance
            //   "half" → half balance
            if let resolved = resolveQuantifier(lower, balance: context.walletBalance) {
                return .correctedIntent(
                    .send(amount: resolved, unit: .btc, address: address, feeLevel: nil),
                    confidence: 0.9
                )
            }

            // Rule 1d: Fiat amount → convert to BTC
            //   "$50" / "50 dollars" / "50 usd" → convert at current price
            if let (fiatAmount, _) = parseFiatAmount(lower) {
                if let btcPrice = context.btcPrice, btcPrice > 0 {
                    let btcAmount = fiatAmount / btcPrice
                    return .correctedIntent(
                        .send(amount: btcAmount, unit: .btc, address: address, feeLevel: nil),
                        confidence: 0.9
                    )
                }
            }

            // Rule 1e: "send" / "I wanna send" without new data → DON'T restart flow!
            //   Stay in awaitingAmount, re-prompt.
            if isSendVerbWithoutData(result.intent) {
                return .directResponse([.text(ResponseTemplates.askForAmountVaried())])
            }

        // ┌─────────────────────────────────────────────────────┐
        // │  AWAITING ADDRESS                                    │
        // │  We asked "Where to?" — user should give an address. │
        // └─────────────────────────────────────────────────────┘
        case .awaitingAddress:

            // Rule 1f: Raw address pasted → accept it
            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
            if looksLikeBitcoinAddress(trimmed) {
                return .correctedIntent(
                    .send(amount: nil, unit: nil, address: trimmed, feeLevel: nil),
                    confidence: 0.95
                )
            }

            // Rule 1g: "same address" / "last address" → reuse
            if (lower.contains("same") || lower.contains("last") || lower.contains("previous")) && lower.contains("address") {
                if let addr = memory.lastAddress {
                    return .correctedIntent(
                        .send(amount: nil, unit: nil, address: addr, feeLevel: nil),
                        confidence: 0.9
                    )
                }
            }

            // Rule 1h: "send" without data → re-prompt, don't restart
            if isSendVerbWithoutData(result.intent) {
                return .directResponse([.text(ResponseTemplates.askForAddressVaried())])
            }

        // ┌─────────────────────────────────────────────────────┐
        // │  AWAITING CONFIRMATION                               │
        // │  We showed the send card — user should say yes/no.   │
        // └─────────────────────────────────────────────────────┘
        case .awaitingConfirmation:

            // Rule 1i: Affirmative → confirm
            if isAffirmative(lower) {
                return .correctedIntent(.confirmAction, confidence: 0.95)
            }

            // Rule 1j: Negative → cancel
            if isNegative(lower) {
                return .correctedIntent(.cancelAction, confidence: 0.95)
            }

            // Rule 1k: "faster" / "cheaper" → modify, don't lose flow
            //   Let SmartConversationFlow handle this — don't intercept.

        // ┌─────────────────────────────────────────────────────┐
        // │  AWAITING FEE LEVEL                                  │
        // │  We asked "Which fee?" — user picks slow/medium/fast │
        // └─────────────────────────────────────────────────────┘
        case .awaitingFeeLevel:

            if containsAny(lower, ["slow", "economy", "cheap", "low", "بطيء"]) {
                return .correctedIntent(.send(amount: nil, unit: nil, address: nil, feeLevel: .slow), confidence: 0.9)
            }
            if containsAny(lower, ["medium", "normal", "standard", "regular", "default", "عادي"]) {
                return .correctedIntent(.send(amount: nil, unit: nil, address: nil, feeLevel: .medium), confidence: 0.9)
            }
            if containsAny(lower, ["fast", "quick", "priority", "urgent", "high", "سريع"]) {
                return .correctedIntent(.send(amount: nil, unit: nil, address: nil, feeLevel: .fast), confidence: 0.9)
            }

            // "fine" / "ok" / "good" → accept the default (medium)
            if isAffirmative(lower) {
                return .correctedIntent(.send(amount: nil, unit: nil, address: nil, feeLevel: .medium), confidence: 0.85)
            }

        case .idle, .completed, .processing, .error:
            break
        }

        return nil
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Rule 2: Follow-Up
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //
    // The user's message is SHORT and RELATED to the last thing
    // we showed them. They're continuing the conversation, not
    // starting a new one.
    //
    //   After price:   "And EUR?" → EUR price
    //   After balance: "In sats?" → balance in sats
    //   After balance: "Is that a lot?" → contextual evaluation
    //   After history: "The first one" → transaction detail
    //   After send:    "Same address" → reuse address
    //   After send:    "Again" / "Do it again" → repeat last send
    //
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func thinkAboutFollowUp(
        _ input: String,
        meaning: SentenceMeaning?,
        memory: ConversationMemory
    ) -> ThinkingResult? {
        guard let lastIntent = memory.lastUserIntent else { return nil }

        let lower = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = stripConjunctions(lower)

        // ── After price or convertAmount: currency follow-up ──
        let wasPriceRelated: Bool = {
            switch lastIntent {
            case .price, .convertAmount: return true
            default: return false
            }
        }()

        if wasPriceRelated {
            if let code = detectCurrencyCode(stripped) {
                return .followUp(.price(currency: code))
            }
        }

        // ── After balance: unit/fiat conversion ──
        if case .balance = lastIntent {
            // "In sats?" "And in satoshis?"
            if containsAny(stripped, ["sats", "sat", "satoshi", "satoshis", "ساتوشي"]) {
                return .followUp(.balance) // ResponseGenerator will detect sats context
            }
            // "In dollars?" "And EUR?" "What about pounds?"
            if let code = detectCurrencyCode(stripped) {
                return .followUp(.price(currency: code))
            }
            // "Is that a lot?" "Is that enough?" "Can I send some?"
            if containsAny(lower, ["is that a lot", "is that good", "is that enough",
                                    "is that much", "is that ok", "can i send"]) {
                return .followUp(.balance) // Will get context-aware evaluation
            }
        }

        // ── After history: selecting a transaction ──
        if case .history = lastIntent {
            if let txs = memory.lastShownTransactions, !txs.isEmpty {
                if containsAny(lower, ["first", "oldest"]) {
                    return .followUp(.transactionDetail(txid: txs.last!.txid))
                }
                if containsAny(lower, ["last", "latest", "newest", "most recent"]) {
                    return .followUp(.transactionDetail(txid: txs.first!.txid))
                }
                // "the second one", "number 2"
                if let idx = extractOrdinalIndex(lower), idx < txs.count {
                    return .followUp(.transactionDetail(txid: txs[idx].txid))
                }
            }
        }

        // ── After ANY intent: "again" / "do it again" / "same thing" / "repeat" ──
        if containsAny(lower, ["again", "same thing", "repeat", "do it again", "one more time"]) {
            switch lastIntent {
            case .balance: return .followUp(.balance)
            case .price(let c): return .followUp(.price(currency: c))
            case .history(let n): return .followUp(.history(count: n))
            case .send: // Repeat last send
                if let addr = memory.lastAddress, let amt = memory.lastAmount {
                    return .followUp(.send(amount: amt, unit: .btc, address: addr, feeLevel: nil))
                }
            default: break
            }
        }

        return nil
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Rule 3: Knowledge vs Action
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //
    // The hardest disambiguation in the app:
    //
    //   "What's bitcoin?"        → KNOWLEDGE (define bitcoin)
    //   "What's my balance?"     → ACTION (show balance)
    //   "What's the BTC price?"  → ACTION (show price)
    //   "What are fees?"         → KNOWLEDGE (explain fees)
    //   "Show fees"              → ACTION (display fee estimates)
    //   "How does mining work?"  → KNOWLEDGE (explain mining)
    //   "How much bitcoin?"      → ACTION (show balance/price)
    //   "What's a UTXO?"         → KNOWLEDGE (explain UTXO)
    //   "Show UTXOs"             → ACTION (list UTXOs)
    //
    // The key signal: knowledge questions use WHAT IS / EXPLAIN / HOW DOES
    // Action requests use SHOW / HOW MUCH / CHECK / SEND / GET
    //
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func thinkAboutKnowledge(
        _ input: String,
        result: ClassificationResult,
        meaning: SentenceMeaning?
    ) -> ThinkingResult? {

        let lower = input.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")

        // ── Step 1: Is this a knowledge question? ──
        //
        // Knowledge starters: words that signal "teach me"
        let knowledgeStarters = [
            // English
            "what is ", "what's ", "what are ", "what was ",
            "who is ", "who was ", "who created ",
            "explain ", "tell me about ", "teach me ",
            "how does ", "how do ", "how is ", "how are ",
            "why is ", "why does ", "why are ", "why do ",
            "define ", "what does ", "what do ",
            // Arabic
            "ما هو ", "ما هي ", "ما هو ال", "شرح ", "اشرح ", "من هو ", "كيف يعمل ",
            // Spanish
            "qué es ", "qué son ", "quién es ", "explica ", "cómo funciona ",
        ]

        let hasKnowledgeStarter = knowledgeStarters.contains { lower.hasPrefix($0) }

        // ── Step 2: Does it mention a Bitcoin concept? ──
        let bitcoinConcepts = [
            "bitcoin", "btc", "satoshi", "sats", "blockchain",
            "mining", "halving", "halvening", "utxo", "utxos",
            "segwit", "taproot", "lightning", "lightning network",
            "mempool", "seed phrase", "seed words", "mnemonic",
            "private key", "public key", "confirmation", "confirmations",
            "proof of work", "pow", "hash", "hash rate",
            "difficulty", "node", "full node", "genesis block",
            "whitepaper", "white paper", "decentralized",
            "cold storage", "hardware wallet", "multisig", "multi-sig",
            "rbf", "replace by fee", "block reward", "block time",
            "soft fork", "hard fork", "bip", "transaction fee",
            // Arabic
            "بتكوين", "بلوكتشين", "تعدين", "محفظة",
            // Spanish
            "minería", "monedero",
        ]

        let mentionsConcept = bitcoinConcepts.contains { lower.contains($0) }

        // ── Step 3: Decide ──

        if hasKnowledgeStarter && mentionsConcept {
            // This is a knowledge question!
            // Try the knowledge engine with normalized input.
            let forEngine = lower
                .trimmingCharacters(in: .punctuationCharacters)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let answer = knowledgeEngine.answer(forEngine) {
                return .knowledgeAnswer(answer)
            }

            // Knowledge engine didn't have a match — but we KNOW it's a knowledge question.
            // Check if the classifier accidentally classified it as a wallet action
            // (e.g., "What's bitcoin?" → .price because "bitcoin" = .bitcoinUnit).
            //
            // If so, the classifier is WRONG. This is a teaching moment, not a price query.
            if case .price = result.intent {
                // Classifier thought "What's bitcoin?" means "What's the BTC price?"
                // But it doesn't. The user wants to learn.
                // Fall through to the general knowledge response below.
            }

            // Generic knowledge response for concepts we don't have specific answers for.
            // Better than "Take your time" or showing a price card.
            return .directResponse([.text(genericKnowledgeResponse(for: lower))])
        }

        // ── Action signals that should NOT go to knowledge ──
        // "How much bitcoin do I have?" → balance, not knowledge
        // "How much is bitcoin?" → price, not knowledge
        // These have "how much" which is NOT a knowledge starter (it's a quantity question)
        // The classifier handles these correctly — don't intervene.

        return nil
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Rule 4: Greeting
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //
    // "hi" mid-conversation should get a friendly re-greeting,
    // NOT "Glad to hear it!" (which is for positive feedback).
    //
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func thinkAboutGreeting(
        meaning: SentenceMeaning?,
        flowState: ConversationState
    ) -> ThinkingResult? {
        guard let m = meaning else { return nil }

        // Greeting = emotional type with NO specific emotion
        // (emotions like gratitude, frustration DO have .emotion set)
        if m.type == .emotional && m.emotion == nil && m.confidence >= 0.8 {

            // In a send flow: greet but remind them where we are
            if isInFlow(flowState) {
                let greeting = timeAwareGreeting()
                let reminder: String = {
                    switch flowState {
                    case .awaitingAmount: return "We were in the middle of a send — what amount?"
                    case .awaitingAddress: return "We're sending — what's the receiving address?"
                    case .awaitingConfirmation: return "We have a pending send — confirm or cancel?"
                    case .awaitingFeeLevel: return "We were picking a fee — slow, medium, or fast?"
                    default: return "What can I help with?"
                    }
                }()
                return .directResponse([.text("\(greeting) \(reminder)")])
            }

            // Not in flow: warm greeting
            return .directResponse([.text(timeAwareGreeting())])
        }

        return nil
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Rule 5: Unknown Input Safety Net
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //
    // The classifier said .unknown. The AI doesn't understand.
    // What do we do?
    //
    // WRONG: "Take your time. I'm here when you're ready."
    //        (Makes us look stupid when user asked a real question)
    //
    // RIGHT: Give a helpful response based on what we DO know:
    //   - In a send flow → re-prompt for what we need
    //   - Has some meaning → use whatever we can
    //   - Completely unknown → offer help
    //
    // The ONLY time "Take your time" is acceptable:
    //   input == "..." or ".." or "…" (literal ellipsis)
    //
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func thinkAboutUnknown(
        _ input: String,
        result: ClassificationResult,
        flowState: ConversationState,
        memory: ConversationMemory
    ) -> ThinkingResult? {
        // Only applies when classifier returned .unknown
        guard case .unknown = result.intent else { return nil }

        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // Literal ellipsis → allow "Take your time" (the ONE correct use)
        if trimmed == "..." || trimmed == ".." || trimmed == "…" {
            return nil // Let DynamicResponseBuilder handle normally
        }

        // Literal "?" → context-dependent help
        if trimmed == "?" {
            if isInFlow(flowState) {
                return .directResponse([.text(repromptForState(flowState, memory: memory))])
            }
            if let lastResponse = memory.lastAIResponse {
                // Rephrase last thing we said
                let short = String(lastResponse.prefix(150))
                return .directResponse([.text("In other words: \(short)")])
            }
            return .correctedIntent(.help, confidence: 0.9)
        }

        // Single character → probably a mistake, be gentle
        if trimmed.count == 1 {
            return .directResponse([.text("What can I help you with?")])
        }

        // ── We're in a send flow → re-prompt for what we need ──
        if isInFlow(flowState) {
            return .directResponse([.text(repromptForState(flowState, memory: memory))])
        }

        // ── Pure gibberish → offer help ──
        if isGibberish(trimmed) {
            return .directResponse([
                .text("I can help with your Bitcoin wallet — try **balance**, **send**, **receive**, **fees**, **price**, or ask me anything about Bitcoin!"),
            ])
        }

        // ── Has real words but classifier couldn't handle → smart fallback ──
        // Mention what we CAN do, suggest "help"
        return .directResponse([
            .text(ResponseTemplates.smartFallback()),
        ])
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Helper: Amount Parsing
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// Parse a bare numeric amount: "0.0001", "10,000", "0.5"
    private func parseAmount(_ input: String) -> Decimal? {
        let cleaned = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        // Must be ONLY a number (no other words)
        guard cleaned.allSatisfy({ $0.isNumber || $0 == "." }) else { return nil }
        return Decimal(string: cleaned)
    }

    /// Parse amount with unit: "0.001 btc", "50000 sats"
    private func parseAmountWithUnit(_ input: String) -> (Decimal, BitcoinUnit)? {
        let parts = input.split(separator: " ").map { String($0) }
        guard parts.count >= 2 else { return nil }

        let numStr = parts[0].replacingOccurrences(of: ",", with: "")
        guard let amount = Decimal(string: numStr) else { return nil }

        let unitStr = parts[1].trimmingCharacters(in: .punctuationCharacters).lowercased()
        switch unitStr {
        case "btc", "bitcoin": return (amount, .btc)
        case "sat", "sats", "satoshi", "satoshis", "ساتوشي": return (amount, .sats)
        default: return nil
        }
    }

    /// Parse fiat amounts: "$50", "100 USD", "50 euros"
    private func parseFiatAmount(_ input: String) -> (Decimal, String)? {
        // Symbol prefix: "$50", "€100"
        let symbolMap: [(String, String)] = [
            ("$", "USD"), ("€", "EUR"), ("£", "GBP"), ("¥", "JPY"), ("₹", "INR"),
        ]
        for (symbol, code) in symbolMap {
            if input.hasPrefix(symbol) {
                let numStr = String(input.dropFirst(symbol.count))
                    .replacingOccurrences(of: ",", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if let amount = Decimal(string: numStr) {
                    return (amount, code)
                }
            }
        }

        // Code suffix: "100 USD", "50 euros"
        let parts = input.split(separator: " ").map { String($0) }
        if parts.count >= 2, let amount = Decimal(string: parts[0].replacingOccurrences(of: ",", with: "")) {
            if let code = detectCurrencyCode(parts[1]) {
                return (amount, code)
            }
        }

        // Word suffix: "50 dollars", "100 bucks"
        let currencyWords: [(String, String)] = [
            ("dollar", "USD"), ("dollars", "USD"), ("bucks", "USD"),
            ("euro", "EUR"), ("euros", "EUR"),
            ("pound", "GBP"), ("pounds", "GBP"),
            ("yen", "JPY"), ("ريال", "SAR"), ("دينار", "JOD"),
        ]
        for (word, code) in currencyWords {
            if input.contains(word) {
                // Extract number before the word
                let pattern = try? NSRegularExpression(pattern: #"([\d,.]+)\s*"# + NSRegularExpression.escapedPattern(for: word))
                if let match = pattern?.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)) {
                    if let numRange = Range(match.range(at: 1), in: input) {
                        let numStr = String(input[numRange]).replacingOccurrences(of: ",", with: "")
                        if let amount = Decimal(string: numStr) {
                            return (amount, code)
                        }
                    }
                }
            }
        }

        return nil
    }

    /// Resolve "all" / "half" / "max" against wallet balance.
    private func resolveQuantifier(_ input: String, balance: Decimal?) -> Decimal? {
        guard let bal = balance, bal > 0 else { return nil }
        if containsAny(input, ["all", "max", "everything", "maximum", "الكل", "كامل", "todo"]) {
            return bal
        }
        if containsAny(input, ["half", "نصف", "mitad"]) {
            return bal / 2
        }
        return nil
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Helper: Currency Detection
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// Detects a fiat currency code from a word or phrase.
    private func detectCurrencyCode(_ text: String) -> String? {
        let lower = text.lowercased().trimmingCharacters(in: .punctuationCharacters)

        // Exact word matches
        let wordMap: [String: String] = [
            "usd": "USD", "dollar": "USD", "dollars": "USD", "bucks": "USD",
            "eur": "EUR", "euro": "EUR", "euros": "EUR",
            "gbp": "GBP", "pound": "GBP", "pounds": "GBP", "quid": "GBP",
            "jpy": "JPY", "yen": "JPY",
            "cad": "CAD", "aud": "AUD", "chf": "CHF", "franc": "CHF",
            "cny": "CNY", "yuan": "CNY", "rmb": "CNY",
            "krw": "KRW", "won": "KRW",
            "inr": "INR", "rupee": "INR", "rupees": "INR",
            "brl": "BRL", "real": "BRL",
            "mxn": "MXN", "peso": "MXN", "pesos": "MXN",
            "jod": "JOD", "dinar": "JOD", "دينار": "JOD",
            "aed": "AED", "dirham": "AED", "درهم": "AED",
            "sar": "SAR", "riyal": "SAR", "ريال": "SAR",
            "try": "TRY", "lira": "TRY",
            "sek": "SEK", "nok": "NOK", "dkk": "DKK",
        ]
        if let code = wordMap[lower] { return code }

        // 3-letter ISO codes (uppercase check)
        let upper = text.uppercased().trimmingCharacters(in: .punctuationCharacters)
        if upper.count == 3 && upper.allSatisfy({ $0.isUppercase || $0.isLetter }) {
            let validISO: Set<String> = [
                "USD","EUR","GBP","JPY","CAD","AUD","CHF","CNY","KRW","INR",
                "BRL","MXN","JOD","AED","SAR","TRY","SEK","NOK","DKK","PLN",
                "CZK","HUF","THB","SGD","HKD","NZD","ZAR","ILS","RUB","PHP",
                "IDR","MYR","VND","COP","ARS","CLP","PEN","TWD","PKR","BDT",
                "NGN","EGP","KES","GHS","TZS","UGX","MAD","TND","QAR","KWD",
                "BHD","OMR",
            ]
            if validISO.contains(upper) { return upper }
        }

        return nil
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Helper: Language Utilities
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// Normalize smart quotes and trim.
    private func normalize(_ input: String) -> String {
        input
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
    }

    /// Strip leading conjunctions: "and EUR" → "EUR"
    private func stripConjunctions(_ text: String) -> String {
        let prefixes = [
            "and ", "also ", "plus ", "or ", "but ",
            "what about ", "how about ",
            "and in ", "but in ", "also in ", "in ",
            "و ", "أيضا ",
            "y ", "también ",
        ]
        var result = text
        for prefix in prefixes {
            if result.hasPrefix(prefix) {
                result = String(result.dropFirst(prefix.count))
                break
            }
        }
        return result.trimmingCharacters(in: .punctuationCharacters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Affirmative detection.
    private func isAffirmative(_ input: String) -> Bool {
        let words: Set<String> = [
            "yes", "yeah", "yep", "yea", "ya", "y", "ok", "okay", "sure",
            "confirm", "go", "send", "do it", "send it", "let's go",
            "go ahead", "proceed", "absolutely", "definitely", "fine",
            "sounds good", "perfect", "right", "correct", "yup", "aye",
            "نعم", "أكيد", "تمام", "موافق", "يلا", "ماشي",
            "sí", "si", "dale", "claro", "correcto", "vale",
        ]
        return words.contains(input)
    }

    /// Negative detection.
    private func isNegative(_ input: String) -> Bool {
        let words: Set<String> = [
            "no", "nope", "nah", "n", "cancel", "stop", "abort", "quit",
            "never mind", "nevermind", "forget it", "back", "go back",
            "changed my mind", "don't", "dont",
            "لا", "الغاء", "إلغاء", "مش",
            "nunca", "cancelar", "para",
        ]
        return words.contains(input) || words.contains(where: { input.contains($0) })
    }

    /// Check if classified intent is a "send" verb with no accompanying data.
    private func isSendVerbWithoutData(_ intent: WalletIntent) -> Bool {
        if case .send(let amt, _, let addr, _) = intent {
            return amt == nil && addr == nil
        }
        return false
    }

    /// Check if input looks like a Bitcoin address.
    private func looksLikeBitcoinAddress(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("bc1") || trimmed.hasPrefix("tb1") { return trimmed.count >= 42 }
        if (trimmed.hasPrefix("1") || trimmed.hasPrefix("3")) && trimmed.count >= 25 && trimmed.count <= 34 {
            return trimmed.allSatisfy { $0.isLetter || $0.isNumber }
        }
        return false
    }

    /// Check if currently in a send flow.
    private func isInFlow(_ state: ConversationState) -> Bool {
        switch state {
        case .awaitingAmount, .awaitingAddress, .awaitingConfirmation, .awaitingFeeLevel:
            return true
        default:
            return false
        }
    }

    /// Re-prompt text based on current flow state.
    private func repromptForState(_ state: ConversationState, memory: ConversationMemory) -> String {
        switch state {
        case .awaitingAmount:
            return ResponseTemplates.askForAmountVaried()
        case .awaitingAddress:
            return ResponseTemplates.askForAddressVaried()
        case .awaitingConfirmation:
            return "Ready to confirm, or would you like to cancel?"
        case .awaitingFeeLevel:
            return ResponseTemplates.askForFeeLevel()
        default:
            return "What can I help you with?"
        }
    }

    /// Check if input is gibberish (no recognizable words).
    private func isGibberish(_ input: String) -> Bool {
        let cleaned = input.lowercased()
            .trimmingCharacters(in: .punctuationCharacters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return true }
        // If it's all special characters
        if cleaned.allSatisfy({ !$0.isLetter }) { return true }
        // Very short random characters
        if cleaned.count <= 3 && !cleaned.allSatisfy({ $0.isNumber }) { return true }
        return false
    }

    /// Check if input contains any of the given keywords.
    private func containsAny(_ input: String, _ keywords: [String]) -> Bool {
        keywords.contains { input.contains($0) }
    }

    /// Extract ordinal number: "the second one" → 1, "number 3" → 2
    private func extractOrdinalIndex(_ input: String) -> Int? {
        if input.contains("first") || input.contains("1st") { return 0 }
        if input.contains("second") || input.contains("2nd") { return 1 }
        if input.contains("third") || input.contains("3rd") { return 2 }
        if input.contains("fourth") || input.contains("4th") { return 3 }
        if input.contains("fifth") || input.contains("5th") { return 4 }
        return nil
    }

    /// Generate a time-aware greeting.
    private func timeAwareGreeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let timeGreeting: String
        switch hour {
        case 5..<12: timeGreeting = "Good morning!"
        case 12..<17: timeGreeting = "Good afternoon!"
        case 17..<22: timeGreeting = "Good evening!"
        default: timeGreeting = "Hey there!"
        }
        let suffix = ["What can I do for you?", "How can I help?", "What do you need?"]
        return "\(timeGreeting) \(suffix.randomElement() ?? suffix[0])"
    }

    /// Generic knowledge response when the engine doesn't have a specific answer.
    private func genericKnowledgeResponse(for input: String) -> String {
        // Extract the topic from the question
        let topics = ["bitcoin", "blockchain", "mining", "halving", "utxo", "segwit",
                       "taproot", "lightning", "mempool", "fee", "seed", "key", "node",
                       "wallet", "transaction", "confirmation", "multisig", "rbf"]
        let topic = topics.first { input.contains($0) } ?? "that"

        return [
            "Great question about \(topic)! This is a deep topic in Bitcoin. Want me to explain the basics?",
            "Interesting question! \(topic.capitalized) is an important Bitcoin concept. Ask me something specific and I'll do my best to explain.",
            "That's a good one! I can explain various aspects of \(topic). What specifically would you like to know?",
        ].randomElement()!
    }
}
