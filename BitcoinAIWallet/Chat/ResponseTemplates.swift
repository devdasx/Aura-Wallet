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

    // MARK: - Social Responses

    /// Response to "thanks", "thank you", etc.
    static func thankYouResponse() -> String {
        pick([
            "Happy to help. Let me know if you need anything else.",
            "Anytime. I'm here whenever you need me.",
            "You're welcome. That's what I'm here for.",
            "No problem at all. What else can I do for you?",
            "Glad I could help.",
        ])
    }

    /// First interaction response — user's first message after the welcome greeting.
    /// Warm, tells them what we can do.
    static func firstInteractionResponse() -> String {
        pick([
            "Hey, I can help you **send**, **receive**, check your **balance**, view **fees**, get the **price** — just ask.",
            "Hi there. Tell me what you need — **balance**, **send**, **receive**, **fees**, or anything else.",
            "Welcome. I can check your **balance**, **send** bitcoin, show **fees**, get the **price**, and more. Just say the word.",
            "Good to see you. Ask me anything — **balance**, **send**, **receive**, **price**, **fees**, and beyond.",
        ])
    }

    /// Response to positive social interactions (lol, haha, etc.)
    static func socialPositiveResponse() -> String {
        pick([
            "Anything else I can help with?",
            "Need anything else?",
            "I'm here if you need me.",
            "Let me know if there's something else I can do.",
        ])
    }

    // MARK: - Balance

    static func balanceResponse(btcAmount: String, fiatAmount: String, pendingAmount: String?, utxoCount: Int) -> String {
        var lines: [String] = []
        let intro = pick([
            "You're holding **\(btcAmount) BTC** right now — that's about \(fiatAmount).",
            "Your balance is **\(btcAmount) BTC** (\(fiatAmount)).",
            "You've got **\(btcAmount) BTC** in your wallet (\(fiatAmount)).",
            "Current balance: **\(btcAmount) BTC**, worth roughly \(fiatAmount).",
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
            "Your updated balance after that **\(sentAmount) BTC** send:",
            "Send complete. Here's your remaining balance:",
            "That **\(sentAmount) BTC** is on its way. Here's what you have left:",
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
            "Still at **\(btcAmount) BTC** — no changes since you last checked.",
            "Same as before: **\(btcAmount) BTC**. Nothing new.",
            "No change. You're still holding **\(btcAmount) BTC**.",
            "Balance unchanged at **\(btcAmount) BTC**.",
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
            "Here's your transaction summary. Please review everything before confirming.",
            "Ready to send. Take a moment to review the details below.",
            "Transaction prepared. Look it over and confirm when you're satisfied.",
            "I've put together the details. Review and confirm to send.",
        ])
    }

    static func sendSuccess(txid: String) -> String {
        var lines: [String] = []
        let intro = pick([
            "Done. Your transaction has been broadcast to the network.",
            "Sent successfully. Your bitcoin is on its way.",
            "Transaction broadcast. It should start confirming shortly.",
            "All done. Your bitcoin has been sent.",
        ])
        lines.append("{{green:\(intro)}}")
        lines.append("")
        lines.append("• \(L10n.History.txid): {{address:\(txid)}}")
        return lines.joined(separator: "\n")
    }

    static func sendFailed(reason: String) -> String {
        let intro = pick([
            "Something went wrong with the transaction. \(reason)",
            "The send didn't go through. \(reason)",
            "Transaction failed. \(reason)",
            "We hit a problem. \(reason)",
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
            "Here's your \(type) receiving address. Share it with the sender or scan the QR code.",
            "Your \(type) address is ready. Anyone can send bitcoin to this address.",
            "Fresh \(type) address below. Share it or use the QR code.",
            "Here's a \(type) address for receiving bitcoin:",
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
            "Showing your \(count) most recent transactions.",
            "Your recent activity — \(count) transactions:",
            "Here's what's been happening — \(count) transactions:",
        ])
    }

    static func noTransactions() -> String {
        L10n.History.noTransactions
    }

    // MARK: - Fee

    static func feeEstimateResponse(slow: String, medium: String, fast: String) -> String {
        var lines: [String] = []
        let intro = pick([
            "Here are the current network fees. Pick the speed that works for you.",
            "Network fee estimates are in. I'd recommend **medium** for most transactions.",
            "Current fee rates below. Fast gets you in the next block or two.",
            "Here's what the network is charging right now:",
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
            "Bitcoin is trading at **\(formattedPrice) \(currency)** right now.",
            "Current BTC price: **\(formattedPrice) \(currency)**.",
            "1 BTC = **\(formattedPrice) \(currency)** as of right now.",
            "The latest price is **\(formattedPrice) \(currency)**.",
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

    // MARK: - Explain Topic

    static func explainTopicResponse(topic: String) -> String {
        let explanations: [String: String] = [
            "bitcoin": "**Bitcoin** is a decentralized digital currency created in 2009 by Satoshi Nakamoto. It allows peer-to-peer transactions without intermediaries like banks. Transactions are verified by network nodes through cryptography and recorded on a public ledger called a blockchain.",
            "wallet": "A **Bitcoin wallet** stores the cryptographic keys you need to send and receive Bitcoin. It doesn't actually store coins — those live on the blockchain. Your wallet holds the private keys that prove ownership and let you sign transactions.",
            "transactions": "A **Bitcoin transaction** transfers value from one address to another. Each transaction includes inputs (where the BTC comes from), outputs (where it goes), and a fee paid to miners. Transactions are broadcast to the network and confirmed when included in a block.",
            "fees": "**Transaction fees** are small amounts of Bitcoin paid to miners to include your transaction in a block. Fees are based on transaction size (in bytes), not the amount sent. Higher fees = faster confirmation. When the network is busy, fees rise.",
            "network": "The **Bitcoin network** is a peer-to-peer system of nodes that validate and relay transactions. Miners compete to add new blocks roughly every 10 minutes. The network's security comes from its distributed nature and proof-of-work consensus.",
            "mining": "**Mining** is the process of using computational power to solve cryptographic puzzles and add new blocks to the blockchain. Miners are rewarded with newly created Bitcoin (the block reward) plus transaction fees. This secures the network.",
            "halving": "The **halving** is an event that occurs roughly every 4 years (every 210,000 blocks) where the Bitcoin block reward is cut in half. This controls Bitcoin's inflation rate and ensures there will only ever be 21 million BTC.",
            "mempool": "The **mempool** (memory pool) is where unconfirmed transactions wait before being included in a block. When you send Bitcoin, your transaction sits in the mempool until a miner picks it up. Higher-fee transactions are prioritized.",
            "segwit": "**SegWit** (Segregated Witness) is a Bitcoin upgrade that separates signature data from transaction data. This reduces transaction size, lowers fees, and fixes transaction malleability. SegWit addresses start with **bc1q**.",
            "taproot": "**Taproot** is a Bitcoin upgrade that improves privacy, efficiency, and smart contract capabilities. It uses Schnorr signatures and makes complex transactions look like simple ones on-chain. Taproot addresses start with **bc1p**.",
            "lightning": "The **Lightning Network** is a Layer 2 payment protocol built on top of Bitcoin. It enables instant, low-fee micropayments by creating payment channels between users. Transactions settle on the Bitcoin blockchain when channels close.",
            "keys": "**Bitcoin keys** come in pairs: a private key (secret, used to sign transactions) and a public key (derived from the private key, used to create addresses). Never share your private key — anyone who has it can spend your Bitcoin.",
            "addresses": "A **Bitcoin address** is a string of characters that represents a destination for Bitcoin payments. There are several types: Legacy (1...), P2SH (3...), SegWit (bc1q...), and Taproot (bc1p...). Each type offers different features and fee structures.",
            "utxo": "A **UTXO** (Unspent Transaction Output) is a chunk of Bitcoin that hasn't been spent yet. Your wallet balance is the sum of all your UTXOs. When you send Bitcoin, you spend entire UTXOs and get change back as a new UTXO.",
            "blockchain": "The **blockchain** is a chain of blocks, each containing a batch of verified transactions. Once a block is added, it's extremely difficult to alter. Each block references the previous one, creating an immutable record of all Bitcoin transactions ever made.",
        ]

        if let explanation = explanations[topic.lowercased()] {
            return explanation
        }

        // Generic fallback for unrecognized topics
        return pick([
            "That's a great question about **\(topic)**. I don't have a detailed explanation for that topic yet. Try asking about **bitcoin**, **mining**, **fees**, **segwit**, **taproot**, or **lightning**.",
            "I don't have a specific explanation for **\(topic)** yet. You can ask me about core Bitcoin concepts like **wallets**, **transactions**, **UTXOs**, **keys**, or **addresses**.",
            "I'd love to explain **\(topic)**, but I don't have that one covered yet. I can tell you about **bitcoin**, **mining**, **halving**, **mempool**, **segwit**, and more.",
        ])
    }

    // MARK: - Smart Fallback

    static func smartFallback() -> String {
        pick([
            "I'm not sure what you mean. Try **balance**, **send**, **receive**, **fees**, or **price**.",
            "Hmm, I didn't quite get that. Could you rephrase, or say **help** to see what I can do?",
            "Not sure I followed that. You can ask me about your balance, send bitcoin, check prices, or say **help** for more.",
            "I didn't catch that. Here are some things to try: **balance**, **send**, **receive**, **fees**, **price**.",
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
                "I think you might be asking about **\(name)**. Is that right?\n\n{{dim:Try: \"\(suggestion)\"}}",
                "Sounds like you might want **\(name)**.\n\n{{dim:Try saying: \"\(suggestion)\"}}",
                "Did you mean **\(name)**? If so, here's how to ask:\n\n{{dim:Say: \"\(suggestion)\"}}",
                "I'm not 100% sure, but were you looking for **\(name)**?\n\n{{dim:You can say: \"\(suggestion)\"}}",
            ])
        }

        // Multiple possible alternatives
        if alternatives.count >= 2 {
            let top2 = alternatives.prefix(2).map { "**\($0.intent.friendlyName)**" }
            return "I'm not sure what you're after. Did you mean \(top2[0]) or \(top2[1])?\n\n{{dim:Say **\"help\"** to see everything I can do.}}"
        }

        // No clue at all — be helpful, not dismissive
        return pick([
            "I didn't quite catch that, but I can help with your **balance**, **sending**, **receiving**, **fees**, **price**, and more.\n\n{{dim:Say **\"help\"** for the full list.}}",
            "Not sure I understood. Try asking about your **balance**, **transactions**, or **fees**.\n\n{{dim:Say **\"help\"** to see all commands.}}",
            "Hmm, I'm not sure what you need. Here's what I can do:\n\n• Check your **balance**\n• **Send** or **receive** bitcoin\n• Show **fee estimates**\n• Check the **price**\n\n{{dim:Say **\"help\"** for more.}}",
            "I didn't get that one. You can ask me to check your **balance**, **send** bitcoin, show the **price**, or estimate **fees**.\n\n{{dim:Say **\"help\"** to see everything.}}",
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
            "Here's everything I can help with:",
            "Here's a quick guide to what I can do:",
            "Need a hand? Here's the full list:",
            "Here are all the things you can ask me:",
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
            "Got it. What's the destination address?",
            "Now I just need the receiving address. Paste it in or type it out.",
        ])
    }

    /// Varied amount prompt for the send flow.
    static func askForAmountVaried() -> String {
        pick([
            localizedString("chat.ask_for_amount"),
            "How much would you like to send? You can use BTC or sats.",
            "What amount should I send? BTC or sats both work.",
            "Tell me the amount. I accept BTC, sats, or a dollar value.",
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
            "{{dim:No problem, cancelled. No bitcoin was sent.}}",
            "{{dim:Cancelled. Your funds are untouched. What would you like to do instead?}}",
            "{{dim:All good — I've cancelled that for you. Let me know when you're ready.}}",
            "{{dim:Transaction cancelled. Nothing was sent.}}",
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
                "Happy to help. Let me know if you need anything else.",
                "Anytime. I'm here whenever you need me.",
                "You're welcome. That's what I'm here for.",
                "Glad I could help. What else can I do?",
            ])
        case "frustration":
            return pick([
                "I'm sorry you're having trouble. What exactly isn't working?",
                "Sorry about that. Walk me through what happened and I'll try to help.",
                "I understand the frustration. Let's figure this out together.",
                "That's not great. Tell me more and I'll do my best to fix it.",
            ])
        case "confusion":
            return pick([
                "No worries. Ask me anything — I'm happy to clarify.",
                "Let me try explaining that a different way. What part is unclear?",
                "Totally fine. Feel free to ask, and I'll break it down.",
                "No problem. Say **\"help\"** to see everything I can do, or just ask your question.",
            ])
        case "humor":
            return pick([
                "Ha, good one. Now, what can I actually help you with?",
                "Love it. Alright, what do you need?",
                "You've got jokes. Seriously though, what can I do for you?",
            ])
        case "sadness":
            return "I'm sorry to hear that. If you believe your wallet has been compromised, the most important step is to **move your remaining funds to a new wallet immediately**. Would you like help with that?"
        case "ellipsis":
            return pick([
                "I'm here whenever you're ready.",
                "Take your time. No rush at all.",
                "Whenever you're ready, just let me know.",
                "Standing by. Just say the word.",
            ])
        case "hesitant":
            return pick([
                "What's on your mind? I can help with sending, checking your balance, fees, and more.",
                "Take your time. I'm here when you need me.",
                "No rush. Let me know what you're thinking about.",
                "Need help deciding? Tell me what you're considering.",
            ])
        default:
            return pick([
                "How can I help you?",
                "What would you like to do?",
                "What can I do for you?",
                "I'm here. What do you need?",
            ])
        }
    }

    // MARK: - Punctuation-Aware Responses

    static func questionAboutAction(_ action: String) -> String {
        switch action {
        case "send":
            return pick([
                "Want to send bitcoin? Just tell me the amount and address. For example: **send 0.005 to bc1q...**",
                "To send bitcoin, I'll need an amount and a destination address. Ready when you are.",
                "I can help you send. Give me the amount and address, and I'll prepare the transaction.",
                "Sure, I can send bitcoin for you. Just tell me how much and where.",
            ])
        case "receive":
            return pick([
                "Want to receive bitcoin? I'll show you your address and QR code. Just say **receive**.",
                "To receive bitcoin, share your address with the sender. Say **receive** to see it.",
                "I can pull up your receiving address right now. Just say **receive**.",
                "Ready to receive? Say the word and I'll generate a fresh address for you.",
            ])
        default:
            return "Would you like me to help with that? Just let me know."
        }
    }
}
