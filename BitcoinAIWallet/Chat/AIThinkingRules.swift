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
        // ║  RULE 1b: INVALID AMOUNT VALIDATION                  ║
        // ║  "send 0.0 BTC" → reject zero amount                 ║
        // ║  "send -1 BTC"  → reject negative amount             ║
        // ║  "send 99999999 BTC" → reject > 21M BTC              ║
        // ╚═════════════════════════════════════════════════════╝

        if let r = thinkAboutInvalidAmount(normalized, result: result) {
            return r
        }

        // ╔═════════════════════════════════════════════════════╗
        // ║  RULE 2: IS THIS A FOLLOW-UP?                       ║
        // ║  "And EUR?" after showing USD price.                ║
        // ║  "In sats?" after showing balance.                  ║
        // ║  "Same address" after a send.                       ║
        // ║  "Why?" after any response.                         ║
        // ║  "Use the fast one" after showing fees.             ║
        // ║  "Send more" after a successful send.               ║
        // ╚═════════════════════════════════════════════════════╝

        if let r = thinkAboutFollowUp(normalized, meaning: meaning, memory: memory, context: context) {
            return r
        }

        // ╔═════════════════════════════════════════════════════╗
        // ║  RULE 3: KNOWLEDGE vs ACTION                        ║
        // ║  "What's bitcoin?" → TEACH (knowledge answer)       ║
        // ║  "How much bitcoin?" → DO (show balance/price)      ║
        // ║  "What are fees?" → TEACH                           ║
        // ║  "Show fees" → DO                                   ║
        // ║  "Is bitcoin safe?" → TEACH                         ║
        // ║  "Is bitcoin legal?" → TEACH                        ║
        // ╚═════════════════════════════════════════════════════╝

        if let r = thinkAboutKnowledge(normalized, result: result, meaning: meaning) {
            return r
        }

        // ╔═════════════════════════════════════════════════════╗
        // ║  RULE 4: GREETINGS                                  ║
        // ║  Time-aware, context-aware greetings.               ║
        // ║  "Good morning" at 2am → "Still up checking BTC?"  ║
        // ║  "hi" mid-conversation → friendly acknowledgment    ║
        // ╚═════════════════════════════════════════════════════╝

        if let r = thinkAboutGreeting(normalized, meaning: meaning, flowState: flowState, memory: memory) {
            return r
        }

        // ╔═════════════════════════════════════════════════════╗
        // ║  RULE 5: SAFETY NET                                 ║
        // ║  Classifier said .unknown? Real words were typed?   ║
        // ║  → Smart fallback. NEVER ellipsis.                  ║
        // ║  Empty input? Gibberish? Very long input?           ║
        // ║  Low confidence with alternatives?                  ║
        // ╚═════════════════════════════════════════════════════╝

        if let r = thinkAboutUnknown(normalized, result: result, flowState: flowState, memory: memory) {
            return r
        }

        // ╔═════════════════════════════════════════════════════╗
        // ║  RULE 6: PROCEED — PASS-THROUGH                    ║
        // ║  High confidence classification that needs no       ║
        // ║  thinking? Already in a flow with correct intent?   ║
        // ║  Just proceed. Don't overthink it.                  ║
        // ╚═════════════════════════════════════════════════════╝

        return thinkAboutProceeding(result: result, flowState: flowState)
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
    //   address    idle → ask intent   awaitingAddress → THE answer
    //   "0.5"      idle → ask intent   awaitingAmount → send 0.5
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
            //   "0.001" → send 0.001 BTC
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
        case .awaitingAddress(let amount):

            // Rule 1f: Raw address pasted → accept it, carry forward the amount
            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
            if looksLikeBitcoinAddress(trimmed) {
                return .correctedIntent(
                    .send(amount: amount, unit: .btc, address: trimmed, feeLevel: nil),
                    confidence: 0.95
                )
            }

            // Rule 1g: "same address" / "last address" → reuse from memory
            if (lower.contains("same") || lower.contains("last") || lower.contains("previous")) && lower.contains("address") {
                if let addr = memory.lastAddress {
                    return .correctedIntent(
                        .send(amount: amount, unit: .btc, address: addr, feeLevel: nil),
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
        case .awaitingFeeLevel(let amount, let address):

            if containsAny(lower, ["slow", "economy", "cheap", "low", "cheapest", "lowest", "بطيء"]) {
                return .correctedIntent(.send(amount: amount, unit: .btc, address: address, feeLevel: .slow), confidence: 0.9)
            }
            if containsAny(lower, ["medium", "normal", "standard", "regular", "default", "middle", "عادي"]) {
                return .correctedIntent(.send(amount: amount, unit: .btc, address: address, feeLevel: .medium), confidence: 0.9)
            }
            if containsAny(lower, ["fast", "quick", "priority", "urgent", "high", "fastest", "highest", "سريع"]) {
                return .correctedIntent(.send(amount: amount, unit: .btc, address: address, feeLevel: .fast), confidence: 0.9)
            }

            // Ordinal selection: "the first one", "number 2", "option 3"
            if containsAny(lower, ["first", "1st", "one", "1"]) && !containsAny(lower, ["second", "third"]) {
                return .correctedIntent(.send(amount: amount, unit: .btc, address: address, feeLevel: .slow), confidence: 0.85)
            }
            if containsAny(lower, ["second", "2nd", "two", "2"]) {
                return .correctedIntent(.send(amount: amount, unit: .btc, address: address, feeLevel: .medium), confidence: 0.85)
            }
            if containsAny(lower, ["third", "3rd", "three", "3"]) {
                return .correctedIntent(.send(amount: amount, unit: .btc, address: address, feeLevel: .fast), confidence: 0.85)
            }

            // "fine" / "ok" / "good" → accept the default (medium)
            if isAffirmative(lower) {
                return .correctedIntent(.send(amount: amount, unit: .btc, address: address, feeLevel: .medium), confidence: 0.85)
            }

        // ┌─────────────────────────────────────────────────────┐
        // │  IDLE / COMPLETED / OTHER — Not in a flow            │
        // │  Bare numbers and addresses need special handling.    │
        // └─────────────────────────────────────────────────────┘
        case .idle, .completed, .processing, .error:

            // Rule 1l: Bare number when NOT in flow → do NOT assume send
            //   "0.5" while idle → ask what they want
            if parseAmount(lower) != nil && !isInFlow(flowState) {
                // Only intercept if the classifier incorrectly routed to .send
                if case .send = result.intent {
                    return .directResponse([
                        .text("You typed a number. What would you like to do with it? You can say **\"send \(lower) BTC\"** or ask me something else."),
                    ])
                }
            }

            // Rule 1m: Bare address when NOT in flow → ask what they want to do with it
            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
            if looksLikeBitcoinAddress(trimmed) && !isInFlow(flowState) {
                // The user pasted an address with no command
                if case .unknown = result.intent {
                    return .directResponse([
                        .text("I see a Bitcoin address. What would you like to do with it?\n\n- **Send** Bitcoin to this address\n- **Check** if it's valid\n\nTry: \"send 0.001 BTC to this address\""),
                    ])
                }
            }
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
    //   After price:    "And EUR?" → EUR price
    //   After price:    "What about pounds?" → GBP price
    //   After balance:  "In sats?" → balance in sats
    //   After balance:  "And in dollars?" → convert balance to USD
    //   After balance:  "Is that a lot?" → contextual evaluation
    //   After history:  "The first one" → transaction detail
    //   After history:  "Tell me about the first one" → transaction detail
    //   After send:     "Send more" → new send flow
    //   After send:     "Same address" → reuse address
    //   After send:     "Again" / "Do it again" → repeat last send
    //   After fees:     "Use the fast one" → select fast fee
    //   After ANY:      "Why?" → explain the previous response
    //   After ANY:      "Can you repeat that?" → repeat last response
    //   After ANY:      "In simpler terms?" → simplify last response
    //
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func thinkAboutFollowUp(
        _ input: String,
        meaning: SentenceMeaning?,
        memory: ConversationMemory,
        context: ConversationContext
    ) -> ThinkingResult? {
        let lower = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = stripConjunctions(lower)

        // ── Universal follow-ups: work after ANY previous intent ──

        // "Why?" / "Why is that?" / "How come?" → explain last response
        if containsAny(lower, ["why?", "how come", "why is that", "why's that"]) || lower == "why" {
            if let lastResponse = memory.lastAIResponse {
                let short = String(lastResponse.prefix(300))
                return .directResponse([.text("Here's why: \(short)")])
            }
        }

        // "Can you repeat that?" / "Say that again" / "What did you say?"
        if containsAny(lower, ["repeat that", "say that again", "what did you say",
                                "come again", "repeat", "say again", "one more time"]) && lower.count < 40 {
            if let lastResponse = memory.lastAIResponse {
                return .directResponse([.text(lastResponse)])
            }
        }

        // "In simpler terms?" / "Explain more simply" / "ELI5" / "Simplify"
        if containsAny(lower, ["simpler terms", "simpler", "simple terms", "eli5",
                                "dumb it down", "more simply", "explain simply",
                                "in plain english", "for beginners"]) {
            if let lastResponse = memory.lastAIResponse {
                let short = String(lastResponse.prefix(200))
                return .directResponse([.text("In simpler terms: \(short)")])
            }
        }

        // "More details" / "Tell me more" / "Elaborate" / "What else?" / "Anything else?"
        if containsAny(lower, ["more details", "tell me more", "elaborate", "go on",
                                "keep going", "continue", "more info", "expand on that",
                                "what else", "anything else", "what more"]) {
            if let lastResponse = memory.lastAIResponse {
                return .directResponse([.text("Here's more detail: \(lastResponse)")])
            }
        }

        // Now check intent-specific follow-ups
        guard let lastIntent = memory.lastUserIntent else { return nil }

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
            // "Is that a lot?" "Is that enough?" "Is that good?" "Can I send some?"
            if containsAny(lower, ["is that a lot", "is that good", "is that enough",
                                    "is that much", "is that ok", "can i send",
                                    "is that right", "is it enough", "is it a lot"]) {
                // Generate a contextual evaluation based on the shown balance
                if let bal = memory.lastShownBalance {
                    let evaluation: String
                    if bal > 1 {
                        evaluation = "You have **\(bal) BTC** — that's a significant holding! Make sure you have proper backups of your seed phrase."
                    } else if bal > Decimal(string: "0.01")! {
                        evaluation = "You have **\(bal) BTC** — a solid start! Consider using cold storage for long-term holding."
                    } else if bal > 0 {
                        evaluation = "You have **\(bal) BTC** — enough for small transactions and getting familiar with Bitcoin."
                    } else {
                        evaluation = "Your balance is **0 BTC** right now. Say **receive** to get a deposit address."
                    }
                    return .directResponse([.text(evaluation)])
                }
                return .followUp(.balance) // Will get context-aware evaluation
            }
        }

        // ── After feeEstimate: selecting a fee ──
        if case .feeEstimate = lastIntent {
            // "Use the fast one" / "I'll take the fast" / "Go with priority"
            if containsAny(lower, ["fast", "quick", "priority", "urgent", "highest", "fastest", "سريع"]) {
                // This starts a send flow with the fast fee pre-selected
                return .followUp(.send(amount: nil, unit: nil, address: nil, feeLevel: .fast))
            }
            if containsAny(lower, ["slow", "cheap", "economy", "lowest", "cheapest", "بطيء"]) {
                return .followUp(.send(amount: nil, unit: nil, address: nil, feeLevel: .slow))
            }
            if containsAny(lower, ["medium", "normal", "middle", "standard", "default", "عادي"]) {
                return .followUp(.send(amount: nil, unit: nil, address: nil, feeLevel: .medium))
            }
            // "the first/second/third one"
            if containsAny(lower, ["first", "1st"]) {
                return .followUp(.send(amount: nil, unit: nil, address: nil, feeLevel: .slow))
            }
            if containsAny(lower, ["second", "2nd", "middle"]) {
                return .followUp(.send(amount: nil, unit: nil, address: nil, feeLevel: .medium))
            }
            if containsAny(lower, ["third", "3rd", "last"]) && !containsAny(lower, ["transaction"]) {
                return .followUp(.send(amount: nil, unit: nil, address: nil, feeLevel: .fast))
            }
        }

        // ── After history: selecting a transaction ──
        if case .history = lastIntent {
            if let txs = memory.lastShownTransactions, !txs.isEmpty {
                // "tell me about the first one" / "details on the first" / "the first one"
                if containsAny(lower, ["first", "oldest", "1st"]) {
                    return .followUp(.transactionDetail(txid: txs.last!.txid))
                }
                if containsAny(lower, ["last", "latest", "newest", "most recent"]) {
                    return .followUp(.transactionDetail(txid: txs.first!.txid))
                }
                // "the second one", "number 2", "tell me about #3"
                if let idx = extractOrdinalIndex(lower), idx < txs.count {
                    return .followUp(.transactionDetail(txid: txs[idx].txid))
                }
                // "tell me about it" / "more details" when only 1 transaction shown
                if txs.count == 1 && containsAny(lower, ["about it", "details", "more", "that one"]) {
                    return .followUp(.transactionDetail(txid: txs[0].txid))
                }
            }
        }

        // ── After successful send: follow-up actions ──
        let wasSend: Bool = {
            if case .send = lastIntent { return true }
            if case .confirmAction = lastIntent { return true }
            return false
        }()

        if wasSend || (memory.lastSentTx != nil && memory.turnsSinceLastSend() < 4) {
            // "send more" / "send again" / "another one"
            if containsAny(lower, ["send more", "another", "one more", "send again"]) {
                return .followUp(.send(amount: nil, unit: nil, address: nil, feeLevel: nil))
            }
            // "same address" / "same amount" → reuse last send parameters
            if containsAny(lower, ["same address", "same place"]) {
                if let addr = memory.lastAddress {
                    return .followUp(.send(amount: nil, unit: nil, address: addr, feeLevel: nil))
                }
            }
            if containsAny(lower, ["same amount"]) {
                if let amt = memory.lastAmount {
                    return .followUp(.send(amount: amt, unit: .btc, address: nil, feeLevel: nil))
                }
            }
        }

        // ── After ANY intent: "again" / "do it again" / "same thing" / "repeat" ──
        if containsAny(lower, ["again", "same thing", "do it again"]) && lower.count < 30 {
            switch lastIntent {
            case .balance: return .followUp(.balance)
            case .price(let c): return .followUp(.price(currency: c))
            case .history(let n): return .followUp(.history(count: n))
            case .feeEstimate: return .followUp(.feeEstimate)
            case .receive: return .followUp(.receive)
            case .walletHealth: return .followUp(.walletHealth)
            case .networkStatus: return .followUp(.networkStatus)
            case .utxoList: return .followUp(.utxoList)
            case .send: // Repeat last send
                if let addr = memory.lastAddress, let amt = memory.lastAmount {
                    return .followUp(.send(amount: amt, unit: .btc, address: addr, feeLevel: nil))
                }
                return .followUp(.send(amount: nil, unit: nil, address: nil, feeLevel: nil))
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
    //   "Is bitcoin safe?"       → KNOWLEDGE (explain safety)
    //   "Is bitcoin legal?"      → KNOWLEDGE (explain legality)
    //   "What are transaction fees?" → KNOWLEDGE (explain concept)
    //
    // KEY DIFFERENTIATOR:
    //   Knowledge: asks about a CONCEPT
    //     ("What is X?", "How does X work?", "Why X?", "Is X safe?")
    //   Action: asks about USER'S DATA or requests an OPERATION
    //     ("my", "show me", "send", "check", "current")
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

        // ── Step 0: Action blocklist ──
        // These words/patterns mean the user wants an ACTION, not knowledge.
        // If present, NEVER route to knowledge.
        let actionSignals = [
            "my balance", "my bitcoin", "my btc", "my wallet", "my address",
            "my transaction", "my utxo", "my fee",
            "show me", "show my", "check my", "display my",
            "how much do i", "how much bitcoin do i", "how much btc do i",
            "send ", "receive ", "generate ",
            "current price", "btc price", "bitcoin price today",
            "what's the price", "what is the price",
        ]
        let hasActionSignal = actionSignals.contains { lower.contains($0) }
        if hasActionSignal { return nil } // Let the classifier handle it

        // ── Step 1: Is this a knowledge question? ──
        //
        // Knowledge starters: words that signal "teach me"
        let knowledgeStarters = [
            // English — question forms
            "what is ", "what's ", "what are ", "what was ",
            "who is ", "who was ", "who created ", "who invented ",
            "explain ", "tell me about ", "teach me ",
            "how does ", "how do ", "how is ", "how are ",
            "why is ", "why does ", "why are ", "why do ",
            "define ", "what does ", "what do ",
            // English — evaluation/opinion forms (knowledge)
            "is bitcoin safe", "is btc safe",
            "is bitcoin legal", "is btc legal",
            "is bitcoin secure", "is bitcoin worth",
            "is bitcoin a good", "is bitcoin real",
            "is bitcoin dead", "is bitcoin a scam",
            "is bitcoin decentralized",
            "can bitcoin be hacked", "can bitcoin be traced",
            "should i buy bitcoin", "should i invest",
            // Arabic
            "ما هو ", "ما هي ", "ما هو ال", "شرح ", "اشرح ", "من هو ", "كيف يعمل ",
            "هل البتكوين ", "هل بتكوين ",
            // Spanish
            "qué es ", "qué son ", "quién es ", "explica ", "cómo funciona ",
            "es bitcoin ",
        ]

        let hasKnowledgeStarter = knowledgeStarters.contains { lower.hasPrefix($0) || lower.contains($0) }

        // ── Step 2: Does it mention a Bitcoin concept? ──
        let bitcoinConcepts = [
            "bitcoin", "btc", "satoshi", "sats", "blockchain",
            "mining", "halving", "halvening", "utxo", "utxos",
            "segwit", "taproot", "lightning", "lightning network",
            "mempool", "seed phrase", "seed words", "mnemonic",
            "private key", "public key", "confirmation", "confirmations",
            "proof of work", "pow", "hash", "hash rate", "hashrate",
            "difficulty", "node", "full node", "genesis block",
            "whitepaper", "white paper", "decentralized", "decentralization",
            "cold storage", "hardware wallet", "multisig", "multi-sig",
            "rbf", "replace by fee", "block reward", "block time",
            "soft fork", "hard fork", "bip", "transaction fee", "transaction fees",
            "21 million", "digital gold", "peer to peer", "p2p",
            "double spend", "51% attack", "consensus", "merkle",
            "schnorr", "ecdsa", "secp256k1", "derivation path",
            "hd wallet", "bip39", "bip44", "bip84", "bip86",
            "witness", "script", "opcode", "timelock", "nonce",
            "coinbase transaction", "dust", "dust limit",
            "block size", "block weight", "vbyte",
            // Culture & slang
            "hodl", "hodling", "hodler", "dca", "dollar cost averaging",
            "whale", "whales", "diamond hands",
            "not your keys", "not your coins",
            // Additional concepts
            "fee", "fees", "transaction", "address", "wallet",
            "seed", "key", "keys", "block", "network",
            "legal", "safe", "secure",
            // Arabic
            "بتكوين", "بلوكتشين", "تعدين", "محفظة",
            // Spanish
            "minería", "monedero",
        ]

        let mentionsConcept = bitcoinConcepts.contains { lower.contains($0) }

        // ── Step 3: Standalone knowledge patterns (no starter needed) ──
        // "bitcoin halving", "lightning network", "transaction fees" by themselves
        let standaloneKnowledgePatterns = [
            "bitcoin halving", "the halving", "next halving",
            "lightning network", "layer 2", "layer two",
            "transaction fees", "network fees", "miner fees",
            "seed phrase", "recovery phrase", "backup phrase",
            "cold storage", "hardware wallet", "paper wallet",
            "full node", "bitcoin node",
            "block reward", "mining reward",
            "genesis block", "first block",
            "21 million", "max supply", "total supply",
            "double spend", "51% attack", "51 percent attack",
        ]
        let isStandaloneKnowledge = standaloneKnowledgePatterns.contains { lower.contains($0) }
            && lower.count < 50 // Short input = likely asking about the concept

        // ── Step 4: Decide ──

        if (hasKnowledgeStarter && mentionsConcept) || isStandaloneKnowledge {
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

            // Handle "is bitcoin safe/legal/etc." evaluation questions
            if lower.contains("safe") || lower.contains("secure") {
                return .knowledgeAnswer(
                    "**Is Bitcoin safe?** The Bitcoin network itself has never been hacked in over " +
                    "15 years of operation. However, safety depends on how you manage your keys:\n\n" +
                    "- **Network security**: Secured by massive computational power (proof-of-work)\n" +
                    "- **Your keys**: Only as safe as how you store them. Use strong backups and consider cold storage for large amounts\n" +
                    "- **Exchanges**: Third-party services can be hacked — \"not your keys, not your coins\"\n" +
                    "- **Transactions**: Irreversible once confirmed, so always double-check addresses\n\n" +
                    "This wallet stores your keys in the device's **Secure Enclave** for protection."
                )
            }

            if lower.contains("legal") {
                return .knowledgeAnswer(
                    "**Is Bitcoin legal?** In most countries, yes. Bitcoin is legal to own, use, and " +
                    "trade in the **US, EU, UK, Japan, Canada, Australia**, and most of the world. " +
                    "Some countries have restrictions or bans (e.g., China banned exchanges but not " +
                    "ownership). Tax treatment varies — in the US, Bitcoin is treated as **property** " +
                    "by the IRS, meaning capital gains taxes apply when you sell. Always check your " +
                    "local regulations."
                )
            }

            if lower.contains("worth") || lower.contains("valuable") || lower.contains("good investment") {
                return .knowledgeAnswer(
                    "**Why is Bitcoin valuable?** Bitcoin's value comes from several properties:\n\n" +
                    "- **Scarcity**: Hard cap of 21 million coins, enforced by code\n" +
                    "- **Decentralization**: No single entity controls it\n" +
                    "- **Censorship resistance**: No one can freeze your funds\n" +
                    "- **Portability**: Send any amount anywhere in minutes\n" +
                    "- **Divisibility**: 1 BTC = 100,000,000 satoshis\n" +
                    "- **Network effect**: Growing adoption by individuals, institutions, and nations\n\n" +
                    "Bitcoin is volatile — its price can swing significantly. Only invest what you can afford to lose."
                )
            }

            if lower.contains("dead") || lower.contains("scam") {
                return .knowledgeAnswer(
                    "Bitcoin has been declared \"dead\" over **470 times** since 2010, yet it continues " +
                    "to operate 24/7 with no downtime. It is **not a scam** — it is open-source software " +
                    "that anyone can audit, run, and verify. The blockchain is a public ledger visible " +
                    "to everyone. However, there are scams **around** Bitcoin (fake exchanges, phishing, " +
                    "Ponzi schemes). Always verify addresses, never share your seed phrase, and only " +
                    "use trusted wallets like this one."
                )
            }

            if lower.contains("hacked") || lower.contains("traced") {
                return .knowledgeAnswer(
                    "**Can Bitcoin be hacked?** The Bitcoin protocol itself has never been hacked. " +
                    "To attack the network, you'd need to control over 50% of global mining power — " +
                    "an astronomically expensive feat.\n\n" +
                    "**Can Bitcoin be traced?** Bitcoin is **pseudonymous**, not anonymous. All transactions " +
                    "are public on the blockchain. While addresses aren't directly linked to identities, " +
                    "chain analysis firms can often trace transactions. For better privacy, use a **new address** " +
                    "for each transaction (this wallet does this automatically)."
                )
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
    // Time-aware, context-aware greetings.
    //
    // First message "hi" → warm welcome with capabilities
    // Mid-conversation "hi" → friendly acknowledgment
    // "Good morning" at 2am → "Still up checking your bitcoin?"
    // After a successful send → "Anything else I can help with?"
    // "hi" in a flow → greet + remind where we are
    //
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func thinkAboutGreeting(
        _ input: String,
        meaning: SentenceMeaning?,
        flowState: ConversationState,
        memory: ConversationMemory
    ) -> ThinkingResult? {

        let lower = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // ── Farewell detection (must check BEFORE greeting — farewells also classify as .greeting) ──
        let farewellWords: Set<String> = [
            "goodbye", "bye", "farewell", "cya", "laterz",
            "see you", "see ya", "see you later", "take care",
            "catch you later", "peace", "adios", "ciao",
            "au revoir", "hasta luego",
        ]
        if farewellWords.contains(lower) || farewellWords.contains(where: { lower.hasPrefix($0) }) {
            return .directResponse([.text(ResponseVariations.farewell())])
        }

        // Detect if this is a greeting via meaning OR via direct keyword match
        let isGreeting: Bool = {
            // SentenceMeaning-based detection: emotional type with no specific emotion
            if let m = meaning, m.type == .emotional, m.emotion == nil, m.confidence >= 0.8 {
                return true
            }
            // Direct keyword detection for greetings the meaning parser might miss
            let greetingWords: Set<String> = [
                "hi", "hello", "hey", "howdy", "sup", "yo", "hola",
                "good morning", "good afternoon", "good evening", "good night",
                "gm", "gn", "morning", "evening", "afternoon",
                "marhaba", "ahlan", "salam", "salaam",
                "مرحبا", "أهلا", "سلام", "صباح الخير", "مساء الخير",
                "hola", "buenos días", "buenas tardes", "buenas noches",
            ]
            return greetingWords.contains(lower) || greetingWords.contains(where: { lower.hasPrefix($0) })
        }()

        guard isGreeting else { return nil }

        let hour = Calendar.current.component(.hour, from: Date())

        // ── Time-aware mismatch detection ──
        // "Good morning" at 2am → playful correction
        if lower.contains("morning") && (hour < 5 || hour >= 12) {
            if hour < 5 {
                return .directResponse([.text("It's the middle of the night! Still up checking your Bitcoin? I admire the dedication. What can I help with?")])
            } else if hour >= 17 {
                return .directResponse([.text("It's actually evening, but good to see you! What can I help with?")])
            }
        }
        if lower.contains("evening") && hour >= 5 && hour < 17 {
            if hour < 12 {
                return .directResponse([.text("It's still morning actually, but hello! What can I help with?")])
            }
        }

        // ── In a send flow: greet but remind them where we are ──
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

        // ── First message ever → warm welcome with wallet summary ──
        if memory.turnCount == 0 {
            let welcome = timeAwareGreeting()
            return .directResponse([.text(
                "\(welcome) Welcome to your Bitcoin wallet! I can help you:\n\n" +
                "- Check your **balance**\n" +
                "- **Send** or **receive** Bitcoin\n" +
                "- Check the **price**\n" +
                "- View **transaction history**\n" +
                "- Learn about **Bitcoin**\n\n" +
                "What would you like to do?"
            )])
        }

        // ── After a recent successful send → offer next steps ──
        if memory.turnsSinceLastSend() < 3 {
            return .directResponse([.text(
                "\(timeAwareGreeting()) Your last send went through successfully. Anything else I can help with?"
            )])
        }

        // ── Mid-conversation greeting → friendly but brief ──
        return .directResponse([.text(timeAwareGreeting())])
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Rule 5: Unknown Input Safety Net
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //
    // The classifier said .unknown or confidence is very low.
    // What do we do?
    //
    // WRONG: "Take your time. I'm here when you're ready."
    //        (Makes us look stupid when user asked a real question)
    //
    // RIGHT: Give a helpful response based on what we DO know:
    //   - Empty input → gentle nudge
    //   - In a send flow → re-prompt for what we need
    //   - Has some meaning → use whatever we can
    //   - Very long input → try to extract key intent
    //   - Low confidence with alternatives → suggest best guess
    //   - Pure gibberish → offer help with examples
    //   - Completely unknown → smart fallback
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

        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // ── Empty input → gentle nudge ──
        if trimmed.isEmpty {
            return .directResponse([.text("Looks like you sent an empty message. Type **help** to see what I can do, or just ask me anything!")])
        }

        // Only the rest applies when classifier returned .unknown or very low confidence
        let isUnknown: Bool = {
            if case .unknown = result.intent { return true }
            return false
        }()

        let isLowConfidence = result.confidence < 0.3 && !isUnknown

        guard isUnknown || isLowConfidence else { return nil }

        // ── Literal ellipsis → allow "Take your time" (the ONE correct use) ──
        if trimmed == "..." || trimmed == ".." || trimmed == "\u{2026}" {
            return nil // Let DynamicResponseBuilder handle normally
        }

        // ── Literal "?" → context-dependent help ──
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

        // ── Single character → probably a mistake, be gentle ──
        if trimmed.count == 1 {
            return .directResponse([.text("What can I help you with? Try **balance**, **send**, **price**, or **help**.")])
        }

        // ── We're in a send flow → re-prompt for what we need ──
        if isInFlow(flowState) {
            return .directResponse([.text(repromptForState(flowState, memory: memory))])
        }

        // ── Very long input → try to extract the key intent ──
        if trimmed.count > 150 {
            // Extract the most likely intent from a verbose message
            let lower = trimmed.lowercased()
            if lower.contains("send") || lower.contains("transfer") {
                return .correctedIntent(.send(amount: nil, unit: nil, address: nil, feeLevel: nil), confidence: 0.6)
            }
            if lower.contains("balance") || lower.contains("how much") {
                return .correctedIntent(.balance, confidence: 0.6)
            }
            if lower.contains("price") || lower.contains("worth") || lower.contains("cost") {
                return .correctedIntent(.price(currency: nil), confidence: 0.6)
            }
            if lower.contains("receive") || lower.contains("deposit") || lower.contains("address") {
                return .correctedIntent(.receive, confidence: 0.6)
            }
            if lower.contains("history") || lower.contains("transactions") {
                return .correctedIntent(.history(count: nil), confidence: 0.6)
            }
            if lower.contains("fee") {
                return .correctedIntent(.feeEstimate, confidence: 0.6)
            }
            // Couldn't extract — summarize what we understood
            return .directResponse([
                .text("I got a long message but I'm not sure what you need. Could you try a shorter command? For example: **balance**, **send 0.01 BTC**, **price**, or **help**."),
            ])
        }

        // ── Pure gibberish → offer help with specific examples ──
        if isGibberish(trimmed) {
            return .directResponse([
                .text("I didn't catch that. Try: **balance**, **send**, **price**, **receive**, **fees**, or ask me anything about Bitcoin!"),
            ])
        }

        // ── Low confidence with alternatives → suggest best guess ──
        if isLowConfidence && !result.alternatives.isEmpty {
            let best = result.alternatives.max(by: { $0.confidence < $1.confidence })
            if let best = best, best.confidence > 0.2 {
                return .directResponse([
                    .text(ResponseTemplates.smartFallbackWithGuess(
                        bestGuess: best.intent,
                        confidence: best.confidence,
                        alternatives: result.alternatives
                    )),
                ])
            }
        }

        // ── Has real words but classifier couldn't handle → smart fallback ──
        // Mention what we CAN do, suggest "help"
        return .directResponse([
            .text(ResponseTemplates.smartFallback()),
        ])
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Rule 6: Proceed (Pass-Through)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //
    // None of the above rules fired. The classifier's result
    // should be used as-is. But we still sanity-check:
    //
    // - High confidence (>= 0.9) and not a knowledge question → proceed
    // - Already in a flow with correct intent → proceed
    // - Standard commands that need no thinking → proceed
    //
    // This is the default path. Most well-classified inputs land here.
    //
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func thinkAboutProceeding(
        result: ClassificationResult,
        flowState: ConversationState
    ) -> ThinkingResult {
        // High confidence, standard intents → just go
        // No additional thinking needed.
        return .proceed
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Rule 1b: Invalid Amount Validation
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //
    // Detects when the user typed a clear send command with an
    // invalid amount (zero, negative, or exceeds 21M BTC) and
    // gives a clear error instead of silently asking "how much?"
    //
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func thinkAboutInvalidAmount(
        _ input: String,
        result: ClassificationResult
    ) -> ThinkingResult? {

        // Only applies when the classifier resolved to .send with no amount
        // (meaning EntityExtractor rejected it) but the raw input contains a number
        guard case .send(let amount, _, _, _) = result.intent, amount == nil else { return nil }

        let lower = input.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if the raw input contains an actionable send keyword + a number
        let hasSendWord = containsAny(lower, ["send", "transfer", "pay", "move", "withdraw"])
        guard hasSendWord else { return nil }

        // Extract raw numbers from the input
        let numberPattern = try? NSRegularExpression(pattern: #"-?\d[\d,]*\.?\d*"#, options: [])
        let nsLower = lower as NSString
        let matches = numberPattern?.matches(in: lower, options: [], range: NSRange(location: 0, length: nsLower.length)) ?? []

        for match in matches {
            let numStr = nsLower.substring(with: match.range).replacingOccurrences(of: ",", with: "")
            guard let value = Decimal(string: numStr) else { continue }

            if value < 0 {
                return .directResponse([
                    .text("You can't send a **negative amount**. Please specify a positive amount, e.g., **send 0.001 BTC**."),
                ])
            }
            if value == 0 {
                return .directResponse([
                    .text("You can't send **zero** Bitcoin. Please specify a valid amount, e.g., **send 0.001 BTC**."),
                ])
            }
            if value > 21_000_000 {
                return .directResponse([
                    .text("That amount exceeds Bitcoin's total supply of **21 million BTC**. Please enter a realistic amount."),
                ])
            }
        }

        return nil
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
        guard !cleaned.isEmpty else { return nil }
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
        // Very short random characters (but not valid single-letter commands)
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
        // "number N" / "#N"
        let numberPatterns = [
            ("number 1", 0), ("number 2", 1), ("number 3", 2),
            ("number 4", 3), ("number 5", 4),
            ("#1", 0), ("#2", 1), ("#3", 2), ("#4", 3), ("#5", 4),
        ]
        for (pattern, idx) in numberPatterns {
            if input.contains(pattern) { return idx }
        }
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
        case 22...23, 0..<5: timeGreeting = "Hey there, night owl!"
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
                       "wallet", "transaction", "confirmation", "multisig", "rbf",
                       "schnorr", "ecdsa", "derivation", "script", "opcode",
                       "consensus", "merkle", "dust", "nonce", "vbyte"]
        let topic = topics.first { input.contains($0) } ?? "that"

        return [
            "Great question about \(topic)! This is a deep topic in Bitcoin. Want me to explain the basics?",
            "Interesting question! \(topic.capitalized) is an important Bitcoin concept. Ask me something specific and I'll do my best to explain.",
            "That's a good one! I can explain various aspects of \(topic). What specifically would you like to know?",
        ].randomElement()!
    }
}
