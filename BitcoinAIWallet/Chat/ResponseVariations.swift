// MARK: - ResponseVariations.swift
// Bitcoin AI Wallet
//
// Response variation pools for natural-sounding AI responses.
// Each method returns a randomly selected variation from 3-5 options.
// Used by DynamicResponseBuilder for meaning-aware responses.
//
// Platform: iOS 17.0+

import Foundation

// MARK: - ResponseVariations

struct ResponseVariations {

    // MARK: - Variation Helper

    private static func pick(_ options: [String]) -> String {
        options.randomElement() ?? options[0]
    }

    // MARK: - Ellipsis / Hesitation

    static func ellipsis() -> String {
        pick([
            "Take your time. I'm here when you're ready.",
            "No rush — let me know what you need.",
            "Thinking it over? I'm here.",
        ])
    }

    // MARK: - Bare Question Rephrase

    static func rephrasePrefix() -> String {
        pick([
            "Let me put it differently:",
            "In simpler terms:",
            "Here's another way to look at it:",
        ])
    }

    static func explainMore(topic: String) -> String {
        pick([
            "Let me explain more about \(topic).",
            "Here's more on \(topic).",
            "Sure — about \(topic):",
        ])
    }

    static func whatToKnow() -> String {
        pick([
            "What would you like to know more about?",
            "What can I explain?",
            "Ask me anything — I'm here to help.",
        ])
    }

    // MARK: - Evaluation Responses

    static func tooMuchFee() -> String {
        pick([
            "Want a **slower** fee to save money?",
            "I can switch to a cheaper fee level.",
            "Let's use a lower fee — it'll take longer but cost less.",
        ])
    }

    static func tooMuchAmount(halfAmount: String) -> String {
        pick([
            "Want to send less? Half would be **\(halfAmount)**.",
            "We could reduce it — half is **\(halfAmount)**.",
            "How about sending less? Half would be **\(halfAmount)**.",
        ])
    }

    static func tooLittleAmount(doubleAmount: String) -> String {
        pick([
            "Want to increase it? Double would be **\(doubleAmount)**.",
            "We could bump it up — double is **\(doubleAmount)**.",
            "Double would be **\(doubleAmount)**. Want to increase?",
        ])
    }

    static func whatToAdjust() -> String {
        pick([
            "I understand. What would you like to adjust?",
            "Got it. What should we change?",
            "No problem. What would you like to modify?",
        ])
    }

    static func whatToIncrease() -> String {
        pick([
            "What would you like to increase?",
            "What should I bump up?",
            "Tell me what you'd like to increase.",
        ])
    }

    static func enoughConfirm() -> String {
        pick([
            "Ready to confirm?",
            "Shall we proceed?",
            "Want to go ahead and confirm?",
        ])
    }

    static func gladToHear() -> String {
        pick([
            "Glad to hear it! Anything else?",
            "Great! What else can I help with?",
            "Sounds good! Need anything else?",
        ])
    }

    static func gotIt() -> String {
        pick([
            "Got it. What would you like to do?",
            "Understood. What's next?",
            "OK. How can I help?",
        ])
    }

    // MARK: - Comparative Responses

    static func feeIncrease() -> String {
        pick([
            "Switching to **fast** fee — should confirm next block (~10 min).",
            "Bumping to priority fee for faster confirmation.",
            "Moving to **fast** — expect confirmation in ~10 minutes.",
        ])
    }

    static func feeDecrease() -> String {
        pick([
            "Switching to **economy** fee — takes longer but saves money.",
            "Dropping to a lower fee to save on costs.",
            "Using **slow** fee — cheaper but takes ~60 minutes.",
        ])
    }

    static func amountIncrease(newAmount: String) -> String {
        pick([
            "Increasing to **\(newAmount)** BTC. Look right?",
            "Bumped up to **\(newAmount)** BTC. Sound good?",
            "Updated to **\(newAmount)** BTC.",
        ])
    }

