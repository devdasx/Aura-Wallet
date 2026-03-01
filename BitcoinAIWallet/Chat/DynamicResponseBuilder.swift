// MARK: - DynamicResponseBuilder.swift
// Bitcoin AI Wallet
//
// Context-aware response generator that uses SentenceMeaning.
// Handles bare questions, evaluations, comparatives, emotions,
// affordability, and safety questions with meaning-driven responses.
// Falls through to ResponseGenerator for standard intent-based responses.
//
// Platform: iOS 17.0+

import Foundation

// MARK: - DynamicResponseBuilder

final class DynamicResponseBuilder {

    private let responseGenerator: ResponseGenerator

    init(responseGenerator: ResponseGenerator) {
        self.responseGenerator = responseGenerator
    }

    // MARK: - Public API

    @MainActor
    func buildResponse(
        for result: ClassificationResult,
        context: ConversationContext,
        memory: ConversationMemory,
        flow: SmartConversationFlow
    ) -> [ResponseType] {

        // ── Check for meaning-driven responses first ──
        if let meaning = result.meaning {

            // Bare questions: "What?" "And?" "Why?"
            if meaning.type == .question && meaning.action == .explain && meaning.object == .lastMentioned {
                return handleBareQuestion(meaning, memory: memory)
            }

            // Evaluations: "That's too much" "Good enough"
            if meaning.type == .evaluation {
                return handleEvaluation(meaning, memory: memory, flow: flow)
            }

            // Comparatives: "Faster" "Cheaper"
            if meaning.modifier != nil && (meaning.action == .modify(what: "fee") || meaning.action == .modify(what: "amount")) {
                return handleComparative(meaning, memory: memory, flow: flow, context: context)
            }

            // Emotions: "Thanks!" "Ugh"
            if meaning.type == .emotional, let emotion = meaning.emotion {
                return handleEmotion(emotion, memory: memory)
            }

            // Affordability: "Can I afford it?"
            if meaning.action == .compare {
                return handleAffordability(memory: memory, context: context)
            }

            // Safety: "Is that safe?"
            if meaning.type == .question && meaning.object == .wallet {
                if let modifier = meaning.modifier, modifier == .enough {
                    // "Is that enough?" — not a safety question
                } else {
                    return handleSafetyQuestion(memory: memory)
                }
            }

            // Ellipsis: "..." — but NEVER when in an active send flow
            if meaning.type == .empty && meaning.confidence <= 0.5 {
                if !flow.isInSendFlow(flow.activeFlow) {
                    return [.text(ResponseVariations.ellipsis())]
                }
                // In a send flow with weak meaning — fall through to re-prompt
            }
        }

        // ── Flow-state-aware re-prompt ──
        // If we're in a send flow and the intent is unknown, re-prompt
        // for the expected data instead of generating a generic fallback.
        if flow.isInSendFlow(flow.activeFlow), case .unknown = result.intent {
            return responseGenerator.generateResponse(
                for: .send(amount: nil, unit: nil, address: nil, feeLevel: nil),
                context: context,
                memory: memory,
                classification: result
            )
        }

        // ── Standard intent-based responses ──
        return responseGenerator.generateResponse(
            for: result.intent,
            context: context,
            memory: memory,
            classification: result
        )
    }

    // MARK: - "What?" → Rephrase last response

    @MainActor
    private func handleBareQuestion(_ meaning: SentenceMeaning, memory: ConversationMemory) -> [ResponseType] {
        if let lastResponse = memory.lastAIResponse {
            return [.text("\(ResponseVariations.rephrasePrefix()) \(simplify(lastResponse))")]
        }
        if let lastIntent = memory.lastUserIntent {
            return [.text(ResponseVariations.explainMore(topic: lastIntent.friendlyName))]
        }
        return [.text(ResponseVariations.whatToKnow())]
    }

    // MARK: - "That's too much" / "Good enough"

    @MainActor
    private func handleEvaluation(_ meaning: SentenceMeaning, memory: ConversationMemory, flow: SmartConversationFlow) -> [ResponseType] {
        guard let modifier = meaning.modifier else {
            return [.text(ResponseVariations.gotIt())]
        }

        switch modifier {
        case .tooMuch:
            if flow.isInSendFlow(flow.activeFlow) {
                if memory.lastShownFeeEstimates != nil {
                    return [
                        .text(ResponseVariations.tooMuchFee()),
                        .actionButtons(buttons: [
                            ActionButton(label: "Use slow fee", command: "slow fee", icon: "tortoise"),
                            ActionButton(label: "Keep current", command: "confirm", icon: "checkmark"),
                        ]),
                    ]
                }
                if let amt = memory.lastAmount {
                    return [
                        .text(ResponseVariations.tooMuchAmount(halfAmount: formatBTC(amt / 2))),
                        .actionButtons(buttons: [
                            ActionButton(label: "Send half", command: "send \(amt / 2)", icon: "divide"),
                            ActionButton(label: "Enter amount", command: "change amount", icon: "pencil"),
                        ]),
                    ]
                }
            }
            return [.text(ResponseVariations.whatToAdjust())]

        case .tooLittle, .notEnough:
            if let amt = memory.lastAmount {
                return [
                    .text(ResponseVariations.tooLittleAmount(doubleAmount: formatBTC(amt * 2))),
                    .actionButtons(buttons: [
                        ActionButton(label: "Double it", command: "send \(amt * 2)", icon: "multiply"),
                        ActionButton(label: "Enter amount", command: "change amount", icon: "pencil"),
                    ]),
                ]
            }
            return [.text(ResponseVariations.whatToIncrease())]

        case .enough:
            if flow.isInSendFlow(flow.activeFlow) {
                return [
                    .text(ResponseVariations.enoughConfirm()),
                    .actionButtons(buttons: [
                        ActionButton(label: "Confirm", command: "confirm", icon: "checkmark.circle"),
                        ActionButton(label: "Cancel", command: "cancel", icon: "xmark"),
                    ]),
                ]
            }
            return [.text(ResponseVariations.gladToHear())]

        default:
            return [.text(ResponseVariations.gotIt())]
        }
    }

