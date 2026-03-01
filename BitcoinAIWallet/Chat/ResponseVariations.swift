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
            "I'm here whenever you're ready.",
            "Take your time — just let me know what you need.",
            "No rush. I'm standing by.",
            "Whenever you're ready, I'm here to help.",
        ])
    }

    // MARK: - Bare Question Rephrase

    static func rephrasePrefix() -> String {
        pick([
            "Let me put that another way:",
            "Here's a simpler way to think about it:",
            "In other words:",
            "To break it down differently:",
        ])
    }

    static func explainMore(topic: String) -> String {
        pick([
            "Sure, let me tell you more about \(topic).",
            "Here's what you should know about \(topic).",
            "Good question — here's more on \(topic):",
            "Let me dig into \(topic) for you.",
        ])
    }

    static func whatToKnow() -> String {
        pick([
            "What would you like to know more about?",
            "Ask me anything — I'm happy to help.",
            "What can I explain for you?",
            "Curious about something? Fire away.",
        ])
    }

    // MARK: - Evaluation Responses

    static func tooMuchFee() -> String {
        pick([
            "That does seem high. Want me to switch to a slower, cheaper fee?",
            "I can lower the fee for you — it'll take a bit longer but save you money.",
            "Fair point. Let's use a more economical fee level.",
            "I hear you. Want me to find a cheaper fee option?",
        ])
    }

    static func tooMuchAmount(halfAmount: String) -> String {
        pick([
            "Want to scale it back? Half would be **\(halfAmount)**.",
            "That's a big one. How about **\(halfAmount)** instead?",
            "We could go smaller — half would be **\(halfAmount)**.",
            "Understood. Want to try **\(halfAmount)** instead?",
        ])
    }

    static func tooLittleAmount(doubleAmount: String) -> String {
        pick([
            "Want to bump it up? Double would be **\(doubleAmount)**.",
            "We could go higher — double is **\(doubleAmount)**.",
            "That's on the low side. How about **\(doubleAmount)**?",
            "If you'd like more, double would bring it to **\(doubleAmount)**.",
        ])
    }

    static func whatToAdjust() -> String {
        pick([
            "I understand. What would you like to adjust?",
            "No problem. Tell me what to change.",
            "Got it. What should we modify?",
            "Sure thing. What would you like me to tweak?",
        ])
    }

    static func whatToIncrease() -> String {
        pick([
            "What would you like to increase?",
            "What should I bump up for you?",
            "Tell me what you'd like to raise.",
            "Which part do you want me to increase?",
        ])
    }

    static func enoughConfirm() -> String {
        pick([
            "Looks good. Ready to confirm?",
            "Everything checks out. Shall we proceed?",
            "Sounds right to me. Want to go ahead?",
            "All set. Ready to lock it in?",
        ])
    }

    static func gladToHear() -> String {
        pick([
            "Glad to hear it. Anything else I can do?",
            "Great. Let me know if you need anything else.",
            "Good to hear. What else can I help with?",
            "Nice. I'm here if you need me.",
        ])
    }

    static func gotIt() -> String {
        pick([
            "Got it. What would you like to do?",
            "Understood. How can I help?",
            "Alright. What's next?",
            "Noted. What would you like to do now?",
        ])
    }

    // MARK: - Comparative Responses

    static func feeIncrease() -> String {
        pick([
            "Switching to **fast** — should confirm in about 10 minutes.",
            "Bumping to priority fee for quicker confirmation.",
            "Moving to **fast**. You'll be in the next block or two.",
            "Done. Priority fee selected for faster processing.",
        ])
    }

    static func feeDecrease() -> String {
        pick([
            "Switching to **economy** — takes longer but saves you money.",
            "Dropping to a lower fee. It'll take a bit more time, but you'll pay less.",
            "Using **slow** fee. Expect about an hour, but the savings are worth it.",
            "Lowered the fee for you. It'll take longer but cost less.",
        ])
    }

    static func amountIncrease(newAmount: String) -> String {
        pick([
            "Increased to **\(newAmount)** BTC. Look right?",
            "Bumped it up to **\(newAmount)** BTC. Does that work?",
            "Updated to **\(newAmount)** BTC. Good to go?",
            "Now set to **\(newAmount)** BTC. Sound right?",
        ])
    }

    static func amountDecrease(newAmount: String) -> String {
        pick([
            "Reduced to **\(newAmount)** BTC. Better?",
            "Brought it down to **\(newAmount)** BTC. How's that?",
            "Updated to **\(newAmount)** BTC. Does that look right?",
            "Now set to **\(newAmount)** BTC. Good?",
        ])
    }

    static func whatToModify() -> String {
        pick([
            "What would you like to adjust?",
            "What should I change for you?",
            "Tell me what to modify and I'll take care of it.",
            "What part needs changing?",
        ])
    }

    // MARK: - Emotion Responses

    static func gratitude(lastSendAmount: String?) -> String {
        if let amount = lastSendAmount {
            return "You're welcome. Your **\(amount) BTC** send is on its way."
        }
        return pick([
            "Happy to help. Let me know if you need anything else.",
            "Anytime. I'm here whenever you need me.",
            "You're welcome. That's what I'm here for.",
            "Glad I could help. What else can I do for you?",
            "No problem at all.",
        ])
    }

    static func frustration() -> String {
        pick([
            "I hear you. Let me help — can you tell me what went wrong?",
            "Sorry about that. Let's figure this out together.",
            "I understand the frustration. Walk me through what happened and I'll do my best.",
            "That's no good. Let me see what I can do to fix this.",
            "I'm sorry you're running into trouble. What exactly isn't working?",
        ])
    }

    static func confusion(lastTopic: String?) -> String {
        if let topic = lastTopic {
            return "No worries — let me explain \(topic) a different way."
        }
        return pick([
            "No problem. Try saying **\"help\"** to see everything I can do.",
            "Let me try explaining that differently. What part is unclear?",
            "Totally fine — I'm here to help. What's tripping you up?",
            "No worries. Ask me anything and I'll do my best to clarify.",
        ])
    }

    static func humor() -> String {
        pick([
            "Ha, good one. But seriously, what can I help you with?",
            "Love it. Now, anything I can actually do for you?",
            "You've got jokes. Alright, what do you need?",
        ])
    }

    static func concern() -> String {
        pick([
            "That's a fair concern. Your keys never leave this device — your funds are safe. What's on your mind?",
            "I get it. Security matters. Everything is encrypted locally on your device. How can I help?",
            "Totally understandable. Rest assured, your private keys stay on your device and are protected by the Secure Enclave. What would you like to know?",
        ])
    }

    static func excitement(balance: String?) -> String {
        if let bal = balance {
            return "Looking good with **\(bal) BTC**. What would you like to do next?"
        }
        return pick([
            "Love the energy. What would you like to do?",
            "Right there with you. What's next?",
            "Great vibes. How can I help?",
            "Let's make it happen. What do you need?",
        ])
    }

    static func impatience() -> String {
        pick([
            "On it. What do you need?",
            "Right away — what can I do for you?",
            "I'm here. Tell me what you need.",
            "Let's go. What can I help with?",
        ])
    }

    // MARK: - Farewell

    static func farewell() -> String {
        pick([
            "Take care! Your wallet is safe and sound. Come back anytime.",
            "See you later! Your Bitcoin isn't going anywhere.",
            "Goodbye! I'll be here whenever you need me.",
            "Until next time! Your funds are secure.",
            "Bye for now! Stay safe out there.",
        ])
    }

    // MARK: - Affordability

    static func canAfford(target: String, remaining: String) -> String {
        pick([
            "Yes, you can cover that. Sending **\(target)** would leave you with **\(remaining) BTC**.",
            "You're good. After sending **\(target)**, you'd still have **\(remaining) BTC**.",
            "That's well within your balance. **\(remaining) BTC** would remain after sending **\(target)**.",
            "Absolutely. **\(target)** is covered, with **\(remaining) BTC** to spare.",
        ])
    }

    static func barelyAfford(balance: String) -> String {
        pick([
            "Just barely. That would use your entire **\(balance)** balance, leaving nothing for future fees.",
            "Technically yes, but you'd spend your full **\(balance)** with nothing left over.",
            "It's possible, but it would drain your **\(balance)** balance completely. You'd want to keep some aside for fees.",
            "You could, but it would zero out your **\(balance)** balance. I'd recommend keeping a small cushion.",
        ])
    }

    static func cantAfford(shortBy: String, balance: String, target: String) -> String {
        pick([
            "Not enough, unfortunately. You're short by **\(shortBy)** BTC. Your balance is **\(balance)**, and you need **\(target)**.",
            "That's more than your current balance. You have **\(balance)** but need **\(target)** — short by **\(shortBy)** BTC.",
            "You'd need **\(shortBy)** BTC more to cover that. Current balance: **\(balance)**, required: **\(target)**.",
            "You're **\(shortBy)** BTC short. Balance is **\(balance)**, but **\(target)** is needed.",
        ])
    }

    static func affordAskAmount() -> String {
        pick([
            "What amount are you thinking? Tell me and I'll check your balance.",
            "How much did you have in mind? I'll see if you can cover it.",
            "Let me know the amount and I'll check it against your balance.",
            "Give me a number and I'll tell you if you're good.",
        ])
    }

    // MARK: - Safety

    static func sendSafety() -> String {
        pick([
            "Keep in mind, Bitcoin transactions are irreversible — always double-check the address before confirming. Your keys never leave this device.",
            "Important: once sent, Bitcoin transactions can't be reversed. Make sure the address is correct. Everything is signed locally on your device.",
            "A quick reminder — Bitcoin sends are permanent. Verify the address carefully. This wallet signs transactions locally and never exposes your keys.",
        ])
    }

    static func receiveSafety() -> String {
        pick([
            "Sharing your receive address is perfectly safe — it's like giving someone your bank account number. They can send to it, but they can't take from it. For better privacy, use a fresh address each time.",
            "Your receive address is safe to share. People can only send bitcoin to it, not withdraw. I'd recommend using a new address for each transaction for privacy.",
            "Don't worry, sharing this address is safe. The sender can only deposit to it. For best privacy, generate a new address for each payment.",
        ])
    }

    static func generalSafety() -> String {
        pick([
            "This is a self-custodial wallet — your keys never leave this device and are protected by the Secure Enclave. As long as your **seed phrase** is backed up safely, you're in good shape.",
            "Your wallet is fully self-custodial. Private keys are encrypted on-device via the Secure Enclave. Just make sure your **seed phrase** backup is stored somewhere safe.",
            "Security-wise, you're solid. Your keys stay on this device, protected by hardware encryption. The only thing to safeguard is your **seed phrase** — keep it offline and private.",
        ])
    }
}