    static func amountDecrease(newAmount: String) -> String {
        pick([
            "Reducing to **\(newAmount)** BTC. Sound better?",
            "Lowered to **\(newAmount)** BTC. Good?",
            "Updated to **\(newAmount)** BTC.",
        ])
    }

    static func whatToModify() -> String {
        pick([
            "What would you like to adjust?",
            "What should I change?",
            "Tell me what to modify.",
        ])
    }

    // MARK: - Emotion Responses

    static func gratitude(lastSendAmount: String?) -> String {
        if let amount = lastSendAmount {
            return "You're welcome! Your **\(amount) BTC** send is on its way."
        }
        return pick([
            "Happy to help! Need anything else?",
            "Anytime! What's next?",
            "You're welcome!",
            "Glad I could help!",
        ])
    }

    static func frustration() -> String {
        pick([
            "I'm sorry about that. Let me help — what's going wrong?",
            "I hear you. Let's figure this out. What happened?",
            "Sorry about that. Can you tell me more about what went wrong?",
        ])
    }

    static func confusion(lastTopic: String?) -> String {
        if let topic = lastTopic {
            return "No worries! Let me explain \(topic) differently."
        }
        return pick([
            "No problem! Ask me anything. Try **\"help\"** to see what I can do.",
            "Let me try to explain that differently. What part is unclear?",
            "No worries — I'm here to help. What's confusing?",
        ])
    }

    static func humor() -> String {
        "What else can I help you with?"
    }

    static func concern() -> String {
        "Your funds are safe — keys never leave this device. What's on your mind?"
    }

    static func excitement(balance: String?) -> String {
        if let bal = balance {
            return "Looking good with **\(bal) BTC**! What's next?"
        }
        return pick([
            "Love the energy! What would you like to do?",
            "Let's go! What do you need?",
            "What would you like to do?",
        ])
    }

    static func impatience() -> String {
        pick([
            "On it! What do you need?",
            "Right away — what can I do?",
            "I'm here! What do you need?",
        ])
    }

    // MARK: - Affordability

    static func canAfford(target: String, remaining: String) -> String {
        pick([
            "Yes! Sending **\(target)** would leave you **\(remaining) BTC**.",
            "You can cover it. After **\(target)**, you'd have **\(remaining) BTC** left.",
            "Absolutely — **\(target)** is within your balance. **\(remaining) BTC** remaining.",
        ])
    }

    static func barelyAfford(balance: String) -> String {
        pick([
            "Barely — that would use your entire **\(balance)** balance. Nothing left for future fees.",
            "Just barely. You'd spend your full **\(balance)** balance with nothing left.",
            "Technically yes, but you'd have zero left from your **\(balance)** balance.",
        ])
    }

    static func cantAfford(shortBy: String, balance: String, target: String) -> String {
        pick([
            "Not quite. You're short by **\(shortBy)** BTC. Balance: **\(balance)**, need: **\(target)**",
            "You don't have enough. Short by **\(shortBy)** BTC (have: **\(balance)**, need: **\(target)**).",
            "That's more than your balance. You're **\(shortBy)** BTC short.",
        ])
    }

    static func affordAskAmount() -> String {
        pick([
            "What amount are you thinking about? Tell me and I'll check.",
            "How much did you have in mind? I'll see if you can cover it.",
            "Tell me the amount and I'll check against your balance.",
        ])
    }

    // MARK: - Safety

    static func sendSafety() -> String {
        "Sending Bitcoin is irreversible — always double-check the address. This wallet signs locally and never exposes your keys."
    }

    static func receiveSafety() -> String {
        "Sharing your receive address is safe — like a bank account number. They can send TO it but can't take FROM it. For privacy, use a new address each time."
    }

    static func generalSafety() -> String {
        "This is self-custodial — keys never leave your device, encrypted by Secure Enclave. Keep your **seed phrase** backed up safely and you're good."
    }
}