    // MARK: - "Faster" "Cheaper"

    @MainActor
    private func handleComparative(_ meaning: SentenceMeaning, memory: ConversationMemory, flow: SmartConversationFlow, context: ConversationContext) -> [ResponseType] {
        guard let modifier = meaning.modifier else {
            return [.text(ResponseVariations.whatToModify())]
        }

        switch modifier {
        case .increase:
            if memory.lastShownFeeEstimates != nil {
                return [.text(ResponseVariations.feeIncrease())]
            }
            if let amt = memory.lastAmount {
                let newAmt = amt * Decimal(string: "1.5")!
                return [.text(ResponseVariations.amountIncrease(newAmount: formatBTC(newAmt)))]
            }

        case .decrease:
            if memory.lastShownFeeEstimates != nil {
                return [.text(ResponseVariations.feeDecrease())]
            }
            if let amt = memory.lastAmount {
                let newAmt = amt * Decimal(string: "0.75")!
                return [.text(ResponseVariations.amountDecrease(newAmount: formatBTC(newAmt)))]
            }

        default:
            break
        }

        return [.text(ResponseVariations.whatToModify())]
    }

    // MARK: - Emotions

    @MainActor
    private func handleEmotion(_ emotion: EmotionType, memory: ConversationMemory) -> [ResponseType] {
        switch emotion {
        case .gratitude:
            let sendAmt: String? = memory.lastSentTx.map { formatBTC($0.amount) }
            return [.text(ResponseVariations.gratitude(lastSendAmount: sendAmt))]

        case .frustration:
            return [.text(ResponseVariations.frustration())]

        case .confusion:
            let topic = memory.lastUserIntent?.friendlyName
            return [.text(ResponseVariations.confusion(lastTopic: topic))]

        case .humor:
            return [.text(ResponseVariations.humor())]

        case .concern:
            return [.text(ResponseVariations.concern())]

        case .excitement:
            let bal: String? = memory.lastShownBalance.map { formatBTC($0) }
            return [.text(ResponseVariations.excitement(balance: bal))]

        case .impatience:
            return [.text(ResponseVariations.impatience())]
        }
    }

    // MARK: - "Can I afford it?"

    @MainActor
    private func handleAffordability(memory: ConversationMemory, context: ConversationContext) -> [ResponseType] {
        guard let balance = context.walletBalance else {
            return [.errorText("Can't check balance right now. Try refreshing.")]
        }
        guard let target = memory.lastAmount ?? context.pendingTransaction?.amount else {
            return [.text(ResponseVariations.affordAskAmount())]
        }

        let remaining = balance - target
        if remaining > 0 {
            return [.text(ResponseVariations.canAfford(target: formatBTC(target), remaining: formatBTC(remaining)))]
        }
        if remaining == 0 {
            return [.text(ResponseVariations.barelyAfford(balance: formatBTC(balance)))]
        }
        return [.text(ResponseVariations.cantAfford(shortBy: formatBTC(abs(remaining)), balance: formatBTC(balance), target: formatBTC(target)))]
    }

    // MARK: - "Is that safe?"

    @MainActor
    private func handleSafetyQuestion(memory: ConversationMemory) -> [ResponseType] {
        if let lastIntent = memory.lastUserIntent {
            switch lastIntent {
            case .send:
                return [.text(ResponseVariations.sendSafety())]
            case .receive:
                return [.text(ResponseVariations.receiveSafety())]
            default:
                break
            }
        }
        return [.text(ResponseVariations.generalSafety())]
    }

    // MARK: - Helpers

    private func formatBTC(_ amount: Decimal) -> String {
        let handler = NSDecimalNumberHandler(
            roundingMode: .plain, scale: 8,
            raiseOnExactness: false, raiseOnOverflow: false,
            raiseOnUnderflow: false, raiseOnDivideByZero: false
        )
        return NSDecimalNumber(decimal: amount).rounding(accordingToBehavior: handler).stringValue
    }

    private func simplify(_ text: String) -> String {
        // Strip formatting tokens and shorten long responses
        var simplified = text
        // Remove {{token:content}} patterns, keeping the content
        let tokenPattern = try? NSRegularExpression(pattern: "\\{\\{[^:]+:([^}]*)\\}\\}", options: [])
        simplified = tokenPattern?.stringByReplacingMatches(
            in: simplified,
            options: [],
            range: NSRange(simplified.startIndex..., in: simplified),
            withTemplate: "$1"
        ) ?? simplified
        // Remove ** bold markers
        simplified = simplified.replacingOccurrences(of: "**", with: "")
        // Truncate if too long
        if simplified.count > 200 {
            let index = simplified.index(simplified.startIndex, offsetBy: 200)
            simplified = String(simplified[..<index]) + "..."
        }
        return simplified
    }
}
