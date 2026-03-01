import SwiftUI

// MARK: - CommandsData.swift
// Bitcoin AI Wallet
//
// Comprehensive reference of every command, phrase, and natural language
// pattern the AI chat engine understands. Organized by category for
// the CommandsReferenceView.
//
// 400+ commands across 30 categories covering every interaction mode:
// core operations, conversational phrases, knowledge topics, multi-language,
// adjustments, follow-ups, error recovery, and smart detection.
//
// Platform: iOS 17.0+

// MARK: - Data Models

struct CommandItem: Identifiable {
    let id = UUID()
    let example: String
    let description: String
}

struct CommandCategory: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let color: Color
    let commands: [CommandItem]
}

// MARK: - All Command Categories

enum CommandsData {

    static let allCategories: [CommandCategory] = [

        // ──────────────────────────────────────────────
        // 1. SMART CONVERSATIONAL COMMANDS
        // ──────────────────────────────────────────────
        CommandCategory(
            name: "Smart Conversational",
            icon: "text.bubble.fill",
            color: AppColors.brand,
            commands: [
                CommandItem(example: "I want to send bitcoin", description: "Starts the guided send flow"),
                CommandItem(example: "I'd like to check my balance", description: "Shows your current balance"),
                CommandItem(example: "Can you show me the price?", description: "Shows current BTC price"),
                CommandItem(example: "Help me send to bc1q...", description: "Starts send with a pre-filled address"),
                CommandItem(example: "I need a new address", description: "Generates a fresh receiving address"),
                CommandItem(example: "Tell me about my transactions", description: "Shows your transaction history"),
                CommandItem(example: "How much will it cost to send?", description: "Shows current fee estimates"),
                CommandItem(example: "What can you do?", description: "Shows help and all capabilities"),
                CommandItem(example: "I want to learn about bitcoin", description: "Enters knowledge/education mode"),
                CommandItem(example: "Can I afford to send 0.1 BTC?", description: "Checks balance vs. amount + fees"),
                CommandItem(example: "I'd like to receive some bitcoin", description: "Shows your receiving address and QR"),
                CommandItem(example: "Show me what's going on", description: "Shows wallet status overview"),
                CommandItem(example: "Is anything pending?", description: "Checks for unconfirmed transactions"),
                CommandItem(example: "How's my wallet doing?", description: "Runs wallet health check"),
                CommandItem(example: "I want to see my coins", description: "Lists your UTXOs"),
            ]
        ),

        // ──────────────────────────────────────────────
        // 2. CHECK BALANCE
        // ──────────────────────────────────────────────
        CommandCategory(
            name: "Check Balance",
            icon: "bitcoinsign.circle.fill",
            color: AppColors.warning,
            commands: [
                CommandItem(example: "balance", description: "Show your current BTC balance and fiat value"),
                CommandItem(example: "what's my balance", description: "Conversational balance check"),
                CommandItem(example: "how much do I have", description: "Natural language balance inquiry"),
                CommandItem(example: "how much bitcoin do I have", description: "Explicit BTC balance check"),
                CommandItem(example: "how many sats do I have", description: "Balance in satoshis"),
                CommandItem(example: "my btc", description: "Quick balance inquiry"),
                CommandItem(example: "my bitcoin", description: "Check your bitcoin holdings"),
                CommandItem(example: "my funds", description: "View your available funds"),
                CommandItem(example: "my coins", description: "Check your coin balance"),
                CommandItem(example: "check wallet", description: "Check wallet balance and status"),
                CommandItem(example: "check balance", description: "Direct balance check"),
                CommandItem(example: "show balance", description: "Display your current balance"),
                CommandItem(example: "total balance", description: "View total balance including pending"),
                CommandItem(example: "available balance", description: "View spendable balance only"),
                CommandItem(example: "remaining balance", description: "What's left after transactions"),
                CommandItem(example: "how much can I spend", description: "Check spendable amount"),
                CommandItem(example: "what's in my wallet", description: "Casual wallet check"),
                CommandItem(example: "am I rich", description: "Fun balance check with context"),
                CommandItem(example: "wallet balance", description: "Direct wallet balance query"),
                CommandItem(example: "balance in USD", description: "Show balance in US dollars"),
                CommandItem(example: "balance in sats", description: "Show balance in satoshis"),
            ]
        ),

        // ──────────────────────────────────────────────
        // 3. SEND BITCOIN
        // ──────────────────────────────────────────────
        CommandCategory(
            name: "Send Bitcoin",
            icon: "arrow.up.circle.fill",
            color: AppColors.error,
            commands: [
                CommandItem(example: "send", description: "Start a guided send flow -- AI walks you through it"),
                CommandItem(example: "send 0.005 to bc1q...", description: "Send a specific BTC amount to an address"),
                CommandItem(example: "send 50000 sats to bc1q...", description: "Send in satoshis"),
                CommandItem(example: "send $100 worth of bitcoin", description: "Send a fiat-denominated amount in BTC"),
                CommandItem(example: "send all", description: "Sweep your entire balance"),
                CommandItem(example: "send all to bc1q...", description: "Sweep your entire balance to an address"),
                CommandItem(example: "send max", description: "Send maximum amount minus fees"),
                CommandItem(example: "send max to bc1q...", description: "Send maximum amount possible"),
                CommandItem(example: "send everything to bc1q...", description: "Send all funds to an address"),
                CommandItem(example: "send half", description: "Send 50% of your balance"),
                CommandItem(example: "send 0.001 BTC", description: "Send a specific BTC amount (AI asks for address)"),
                CommandItem(example: "transfer 0.01 BTC to bc1q...", description: "Alternative keyword for sending"),
                CommandItem(example: "pay bc1q...", description: "Start a payment to an address"),
                CommandItem(example: "move 0.1 bitcoin to bc1q...", description: "Move bitcoin to another address"),
                CommandItem(example: "withdraw 0.5 BTC", description: "Withdraw from your wallet"),
                CommandItem(example: "send to bc1q...", description: "Provide address first -- AI asks for amount"),
                CommandItem(example: "0.005", description: "Just type an amount when AI asks for it"),
                CommandItem(example: "(paste an address)", description: "Paste a Bitcoin address -- AI starts send flow"),
            ]
        ),

        // ──────────────────────────────────────────────
        // 4. RECEIVE BITCOIN
        // ──────────────────────────────────────────────
        CommandCategory(
            name: "Receive Bitcoin",
            icon: "arrow.down.circle.fill",
            color: AppColors.success,
            commands: [
                CommandItem(example: "receive", description: "Show your receiving address with QR code"),
                CommandItem(example: "my address", description: "Display your current receive address"),
                CommandItem(example: "show address", description: "Show address with QR code"),
                CommandItem(example: "show qr", description: "Display QR code for receiving"),
                CommandItem(example: "qr code", description: "Generate QR code for your address"),
                CommandItem(example: "qr", description: "Quick QR code display"),
                CommandItem(example: "deposit", description: "Show deposit address"),
                CommandItem(example: "new address", description: "Generate a fresh receiving address"),
                CommandItem(example: "fresh address", description: "Get a new address for better privacy"),
                CommandItem(example: "another address", description: "Derive another unused address"),
                CommandItem(example: "generate address", description: "Derive the next unused address"),
                CommandItem(example: "receiving address", description: "Show your receiving address"),
                CommandItem(example: "give me an address", description: "Natural language address request"),
                CommandItem(example: "want to receive", description: "Start receive flow"),
            ]
        ),

        // ──────────────────────────────────────────────
        // 5. BITCOIN PRICE
        // ──────────────────────────────────────────────
        CommandCategory(
            name: "Bitcoin Price",
            icon: "chart.line.uptrend.xyaxis",
            color: AppColors.success,
            commands: [
                CommandItem(example: "price", description: "Current Bitcoin price in your default currency"),
                CommandItem(example: "btc price", description: "Show BTC market price"),
                CommandItem(example: "bitcoin price", description: "Current Bitcoin exchange rate"),
                CommandItem(example: "how much is bitcoin", description: "Conversational price check"),
                CommandItem(example: "what is bitcoin worth", description: "Check current BTC value"),
                CommandItem(example: "price in EUR", description: "BTC price in euros"),
                CommandItem(example: "price in GBP", description: "BTC price in British pounds"),
                CommandItem(example: "price in JPY", description: "BTC price in Japanese yen"),
                CommandItem(example: "price in CAD", description: "BTC price in Canadian dollars"),
                CommandItem(example: "price in AUD", description: "BTC price in Australian dollars"),
                CommandItem(example: "price in CHF", description: "BTC price in Swiss francs"),
                CommandItem(example: "price in SAR", description: "BTC price in Saudi riyals"),
                CommandItem(example: "price in AED", description: "BTC price in UAE dirhams"),
                CommandItem(example: "btc to usd", description: "Bitcoin to US dollar rate"),
                CommandItem(example: "bitcoin to eur", description: "Bitcoin to euro rate"),
                CommandItem(example: "is bitcoin up", description: "Price direction check"),
                CommandItem(example: "is bitcoin going up", description: "Price trend question"),
                CommandItem(example: "market price", description: "Current market exchange rate"),
                CommandItem(example: "current price", description: "Live price check"),
                CommandItem(example: "price check", description: "Quick price lookup"),
            ]
        ),

        // ──────────────────────────────────────────────
        // 6. CURRENCY CONVERSION
        // ──────────────────────────────────────────────
        CommandCategory(
            name: "Convert & Calculate",
            icon: "arrow.left.arrow.right",
            color: AppColors.info,
            commands: [
                CommandItem(example: "convert 0.1 BTC to USD", description: "Convert BTC to a fiat currency"),
                CommandItem(example: "how much is 0.5 BTC", description: "BTC to fiat conversion"),
                CommandItem(example: "how much is 100000 sats", description: "Sats to fiat conversion"),
                CommandItem(example: "how many sats is 0.001 BTC", description: "BTC to satoshis conversion"),
                CommandItem(example: "$50", description: "Convert USD to BTC at current rate"),
                CommandItem(example: "100 EUR", description: "Convert euros to BTC equivalent"),
                CommandItem(example: "500 GBP in BTC", description: "Pounds to BTC conversion"),
                CommandItem(example: "1000 SAR to BTC", description: "Saudi riyals to BTC conversion"),
                CommandItem(example: "and in EUR?", description: "Follow-up: convert to euros"),
                CommandItem(example: "what about GBP?", description: "Follow-up: convert to pounds"),
                CommandItem(example: "in sats?", description: "Follow-up: show in satoshis"),
                CommandItem(example: "and dollars?", description: "Follow-up: show in USD"),
            ]
        ),

        // ──────────────────────────────────────────────
        // 7. TRANSACTION HISTORY
        // ──────────────────────────────────────────────
        CommandCategory(
            name: "Transaction History",
            icon: "clock.fill",
            color: AppColors.info,
            commands: [
                CommandItem(example: "history", description: "Show recent transaction history"),
                CommandItem(example: "transactions", description: "List all recent transactions"),
                CommandItem(example: "last 5 transactions", description: "View a specific number of transactions"),
                CommandItem(example: "last 3 transfers", description: "Recent transfers with count"),
                CommandItem(example: "recent transactions", description: "View most recent activity"),
                CommandItem(example: "show transactions", description: "Display transaction list"),
                CommandItem(example: "activity", description: "View recent wallet activity"),
                CommandItem(example: "recent activity", description: "Show latest activity"),
                CommandItem(example: "show sent", description: "Filter to sent transactions only"),
                CommandItem(example: "show received", description: "Filter to received transactions only"),
                CommandItem(example: "pending", description: "Show unconfirmed transactions"),
                CommandItem(example: "what did I send recently", description: "Past-tense query -- shows history, not send"),
                CommandItem(example: "what did I receive", description: "Past-tense receive query"),
                CommandItem(example: "my transfers", description: "View all transfer history"),
                CommandItem(example: "export history", description: "Export transactions as CSV"),
                CommandItem(example: "export csv", description: "Download transaction history file"),
                CommandItem(example: "(paste a txid)", description: "Paste a 64-char hex txid for details"),
            ]
        ),

        // ──────────────────────────────────────────────
        // 8. NETWORK FEES
        // ──────────────────────────────────────────────
        CommandCategory(
            name: "Network Fees",
            icon: "gauge.medium",
            color: AppColors.accent,
            commands: [
                CommandItem(example: "fees", description: "Show current network fee estimates"),
                CommandItem(example: "fee estimate", description: "Get slow / medium / fast fee rates"),
                CommandItem(example: "fee rate", description: "Check current sat/vB rates"),
                CommandItem(example: "how much to send", description: "Estimate transaction cost"),
                CommandItem(example: "how much are fees", description: "Natural language fee inquiry"),
                CommandItem(example: "what are the fees", description: "Check current fee conditions"),
                CommandItem(example: "network fee", description: "View current network fees"),
                CommandItem(example: "check fees", description: "Quick fee check"),
                CommandItem(example: "show fees", description: "Display fee rate information"),
                CommandItem(example: "mempool", description: "Check mempool congestion and fees"),
                CommandItem(example: "sat per byte", description: "Technical fee rate check"),
                CommandItem(example: "transaction fee", description: "Cost to send a transaction"),
                CommandItem(example: "bump fee", description: "Speed up a stuck transaction (RBF)"),
                CommandItem(example: "speed up", description: "Accelerate a pending transaction"),
                CommandItem(example: "accelerate", description: "Speed up a stuck transaction"),
                CommandItem(example: "what's the recommended fee?", description: "AI suggests the best fee for current conditions"),
                CommandItem(example: "how much will it cost to send?", description: "Estimate total cost including fees"),
            ]
        ),

        // ──────────────────────────────────────────────
        // 9. FEE SELECTION
        // ──────────────────────────────────────────────
        CommandCategory(
            name: "Fee Selection",
            icon: "speedometer",
            color: AppColors.accentDark,
            commands: [
                CommandItem(example: "use fast fee", description: "Select priority fee for fastest confirmation"),
                CommandItem(example: "use slow fee", description: "Select economy fee to save on costs"),
                CommandItem(example: "use normal fee", description: "Select standard/medium fee level"),
                CommandItem(example: "fastest possible", description: "Use the highest priority fee rate"),
                CommandItem(example: "cheapest option", description: "Use the lowest available fee rate"),
                CommandItem(example: "5 sat/vb", description: "Set a custom fee rate in sat/vB"),
                CommandItem(example: "10 sats per byte", description: "Specify custom fee rate"),
                CommandItem(example: "custom fee", description: "Enter a manual fee rate"),
                CommandItem(example: "low fee", description: "Select the economy fee tier"),
                CommandItem(example: "high fee", description: "Select the priority fee tier"),
                CommandItem(example: "medium fee", description: "Select the standard fee tier"),
                CommandItem(example: "priority fee", description: "Use the fastest fee option"),
                CommandItem(example: "economy fee", description: "Use the cheapest fee option"),
            ]
        ),

        // ──────────────────────────────────────────────
        // 10. CONFIRM & CANCEL
        // ──────────────────────────────────────────────
        CommandCategory(
            name: "Confirm & Cancel",
            icon: "checkmark.circle.fill",
            color: AppColors.success,
            commands: [
                CommandItem(example: "yes", description: "Confirm a pending action"),
                CommandItem(example: "confirm", description: "Explicitly confirm a transaction"),
                CommandItem(example: "ok", description: "Agree to proceed"),
                CommandItem(example: "go ahead", description: "Give the green light"),
                CommandItem(example: "do it", description: "Confirm with emphasis"),
                CommandItem(example: "send it", description: "Confirm a send transaction"),
                CommandItem(example: "sure", description: "Casual confirmation"),
                CommandItem(example: "let's go", description: "Enthusiastic confirmation"),
                CommandItem(example: "looks good", description: "Approve after reviewing details"),
                CommandItem(example: "approved", description: "Formal confirmation"),
                CommandItem(example: "proceed", description: "Continue with the operation"),
                CommandItem(example: "no", description: "Decline or cancel"),
                CommandItem(example: "cancel", description: "Cancel the current operation"),
                CommandItem(example: "stop", description: "Stop the current flow"),
                CommandItem(example: "nevermind", description: "Dismiss the current action"),
                CommandItem(example: "go back", description: "Return to the previous step"),
                CommandItem(example: "forget it", description: "Abandon the current operation"),
                CommandItem(example: "changed my mind", description: "Cancel with context"),
                CommandItem(example: "wait", description: "Pause -- keeps flow active, doesn't cancel"),
                CommandItem(example: "hold on", description: "Soft pause without cancelling"),
                CommandItem(example: "abort", description: "Immediately cancel the current operation"),
                CommandItem(example: "not now", description: "Defer the current action"),
            ]
        ),

        // ──────────────────────────────────────────────
        // 11. ADJUST & MODIFY (IN-FLIGHT)
        // ──────────────────────────────────────────────
        CommandCategory(
            name: "Adjust & Modify",
            icon: "slider.horizontal.3",
            color: AppColors.accent,
            commands: [
                CommandItem(example: "faster", description: "Increase fee for faster confirmation"),
                CommandItem(example: "slower", description: "Decrease fee to save on costs"),
                CommandItem(example: "cheaper", description: "Choose a lower fee option"),
                CommandItem(example: "more", description: "Increase amount or show more results"),
                CommandItem(example: "less", description: "Decrease amount"),
                CommandItem(example: "double it", description: "Double the current amount"),
                CommandItem(example: "double the amount", description: "Multiply the send amount by 2"),
                CommandItem(example: "send half instead", description: "Change to half the amount"),
                CommandItem(example: "change amount", description: "Modify the send amount mid-flow"),
                CommandItem(example: "change the amount", description: "Re-enter the send amount"),
                CommandItem(example: "change the address", description: "Re-enter the destination address"),
                CommandItem(example: "change the fee", description: "Re-select the fee level"),
                CommandItem(example: "change to 0.05", description: "Set a specific new amount"),
                CommandItem(example: "use slow fee", description: "Switch to economy fee level"),
                CommandItem(example: "use fast fee", description: "Switch to priority fee level"),
                CommandItem(example: "make it faster", description: "Increase fee for quicker confirmation"),
                CommandItem(example: "make it cheaper", description: "Decrease fee to lower cost"),
                CommandItem(example: "that's too much", description: "AI suggests a lower amount or fee"),
                CommandItem(example: "that's too little", description: "AI suggests increasing the amount"),
                CommandItem(example: "not enough", description: "AI suggests increasing the amount"),
                CommandItem(example: "good enough", description: "Accept the current values"),
            ]
        ),

        // ──────────────────────────────────────────────
        // 12. SMART QUESTIONS
        // ──────────────────────────────────────────────
        CommandCategory(
            name: "Smart Questions",
            icon: "brain.head.profile.fill",
            color: AppColors.info,
            commands: [
                CommandItem(example: "is this safe?", description: "AI explains the safety of your action"),
                CommandItem(example: "is it safe to send?", description: "Safety check before sending"),
                CommandItem(example: "can I afford this?", description: "AI checks balance vs. amount"),
                CommandItem(example: "can I afford 0.5 BTC?", description: "Affordability check with amount"),
                CommandItem(example: "is that a lot?", description: "Context-aware value evaluation"),
                CommandItem(example: "is that good?", description: "AI evaluates in context"),
                CommandItem(example: "is that enough?", description: "Sufficiency check"),
                CommandItem(example: "what?", description: "AI rephrases its last response simpler"),
                CommandItem(example: "why?", description: "AI explains its reasoning"),
                CommandItem(example: "explain", description: "Get a deeper explanation"),
                CommandItem(example: "what does that mean", description: "AI clarifies its last message"),
                CommandItem(example: "try again", description: "Retry the last action"),
                CommandItem(example: "do it again", description: "Redo the previous operation"),
                CommandItem(example: "same", description: "Repeat the last action with same parameters"),
                CommandItem(example: "can you repeat that?", description: "AI repeats its last response"),
                CommandItem(example: "in simpler terms?", description: "AI simplifies its explanation"),
                CommandItem(example: "tell me more", description: "AI expands on the current topic"),
                CommandItem(example: "what else?", description: "AI provides additional information"),
            ]
        ),

        // ──────────────────────────────────────────────
        // 13. ERROR RECOVERY
        // ──────────────────────────────────────────────
        CommandCategory(
            name: "Error Recovery",
            icon: "arrow.counterclockwise.circle.fill",
            color: AppColors.error,
            commands: [
                CommandItem(example: "try again", description: "Retry the last failed action"),
                CommandItem(example: "start over", description: "Reset conversation and start fresh"),
                CommandItem(example: "go back", description: "Undo the last step in a flow"),
                CommandItem(example: "I made a mistake", description: "AI helps you correct an error"),
                CommandItem(example: "wrong address", description: "Alerts AI that the address was wrong"),
                CommandItem(example: "wrong amount", description: "Alerts AI that the amount was wrong"),
                CommandItem(example: "that's not right", description: "AI asks what needs to be corrected"),
                CommandItem(example: "oops", description: "AI offers to help fix the mistake"),
                CommandItem(example: "undo", description: "Undo the last action"),
                CommandItem(example: "reset", description: "Reset the current flow"),
            ]
        ),

        // ──────────────────────────────────────────────
        // 14. QUICK ONE-WORD COMMANDS
        // ──────────────────────────────────────────────
        CommandCategory(
            name: "Quick Commands",
            icon: "bolt.fill",
            color: AppColors.warning,
            commands: [
                CommandItem(example: "balance", description: "Check your balance"),
                CommandItem(example: "price", description: "Show current BTC price"),
                CommandItem(example: "send", description: "Start the send flow"),
                CommandItem(example: "receive", description: "Get a receiving address"),
                CommandItem(example: "history", description: "Show transaction history"),
                CommandItem(example: "fees", description: "Show fee estimates"),
                CommandItem(example: "help", description: "Show available commands"),
                CommandItem(example: "utxos", description: "Show unspent outputs"),
                CommandItem(example: "cancel", description: "Cancel the current action"),
                CommandItem(example: "confirm", description: "Confirm the current action"),
                CommandItem(example: "refresh", description: "Sync wallet data"),
                CommandItem(example: "pending", description: "Show unconfirmed transactions"),
            ]
        ),

        // ──────────────────────────────────────────────
        // 15. BITCOIN KNOWLEDGE
        // ──────────────────────────────────────────────
        CommandCategory(
            name: "Bitcoin Knowledge",
            icon: "book.fill",
            color: AppColors.info,
            commands: [
                CommandItem(example: "what is bitcoin?", description: "Explains what Bitcoin is and how it works"),
                CommandItem(example: "what is the blockchain?", description: "Explains the blockchain ledger"),
                CommandItem(example: "what is mining?", description: "Explains Bitcoin mining and proof of work"),
                CommandItem(example: "what is the halving?", description: "Explains the Bitcoin halving event"),
                CommandItem(example: "what is a UTXO?", description: "Explains unspent transaction outputs"),
                CommandItem(example: "what is segwit?", description: "Explains Segregated Witness upgrade"),
                CommandItem(example: "what is taproot?", description: "Explains the Taproot upgrade"),
                CommandItem(example: "what is the lightning network?", description: "Explains the Lightning Network layer 2"),
                CommandItem(example: "what is a seed phrase?", description: "Explains mnemonic seed phrases"),
                CommandItem(example: "what is a private key?", description: "Explains private keys and signing"),
                CommandItem(example: "what is a public key?", description: "Explains public keys and addresses"),
                CommandItem(example: "what is a node?", description: "Explains Bitcoin full nodes"),
                CommandItem(example: "what is difficulty?", description: "Explains mining difficulty adjustment"),
                CommandItem(example: "what is the mempool?", description: "Explains the transaction mempool"),
                CommandItem(example: "what is RBF?", description: "Explains Replace-By-Fee"),
                CommandItem(example: "what is DCA?", description: "Explains Dollar Cost Averaging"),
                CommandItem(example: "what is a whale?", description: "Explains large holders (whales)"),
                CommandItem(example: "what is dust?", description: "Explains dust limits and uneconomical UTXOs"),
                CommandItem(example: "who created bitcoin?", description: "The story of Satoshi Nakamoto"),
                CommandItem(example: "is bitcoin safe?", description: "Explains Bitcoin's security model"),
                CommandItem(example: "what are transaction fees?", description: "Explains how Bitcoin fees work"),
                CommandItem(example: "how do confirmations work?", description: "Explains block confirmations"),
                CommandItem(example: "what address types exist?", description: "Explains Legacy, SegWit, Native SegWit, Taproot"),
                CommandItem(example: "what is an HD wallet?", description: "Explains hierarchical deterministic wallets"),
                CommandItem(example: "what is BIP39?", description: "Explains the mnemonic word list standard"),
                CommandItem(example: "what is a block?", description: "Explains Bitcoin blocks"),
                CommandItem(example: "what is a hash?", description: "Explains cryptographic hashing"),
                CommandItem(example: "what is proof of work?", description: "Explains the consensus mechanism"),
                CommandItem(example: "what is a satoshi?", description: "Explains the smallest BTC unit"),
                CommandItem(example: "what is cold storage?", description: "Explains offline key storage"),
                CommandItem(example: "what is a hot wallet?", description: "Explains online/connected wallets"),
                CommandItem(example: "what is multisig?", description: "Explains multi-signature transactions"),
                CommandItem(example: "what is a soft fork?", description: "Explains backward-compatible upgrades"),
                CommandItem(example: "what is a hard fork?", description: "Explains non-backward-compatible splits"),
                CommandItem(example: "what is the genesis block?", description: "Explains Bitcoin's first block"),
                CommandItem(example: "what is 21 million?", description: "Explains Bitcoin's supply cap"),
            ]
        ),

        // ──────────────────────────────────────────────
        // 16. WALLET MANAGEMENT
        // ──────────────────────────────────────────────
        CommandCategory(
            name: "Wallet Management",
            icon: "wallet.pass.fill",
            color: AppColors.accent,
            commands: [
                CommandItem(example: "wallet health", description: "Run a diagnostic health check"),
                CommandItem(example: "wallet status", description: "View wallet overview and status"),
                CommandItem(example: "wallet info", description: "Wallet summary with key metrics"),
                CommandItem(example: "wallet summary", description: "Overview of balance, UTXOs, activity"),
                CommandItem(example: "health check", description: "Run a full wallet diagnostic"),
                CommandItem(example: "refresh", description: "Sync wallet with the blockchain"),
                CommandItem(example: "sync", description: "Synchronize wallet data"),
                CommandItem(example: "reload", description: "Reload wallet information"),
                CommandItem(example: "update", description: "Update balance and transactions"),
                CommandItem(example: "resync wallet", description: "Full wallet resynchronization"),
            ]
        ),

        // ──────────────────────────────────────────────
        // 17. UTXOs & COINS
        // ──────────────────────────────────────────────
        CommandCategory(
            name: "UTXOs & Coins",
            icon: "circle.grid.3x3.fill",
            color: AppColors.warning,
            commands: [
                CommandItem(example: "utxo", description: "List your unspent transaction outputs"),
                CommandItem(example: "utxos", description: "Show all UTXOs in your wallet"),
                CommandItem(example: "unspent outputs", description: "View unspent coins"),
                CommandItem(example: "coin control", description: "View individual spendable coins"),
                CommandItem(example: "my utxos", description: "Show your UTXO set"),
                CommandItem(example: "show coins", description: "Display individual coins"),
                CommandItem(example: "how many utxos", description: "Count your unspent outputs"),
                CommandItem(example: "list coins", description: "Enumerate all spendable coins"),
            ]
        ),

        // ──────────────────────────────────────────────
        // 18. NETWORK STATUS
        // ──────────────────────────────────────────────
        CommandCategory(
            name: "Network",
            icon: "network",
            color: AppColors.info,
            commands: [
                CommandItem(example: "network status", description: "Check your blockchain connection"),
                CommandItem(example: "connection status", description: "View connection health"),
                CommandItem(example: "server status", description: "Check Blockbook server status"),
                CommandItem(example: "node status", description: "View node connectivity"),
                CommandItem(example: "blockchain status", description: "Check blockchain sync status"),
                CommandItem(example: "am I connected?", description: "Verify network connectivity"),
                CommandItem(example: "is the network up?", description: "Check if blockchain API is reachable"),
                CommandItem(example: "block height", description: "Show current Bitcoin block height"),
            ]
        ),

        // ──────────────────────────────────────────────
        // 19. PRIVACY
        // ──────────────────────────────────────────────
        CommandCategory(
            name: "Privacy",
            icon: "eye.slash.fill",
            color: AppColors.textSecondary,
            commands: [
                CommandItem(example: "hide balance", description: "Mask amounts with dots for privacy"),
                CommandItem(example: "hide", description: "Quick privacy mode toggle"),
                CommandItem(example: "private mode", description: "Enable privacy display mode"),
                CommandItem(example: "go private", description: "Switch to private mode"),
                CommandItem(example: "show balance", description: "Reveal hidden balance amounts"),
                CommandItem(example: "unhide", description: "Turn off privacy mode"),
                CommandItem(example: "reveal balance", description: "Show your balance again"),
            ]
        ),

        // ──────────────────────────────────────────────
        // 20. GREETINGS & SOCIAL
        // ──────────────────────────────────────────────
        CommandCategory(
            name: "Greetings & Chat",
            icon: "hand.wave.fill",
            color: AppColors.warning,
            commands: [
                CommandItem(example: "hello", description: "Start a conversation"),
                CommandItem(example: "hi", description: "Quick greeting"),
                CommandItem(example: "hey", description: "Casual greeting"),
                CommandItem(example: "yo", description: "Informal greeting"),
                CommandItem(example: "good morning", description: "Time-based greeting"),
                CommandItem(example: "good afternoon", description: "Afternoon greeting"),
                CommandItem(example: "good evening", description: "Evening greeting"),
                CommandItem(example: "good night", description: "Night-time greeting"),
                CommandItem(example: "howdy", description: "Friendly greeting"),
                CommandItem(example: "what's up", description: "Casual greeting"),
                CommandItem(example: "how's it going", description: "Conversational greeting"),
                CommandItem(example: "what's good", description: "Social greeting"),
                CommandItem(example: "g'day", description: "Australian-style greeting"),
                CommandItem(example: "greetings", description: "Formal greeting"),
                CommandItem(example: "sup", description: "Shortened casual greeting"),
            ]
        ),

        // ──────────────────────────────────────────────
        // 21. EMOTIONS & REACTIONS
        // ──────────────────────────────────────────────
        CommandCategory(
            name: "Emotions & Reactions",
            icon: "face.smiling.fill",
            color: AppColors.success,
            commands: [
                CommandItem(example: "thanks!", description: "AI acknowledges your gratitude"),
                CommandItem(example: "thank you", description: "Express appreciation -- AI responds warmly"),
                CommandItem(example: "awesome", description: "AI shares your excitement"),
                CommandItem(example: "cool", description: "Positive acknowledgment"),
                CommandItem(example: "nice!", description: "AI celebrates with you"),
                CommandItem(example: "love it", description: "Strong positive reaction"),
                CommandItem(example: "wow", description: "AI responds to amazement"),
                CommandItem(example: "great", description: "Positive feedback"),
                CommandItem(example: "perfect", description: "Strong approval"),
                CommandItem(example: "ugh", description: "AI empathizes with frustration"),
                CommandItem(example: "damn", description: "AI acknowledges frustration"),
                CommandItem(example: "oops", description: "AI offers help after a mistake"),
                CommandItem(example: "hmm", description: "AI asks what you're thinking about"),
                CommandItem(example: "lol", description: "AI responds to humor"),
                CommandItem(example: "haha", description: "AI joins in the fun"),
                CommandItem(example: "sorry", description: "AI reassures you"),
                CommandItem(example: "not bad", description: "Cautiously positive reaction"),
                CommandItem(example: "to the moon!", description: "Bitcoin enthusiasm!"),
                CommandItem(example: "goodbye", description: "AI says farewell warmly"),
                CommandItem(example: "bye", description: "Quick farewell"),
            ]
        ),

        // ──────────────────────────────────────────────
        // 22. NAVIGATION
        // ──────────────────────────────────────────────
        CommandCategory(
            name: "Navigation",
            icon: "arrow.uturn.backward.circle.fill",
            color: AppColors.textSecondary,
            commands: [
                CommandItem(example: "back", description: "Go back to the previous step"),
                CommandItem(example: "undo", description: "Undo the last action"),
                CommandItem(example: "start over", description: "Reset and start from scratch"),
                CommandItem(example: "the first one", description: "Select the first item from a list"),
                CommandItem(example: "the second one", description: "Select the second item"),
                CommandItem(example: "the third one", description: "Select the third item"),
                CommandItem(example: "the last one", description: "Select the last item from a list"),
                CommandItem(example: "next", description: "Move to the next item or step"),
                CommandItem(example: "previous", description: "Move to the previous item or step"),
                CommandItem(example: "show more", description: "Display more results"),
                CommandItem(example: "show all", description: "Display all available results"),
            ]
        ),

        // ──────────────────────────────────────────────
        // 23. SETTINGS & HELP
        // ──────────────────────────────────────────────
        CommandCategory(
            name: "Settings & Help",
            icon: "gearshape.fill",
            color: AppColors.textSecondary,
            commands: [
                CommandItem(example: "help", description: "Show a quick overview of what AI can do"),
                CommandItem(example: "what can you do", description: "See all available capabilities"),
                CommandItem(example: "commands", description: "List available commands"),
                CommandItem(example: "how to", description: "Get usage instructions"),
                CommandItem(example: "how do I send bitcoin?", description: "Step-by-step send instructions"),
                CommandItem(example: "how do I receive?", description: "Instructions for receiving BTC"),
                CommandItem(example: "settings", description: "Open the settings panel"),
                CommandItem(example: "preferences", description: "View app preferences"),
                CommandItem(example: "about", description: "App version and information"),
                CommandItem(example: "version", description: "Check current app version"),
            ]
        ),

        // ──────────────────────────────────────────────
        // 24. FOLLOW-UP QUERIES
        // ──────────────────────────────────────────────
        CommandCategory(
            name: "Follow-Up Queries",
            icon: "bubble.left.and.bubble.right.fill",
            color: AppColors.info,
            commands: [
                CommandItem(example: "and EUR?", description: "After price/balance -- show in euros"),
                CommandItem(example: "and in EUR?", description: "After any amount -- convert to euros"),
                CommandItem(example: "in GBP?", description: "After price/balance -- show in pounds"),
                CommandItem(example: "what about in pounds?", description: "Follow-up: convert to British pounds"),
                CommandItem(example: "what about yen?", description: "After price -- show in JPY"),
                CommandItem(example: "and in dollars?", description: "After balance -- show USD value"),
                CommandItem(example: "in sats?", description: "After balance -- show in satoshis"),
                CommandItem(example: "is that a lot?", description: "After balance -- contextual evaluation"),
                CommandItem(example: "is that good?", description: "After any response -- AI evaluates"),
                CommandItem(example: "can I send some?", description: "After balance -- check sendability"),
                CommandItem(example: "how much is that in dollars", description: "Convert last shown value to USD"),
                CommandItem(example: "can you repeat that?", description: "AI repeats its last response"),
                CommandItem(example: "in simpler terms?", description: "AI simplifies the explanation"),
                CommandItem(example: "why?", description: "AI explains the reasoning behind its response"),
                CommandItem(example: "tell me more", description: "AI expands on the current topic"),
                CommandItem(example: "what else?", description: "AI provides additional related info"),
            ]
        ),

        // ──────────────────────────────────────────────
        // 25. ARABIC عربي
        // ──────────────────────────────────────────────
        CommandCategory(
            name: "Arabic",
            icon: "globe",
            color: AppColors.accent,
            commands: [
                CommandItem(example: "رصيدي", description: "Check balance"),
                CommandItem(example: "كم عندي", description: "How much do I have"),
                CommandItem(example: "كم رصيدي؟", description: "What's my balance?"),
                CommandItem(example: "ارسل", description: "Start a send"),
                CommandItem(example: "أرسل بيتكوين", description: "Send bitcoin"),
                CommandItem(example: "أرسل 0.01 بتكوين", description: "Send specific amount"),
                CommandItem(example: "حول", description: "Convert currency"),
                CommandItem(example: "استقبال", description: "Show receive address"),
                CommandItem(example: "عنواني", description: "My address"),
                CommandItem(example: "عنوان جديد", description: "New address"),
                CommandItem(example: "سعر البتكوين", description: "Current BTC price"),
                CommandItem(example: "سعر", description: "Price check"),
                CommandItem(example: "ما السعر؟", description: "What's the price?"),
                CommandItem(example: "رسوم", description: "Network fees"),
                CommandItem(example: "سجل المعاملات", description: "Transaction history"),
                CommandItem(example: "مساعدة", description: "Help"),
                CommandItem(example: "ساعدني", description: "Help me"),
                CommandItem(example: "نعم", description: "Confirm"),
                CommandItem(example: "تأكيد", description: "Confirm (formal)"),
                CommandItem(example: "لا", description: "Cancel"),
                CommandItem(example: "إلغاء", description: "Cancel operation"),
                CommandItem(example: "تحديث", description: "Refresh wallet"),
                CommandItem(example: "مرحبا", description: "Greeting"),
                CommandItem(example: "شكرا", description: "Thank you"),
                CommandItem(example: "شكراً", description: "Thanks (formal)"),
                CommandItem(example: "إعدادات", description: "Settings"),
                CommandItem(example: "اخفاء الرصيد", description: "Hide balance"),
                CommandItem(example: "ما هو البيتكوين؟", description: "What is Bitcoin?"),
            ]
        ),

        // ──────────────────────────────────────────────
        // 26. SPANISH ESPAÑOL
        // ──────────────────────────────────────────────
        CommandCategory(
            name: "Spanish",
            icon: "globe.americas.fill",
            color: AppColors.accent,
            commands: [
                CommandItem(example: "saldo", description: "Check balance"),
                CommandItem(example: "cuánto tengo", description: "How much do I have"),
                CommandItem(example: "mi saldo", description: "My balance"),
                CommandItem(example: "enviar", description: "Start a send"),
                CommandItem(example: "enviar bitcoin", description: "Send bitcoin"),
                CommandItem(example: "enviar 0.01 BTC", description: "Send specific amount"),
                CommandItem(example: "recibir", description: "Show receive address"),
                CommandItem(example: "mi dirección", description: "My address"),
                CommandItem(example: "dirección nueva", description: "New address"),
                CommandItem(example: "precio", description: "Current price"),
                CommandItem(example: "precio del bitcoin", description: "Bitcoin price check"),
                CommandItem(example: "cuál es el precio?", description: "What's the price?"),
                CommandItem(example: "historial", description: "Transaction history"),
                CommandItem(example: "transacciones", description: "View transactions"),
                CommandItem(example: "comisión", description: "Network fees"),
                CommandItem(example: "ayuda", description: "Help"),
                CommandItem(example: "confirmar", description: "Confirm"),
                CommandItem(example: "cancelar", description: "Cancel"),
                CommandItem(example: "actualizar", description: "Refresh wallet"),
                CommandItem(example: "hola", description: "Greeting"),
                CommandItem(example: "gracias", description: "Thanks"),
                CommandItem(example: "ajustes", description: "Settings"),
                CommandItem(example: "ocultar saldo", description: "Hide balance"),
                CommandItem(example: "nueva dirección", description: "New address"),
            ]
        ),

        // ──────────────────────────────────────────────
        // 27. FRENCH FRANCAIS
        // ──────────────────────────────────────────────
        CommandCategory(
            name: "French",
            icon: "globe.europe.africa.fill",
            color: AppColors.info,
            commands: [
                CommandItem(example: "solde", description: "Check balance"),
                CommandItem(example: "combien j'ai", description: "How much do I have"),
                CommandItem(example: "envoyer", description: "Start a send"),
                CommandItem(example: "envoyer du bitcoin", description: "Send bitcoin"),
                CommandItem(example: "recevoir", description: "Show receive address"),
                CommandItem(example: "mon adresse", description: "My address"),
                CommandItem(example: "prix", description: "Current price"),
                CommandItem(example: "prix du bitcoin", description: "Bitcoin price"),
                CommandItem(example: "historique", description: "Transaction history"),
                CommandItem(example: "aide", description: "Help"),
                CommandItem(example: "oui", description: "Confirm"),
                CommandItem(example: "non", description: "Cancel"),
                CommandItem(example: "annuler", description: "Cancel operation"),
                CommandItem(example: "bonjour", description: "Greeting"),
                CommandItem(example: "merci", description: "Thank you"),
            ]
        ),

        // ──────────────────────────────────────────────
        // 28. SMART DETECTION
        // ──────────────────────────────────────────────
        CommandCategory(
            name: "Smart Detection",
            icon: "sparkles",
            color: AppColors.warning,
            commands: [
                CommandItem(example: "(paste a Bitcoin address)", description: "Auto-detects bc1q.../bc1p.../1.../3... addresses"),
                CommandItem(example: "(paste a transaction ID)", description: "Auto-detects 64-character hex txids"),
                CommandItem(example: "(type a number)", description: "Auto-detects amounts in active send flow"),
                CommandItem(example: "(type a fiat amount)", description: "Auto-detects $50 / 100 EUR / 500 GBP"),
                CommandItem(example: "hlep", description: "Typo tolerance -- auto-corrects to \"help\""),
                CommandItem(example: "recieve", description: "Typo tolerance -- auto-corrects to \"receive\""),
                CommandItem(example: "ballance", description: "Typo tolerance -- auto-corrects to \"balance\""),
                CommandItem(example: "sendd", description: "Typo tolerance -- auto-corrects to \"send\""),
                CommandItem(example: "trasactions", description: "Typo tolerance -- auto-corrects to \"transactions\""),
                CommandItem(example: "one bitcoin", description: "Word numbers -- \"one\" through \"thousand\""),
                CommandItem(example: "half a bitcoin", description: "Fraction words -- \"half\", \"quarter\""),
                CommandItem(example: "...", description: "AI prompts you for what you'd like to do"),
                CommandItem(example: "?", description: "Re-prompts current state or asks how to help"),
            ]
        ),

        // ──────────────────────────────────────────────
        // 29. AMOUNT VARIATIONS
        // ──────────────────────────────────────────────
        CommandCategory(
            name: "Amount Variations",
            icon: "number.circle.fill",
            color: AppColors.accentDark,
            commands: [
                CommandItem(example: "send all", description: "Sends your entire balance"),
                CommandItem(example: "send max", description: "Sends maximum amount minus fees"),
                CommandItem(example: "send half", description: "Sends 50% of your balance"),
                CommandItem(example: "send everything", description: "Sweeps all funds"),
                CommandItem(example: "send 50000 sats to bc1q...", description: "Send in satoshis"),
                CommandItem(example: "send $100 worth of bitcoin", description: "Send a fiat-denominated BTC amount"),
                CommandItem(example: "send $50 to bc1q...", description: "Send USD equivalent in BTC"),
                CommandItem(example: "send 0.001 BTC", description: "Send a specific BTC amount"),
                CommandItem(example: "send 0.5 bitcoin", description: "Send using the word \"bitcoin\""),
                CommandItem(example: "send one million sats", description: "Send using word numbers"),
                CommandItem(example: "send a quarter", description: "Send 25% of your balance"),
                CommandItem(example: "100 EUR worth", description: "Fiat-denominated amount in euros"),
            ]
        ),

        // ──────────────────────────────────────────────
        // 30. SECURITY AWARENESS
        // ──────────────────────────────────────────────
        CommandCategory(
            name: "Security Awareness",
            icon: "lock.shield.fill",
            color: AppColors.success,
            commands: [
                CommandItem(example: "is this address safe?", description: "AI checks address format validity"),
                CommandItem(example: "is this safe to send?", description: "Safety check before broadcasting"),
                CommandItem(example: "verify address", description: "Double-check the destination address"),
                CommandItem(example: "check address", description: "Validate a Bitcoin address format"),
                CommandItem(example: "what if I send to wrong address?", description: "AI explains irreversibility"),
                CommandItem(example: "are my funds safe?", description: "AI explains wallet security model"),
                CommandItem(example: "what is my seed phrase?", description: "AI warns about seed phrase safety"),
                CommandItem(example: "how to backup my wallet?", description: "AI explains backup procedures"),
            ]
        ),
    ]
}
