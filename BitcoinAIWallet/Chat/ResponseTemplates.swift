// MARK: - ResponseTemplates.swift
// Bitcoin AI Wallet
//
// Dynamic response templates for the AI chat assistant.
// Uses variation pools (3-5 per response) to avoid repetition,
// time-aware greetings, context-aware balance responses,
// and intelligent fallbacks.
//
// Templates embed formatting tokens ({{amount:}}, **bold**, etc.)
// that MessageFormatter parses at display time.
//
// Platform: iOS 17.0+
// Framework: Foundation

import Foundation

// MARK: - ResponseTemplates

struct ResponseTemplates {

    // MARK: - Variation Helper

    /// Picks a random item from an array. Falls back to the first element.
    private static func pick(_ options: [String]) -> String {
        options.randomElement() ?? options[0]
    }

    // MARK: - Greeting

    static func greeting(walletName: String?) -> String {
        if let name = walletName {
            return L10n.Format.greetingWithName(name)
        }
        return L10n.Chat.greeting
    }

    /// Time-aware greeting with 3 variations per period.
    static func timeAwareGreeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 {
            return pick([
                "Good morning! What can I help you with?",
                "Morning! How can I help?",
                "Good morning! What would you like to do?",
            ])
        } else if hour < 17 {
            return pick([
                "Good afternoon! What would you like to do?",
                "Hey there! Need anything this afternoon?",
                "Afternoon! What can I do for you?",
            ])
        } else {
            return pick([
                "Good evening! Need anything?",
                "Evening! What can I help with?",
                "Hey! What are you looking to do tonight?",
            ])
        }
    }

    // MARK: - Social Responses

    /// Response to "thanks", "thank you", etc.
    static func thankYouResponse() -> String {
        pick([
            "Happy to help!",
            "Anytime! Let me know if you need anything else.",
            "You're welcome!",
            "No problem! I'm here whenever you need me.",
            "Glad I could help!",
        ])
    }

    /// First interaction response — user's first message after the welcome greeting.
    /// Warm, tells them what we can do.
    static func firstInteractionResponse() -> String {
        pick([
            "Hey! I can help you **send**, **receive**, check your **balance**, **fees**, **price** — just ask!",
            "Hi there! Just tell me what you need — **balance**, **send**, **receive**, **fees**, or anything else.",
            "Hey! Ask me anything — check your **balance**, **send** Bitcoin, view **fees**, get the **price**, and more.",
        ])
    }

    /// Response to positive social interactions (lol, haha, etc.)
    static func socialPositiveResponse() -> String {
        pick([
            "Anything else I can help with?",
            "Need anything else?",
            "I'm here if you need me!",
        ])
    }

    // MARK: - Balance

    static func balanceResponse(btcAmount: String, fiatAmount: String, pendingAmount: String?, utxoCount: Int) -> String {
        var lines: [String] = []
        let intro = pick([
            "Your balance is **\(btcAmount) BTC** (\(fiatAmount)).",
            "You have **\(btcAmount) BTC** (\(fiatAmount)).",
            "Current balance: **\(btcAmount) BTC** (\(fiatAmount)).",
        ])
        lines.append(intro)
        lines.append("")
        lines.append("{{amount:\(btcAmount) BTC}}  {{fiat:\(fiatAmount)}}")
        lines.append("")
        lines.append("• \(L10n.Wallet.availableBalance): **\(btcAmount) BTC**")
        if let pending = pendingAmount {
            lines.append("• \(L10n.Wallet.pendingBalance): **\(pending) BTC**")
        }
        lines.append("• \(L10n.Wallet.utxoCount): **\(utxoCount)**")
        lines.append("")
        lines.append("{{dim:\(L10n.Wallet.lastUpdated): \(localizedString("chat.just_now"))}}")
        return lines.joined(separator: "\n")
    }

    // MARK: - Context-Aware Balance

    /// Balance response after a recent send — "After sending X, you have Y left."
    static func balanceAfterSend(btcAmount: String, fiatAmount: String, sentAmount: String, pendingAmount: String?, utxoCount: Int) -> String {
        var lines: [String] = []
        let intro = pick([
            "After sending **\(sentAmount) BTC**, here's where you stand:",
            "Post-send balance update:",
            "After that send, you have:",
        ])
        lines.append(intro)
        lines.append("")
        lines.append("{{amount:\(btcAmount) BTC}}  {{fiat:\(fiatAmount)}}")
        lines.append("")
        lines.append("• \(L10n.Wallet.availableBalance): **\(btcAmount) BTC**")
        if let pending = pendingAmount {
            lines.append("• \(L10n.Wallet.pendingBalance): **\(pending) BTC**")
        }
        lines.append("• \(L10n.Wallet.utxoCount): **\(utxoCount)**")
        return lines.joined(separator: "\n")
    }

    /// Balance response when nothing changed since last check.
    static func balanceUnchanged(btcAmount: String, fiatAmount: String, utxoCount: Int) -> String {
        var lines: [String] = []
        let intro = pick([
            "Still sitting at **\(btcAmount) BTC** — no changes.",
            "Same as before: **\(btcAmount) BTC**.",
            "No change since your last check.",
        ])
        lines.append(intro)
        lines.append("")
        lines.append("{{amount:\(btcAmount) BTC}}  {{fiat:\(fiatAmount)}}")
        lines.append("")
        lines.append("• \(L10n.Wallet.utxoCount): **\(utxoCount)**")
        return lines.joined(separator: "\n")
    }

    // MARK: - Send

    static func sendConfirmation() -> String {
        pick([
            "Here's your transaction summary. Please review and confirm.",
            "Review the details below and confirm when ready.",
            "Transaction ready. Take a look and confirm to send.",
        ])
    }

    static func sendSuccess(txid: String) -> String {
        var lines: [String] = []
        let intro = pick([
            "Transaction broadcast successfully!",
            "Your Bitcoin is on its way!",
            "Sent! Transaction broadcast to the network.",
        ])
        lines.append("{{green:\(intro)}}")
        lines.append("")
        lines.append("• \(L10n.History.txid): {{address:\(txid)}}")
        return lines.joined(separator: "\n")
    }

    static func sendFailed(reason: String) -> String {
        let intro = pick([
            "Transaction failed: \(reason)",
            "Couldn't complete the send. \(reason)",
            "The transaction didn't go through. \(reason)",
        ])
        return "{{red:\(intro)}}"
    }

    static func insufficientFunds(available: String) -> String {
        var lines: [String] = []
        lines.append("{{red:\(L10n.Chat.insufficientFunds)}}")
        lines.append("")
        lines.append("• \(L10n.Wallet.availableBalance): **\(available) BTC**")
        return lines.joined(separator: "\n")
    }

    static func invalidAddress() -> String {
        "{{red:\(L10n.Chat.invalidAddress)}}"
    }

    // MARK: - Receive

    static func receiveAddress(address: String, type: String) -> String {
        var lines: [String] = []
        let intro = pick([
            "Here's your \(type) receive address:",
            "Send Bitcoin to this \(type) address:",
            "Your \(type) address for receiving:",
        ])
        lines.append(intro)
        lines.append("")
        lines.append("{{address:\(address)}}")
        lines.append("")
        lines.append("• \(L10n.Receive.addressType): **\(type)**")
        if type.lowercased().contains("taproot") {
            lines.append("")
            lines.append("{{dim:\(L10n.Chat.taprootNote)}}")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - History

    static func historyResponse(count: Int) -> String {
        if count == 0 { return noTransactions() }
        return pick([
            "Here are your last \(count) transactions.",
            "Showing \(count) recent transactions.",
            "Your recent activity — \(count) transactions.",
        ])
    }

    static func noTransactions() -> String {
        L10n.History.noTransactions
    }

    // MARK: - Fee

    static func feeEstimateResponse(slow: String, medium: String, fast: String) -> String {
        var lines: [String] = []
        let intro = pick([
            "Current network fee estimates:",
            "Here are the latest fee rates:",
            "Network fees right now:",
        ])
        lines.append(intro)
        lines.append("")
        lines.append("• \(L10n.Fee.fast): **\(fast)**")
        lines.append("• \(L10n.Fee.medium): **\(medium)**")
        lines.append("• \(L10n.Fee.slow): **\(slow)**")
        return lines.joined(separator: "\n")
    }

    // MARK: - Price

    static func priceResponse(formattedPrice: String, currency: String) -> String {
        var lines: [String] = []
        let intro = pick([
            "Bitcoin is trading at **\(formattedPrice) \(currency)**.",
            "Current BTC price: **\(formattedPrice) \(currency)**.",
            "BTC/\(currency): **\(formattedPrice)**.",
        ])
        lines.append(intro)
        lines.append("")
        lines.append("{{amount:\(formattedPrice) \(currency)}}")
        return lines.joined(separator: "\n")
    }

    static func priceFetching() -> String {
        "{{dim:\(localizedString("chat.price_fetching"))}}"
    }

    // MARK: - Convert

    static func convertResponse(fiatAmount: String, currency: String, btcAmount: String) -> String {
        var lines: [String] = []
        lines.append("**\(fiatAmount)** \(currency) = {{amount:\(btcAmount) BTC}}")
        lines.append("")
        lines.append("{{dim:\(localizedFormat("chat.convert_response_template", fiatAmount, currency, btcAmount))}}")
        return lines.joined(separator: "\n")
    }

    // MARK: - New Address

    static func newAddressGenerated() -> String {
        "{{green:\(localizedString("chat.new_address_generated"))}}"
    }

    // MARK: - Wallet Health

    static func walletHealthResponse(balance: String, utxoCount: Int, pendingBalance: String, transactionCount: Int) -> String {
        var lines: [String] = []
        lines.append("**\(localizedString("chat.wallet_health_title"))**")
        lines.append("")
        lines.append("• \(L10n.Wallet.totalBalance): **\(balance) BTC**")
        lines.append("• \(L10n.Wallet.utxoCount): **\(utxoCount)**")
        if Decimal(string: pendingBalance) ?? 0 > 0 {
            lines.append("• \(L10n.Wallet.pendingBalance): **\(pendingBalance) BTC**")
        }
        lines.append("• \(localizedFormat("chat.transaction_count_label", transactionCount))")
        lines.append("")
        lines.append("{{green:\(localizedString("chat.wallet_health_status"))}}")
        return lines.joined(separator: "\n")
    }

    // MARK: - Export

    static func exportHistoryResponse() -> String {
        localizedString("chat.export_history_response")
    }

    // MARK: - UTXO

    static func utxoListResponse(count: Int) -> String {
        localizedFormat("chat.utxo_list_response", count)
    }

    // MARK: - Bump Fee

    static func bumpFeeResponse(txid: String?) -> String {
        if let txid = txid {
            var lines: [String] = []
            lines.append(localizedString("chat.bump_fee_intro"))
            lines.append("")
            lines.append("• \(L10n.History.txid): {{address:\(txid)}}")
            return lines.joined(separator: "\n")
        }
        return localizedString("chat.bump_fee_response")
    }

    // MARK: - Network Status

    static func networkStatusResponse(isConnected: Bool) -> String {
        if isConnected {
            return "{{green:\(localizedString("chat.network_connected"))}}"
        }
        return "{{red:\(localizedString("chat.network_disconnected"))}}"
    }

    // MARK: - About

    static func aboutResponse() -> String {
        localizedString("chat.about_response")
    }

    // MARK: - Smart Fallback

    static func smartFallback() -> String {
        pick([
            "I'm not sure what you mean. Try **balance**, **send**, **receive**, **fees**, or **price**.",
            "Hmm, I didn't catch that. Could you rephrase?",
            "Not sure I follow. Say **help** to see what I can do.",
        ])
    }

    /// Intelligent fallback using classification alternatives.
    /// Never says "unknown command" — instead offers helpful guesses.
    static func smartFallbackWithGuess(bestGuess: WalletIntent?, confidence: Double, alternatives: [IntentScore]) -> String {
        // High-ish confidence with a single best guess
        if let guess = bestGuess, confidence >= 0.3 {
            let name = guess.friendlyName
            let suggestion = intentSuggestion(guess)
            return pick([
                "I'm not quite sure what you mean. Did you want to check your **\(name)**?\n\n{{dim:Try: \"\(suggestion)\"}}",
                "Hmm, I think you might be asking about **\(name)**.\n\n{{dim:Try saying: \"\(suggestion)\"}}",
                "I didn't quite catch that. Were you looking for **\(name)**?\n\n{{dim:You can say: \"\(suggestion)\"}}",
            ])
        }

        // Multiple possible alternatives
        if alternatives.count >= 2 {
            let top2 = alternatives.prefix(2).map { "**\($0.intent.friendlyName)**" }
            return "I'm not sure what you're looking for. Did you mean \(top2[0]) or \(top2[1])?\n\n{{dim:Say **\"help\"** to see everything I can do.}}"
        }

        // No clue at all — be helpful, not dismissive
        return pick([
            "I didn't quite get that. I can help with your **balance**, **sending**, **receiving**, **fees**, **price**, and more.\n\n{{dim:Say **\"help\"** for the full list.}}",
            "Not sure I understood. Try asking about your **balance**, **transactions**, or **fees**.\n\n{{dim:Say **\"help\"** to see all commands.}}",
            "Hmm, I'm not sure what you need. Here are some things I can do:\n\n• Check your **balance**\n• **Send** or **receive** Bitcoin\n• Show **fee estimates**\n• Check the **price**\n\n{{dim:Say **\"help\"** for more.}}",
        ])
    }

    /// Returns a sample command for a given intent type.
    private static func intentSuggestion(_ intent: WalletIntent) -> String {
        switch intent {
        case .balance: return "balance"
        case .send: return "send 0.001 BTC to bc1q..."
        case .receive: return "receive"
        case .history: return "show my history"
        case .feeEstimate: return "fees"
        case .price: return "btc price"
        case .convertAmount: return "$50 in BTC"
        case .walletHealth: return "wallet health"
        case .utxoList: return "show my UTXOs"
        case .networkStatus: return "network status"
        case .help: return "help"
        default: return "help"
        }
    }

    // MARK: - Nothing to Confirm

    static func nothingToConfirm() -> String {
        localizedString("chat.nothing_to_confirm")
    }

    // MARK: - Transaction Status

    static func pendingTransaction(confirmations: Int) -> String {
        "{{status:pending}} \(L10n.Chat.pendingNotice) {{dim:(\(L10n.Format.confirmationCount(confirmations)))}}"
    }

    static func confirmedTransaction() -> String {
        "{{status:success}} \(L10n.Chat.confirmedNotice)"
    }

    // MARK: - Errors

    static func networkError() -> String {
        "{{red:\(L10n.Error.network)}}"
    }

    static func walletNotReady() -> String {
        "{{red:\(L10n.Error.walletNotReady)}}"
    }

    static func unknownCommand() -> String { L10n.Chat.unknownCommand }

    static func genericError(_ message: String) -> String {
        "{{red:\(L10n.Common.error):}} \(message)"
    }

    // MARK: - Help

    static func helpResponse() -> String {
        var lines: [String] = []
        let intro = pick([
            "Here's what I can help with:",
            "I can do a lot! Here's a quick guide:",
            "Need a hand? Here's what I can do:",
        ])
        lines.append("**\(intro)**")
        lines.append("")
        lines.append("• \(L10n.QuickAction.send): **\"send 0.005 to bc1q...\"**")
        lines.append("• \(L10n.QuickAction.receive): **\"receive\"** or **\"my address\"**")
        lines.append("• \(L10n.Wallet.balance): **\"balance\"** or **\"how much do I have\"**")
        lines.append("• \(L10n.QuickAction.history): **\"history\"** or **\"last 5 transactions\"**")
        lines.append("• \(L10n.QuickAction.fees): **\"fees\"** or **\"fee estimate\"**")
        lines.append("• Price: **\"price\"** or **\"btc price in EUR\"**")
        lines.append("• Convert: **\"$50\"** or **\"100 EUR\"**")
        lines.append("• Wallet Health: **\"wallet health\"**")
        lines.append("• New Address: **\"new address\"**")
        lines.append("• UTXOs: **\"utxo\"** or **\"unspent outputs\"**")
        lines.append("• Network: **\"network status\"**")
        lines.append("• \(L10n.QuickAction.settings): **\"settings\"**")
        return lines.joined(separator: "\n")
    }

    // MARK: - Prompts

    static func askForAddress() -> String {
        localizedString("chat.ask_for_address")
    }

    static func askForAmount() -> String {
        localizedString("chat.ask_for_amount")
    }

    /// Varied address prompt for the send flow.
    static func askForAddressVaried() -> String {
        pick([
            localizedString("chat.ask_for_address"),
            "Where should I send it? Paste or type the Bitcoin address.",
            "Got it. What's the receiving address?",
        ])
    }

    /// Varied amount prompt for the send flow.
    static func askForAmountVaried() -> String {
        pick([
            localizedString("chat.ask_for_amount"),
            "How much would you like to send? (BTC or sats)",
            "What amount? You can say BTC or sats.",
        ])
    }

    static func askToConfirm() -> String { L10n.Chat.sendConfirmPrompt }

    static func askForFeeLevel() -> String {
        "• \(L10n.Fee.slow)\n• \(L10n.Fee.medium)\n• \(L10n.Fee.fast)"
    }

    // MARK: - Transaction Detail

    static func transactionDetail(txid: String, type: String, amount: String, address: String, confirmations: Int, date: String) -> String {
        let isSent = type == "sent"
        let status: StatusType = confirmations >= 6 ? .success : .pending
        let statusLabel = status == .success ? L10n.History.confirmed : L10n.History.pending
        let amountPrefix = isSent ? "-" : "+"
        let colorToken = isSent ? "red" : "green"

        var lines: [String] = []
        lines.append("{{status:\(status.rawValue)}} **\(statusLabel)** {{dim:(\(L10n.Format.confirmationCount(confirmations)))}}")
        lines.append("")
        lines.append("• \(L10n.Send.amount): {{\(colorToken):\(amountPrefix)\(amount) BTC}}")
        lines.append("• \(isSent ? L10n.Send.to : L10n.Send.from): {{address:\(address)}}")
        lines.append("• \(L10n.History.txid): {{address:\(txid)}}")
        lines.append("• \(L10n.Chat.today): **\(date)**")
        return lines.joined(separator: "\n")
    }

    // MARK: - Cancellation

    static func operationCancelled() -> String {
        "{{dim:\(localizedString("chat.operation_cancelled"))}}"
    }

    /// Varied cancellation response.
    static func operationCancelledVaried() -> String {
        pick([
            "{{dim:\(localizedString("chat.operation_cancelled"))}}",
            "{{dim:No worries, cancelled. What would you like to do instead?}}",
            "{{dim:Cancelled. Let me know when you're ready.}}",
        ])
    }

    // MARK: - Processing

    static func processingTransaction() -> String { L10n.Send.signing }

    // MARK: - Hide / Show Balance

    static func balanceHidden() -> String {
        "{{green:\(localizedString("chat.balance_hidden"))}}"
    }

    static func balanceShown() -> String {
        "{{green:\(localizedString("chat.balance_shown"))}}"
    }

    // MARK: - Refresh

    static func walletRefreshing() -> String {
        "{{dim:\(localizedString("chat.wallet_refreshing"))}}"
    }

    static func walletRefreshed() -> String {
        "{{green:\(localizedString("chat.wallet_refreshed"))}}"
    }

    // MARK: - Settings

    static func openingSettings() -> String {
        "{{green:\(L10n.Settings.title)...}}"
    }

    // MARK: - Emotion Responses

    static func emotionResponse(for emotion: String, context: String?) -> String {
        switch emotion {
        case "gratitude":
            return pick([
                "Happy to help! Need anything else?",
                "Anytime! What's next?",
                "You're welcome! Let me know if you need anything.",
            ])
        case "frustration":
            return pick([
                "I'm sorry you're having trouble. Let me help — what exactly isn't working?",
                "Sorry about that. Can you tell me more about what went wrong?",
                "I understand the frustration. Let me try to help fix this.",
            ])
        case "confusion":
            return pick([
                "No worries! Ask me anything — I'm here to help.",
                "Let me try to explain that differently. What part is unclear?",
                "No problem! Feel free to ask, and I'll do my best to clarify.",
            ])
        case "humor":
            return "What else can I help you with?"
        case "sadness":
            return "I'm sorry to hear that. If you believe your wallet has been compromised, the most important step is to **move your remaining funds to a new wallet immediately**. Would you like help with that?"
        case "ellipsis":
            return pick([
                "Take your time! Let me know how I can help.",
                "No rush — I'm here when you're ready.",
                "Whenever you're ready, just let me know.",
            ])
        case "hesitant":
            return pick([
                "What are you thinking about? I can help with sending, checking your balance, fees, and more.",
                "Take your time! Need help with anything?",
                "I'm here whenever you need me. Just ask!",
            ])
        default:
            return pick([
                "How can I help you?",
                "What would you like to do?",
                "What can I do for you?",
            ])
        }
    }

    // MARK: - Punctuation-Aware Responses

    static func questionAboutAction(_ action: String) -> String {
        switch action {
        case "send":
            return pick([
                "Want to send Bitcoin? Just tell me the amount and address. For example: **send 0.005 to bc1q...**",
                "To send Bitcoin, I'll need an amount and destination address. Ready to start?",
                "I can help you send Bitcoin! Just provide the amount and address.",
            ])
        case "receive":
            return pick([
                "Want to receive Bitcoin? I'll show you your address and QR code. Just say **receive**.",
                "To receive Bitcoin, share your address with the sender. Say **receive** to see it.",
                "I can show you your receive address. Just say the word!",
            ])
        default:
            return "Would you like me to help with that? Just let me know!"
        }
    }
}
