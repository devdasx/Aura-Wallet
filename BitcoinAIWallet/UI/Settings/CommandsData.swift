import SwiftUI

// MARK: - CommandsData.swift
// Bitcoin AI Wallet
//
// Comprehensive reference of every command, phrase, and natural language
// pattern the AI chat engine understands. Organized by category for
// the CommandsReferenceView.
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
        // 1. CHECK BALANCE
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
            ]
        ),

        // ──────────────────────────────────────────────
        // 2. SEND BITCOIN
        // ──────────────────────────────────────────────
        CommandCategory(
            name: "Send Bitcoin",
            icon: "arrow.up.circle.fill",
            color: AppColors.error,
            commands: [
                CommandItem(example: "send", description: "Start a guided send flow — AI walks you through it"),
                CommandItem(example: "send 0.005 to bc1q...", description: "Send a specific BTC amount to an address"),
                CommandItem(example: "send 50000 sats to bc1q...", description: "Send in satoshis"),
                CommandItem(example: "send all to bc1q...", description: "Sweep your entire balance to an address"),
                CommandItem(example: "send max to bc1q...", description: "Send maximum amount possible"),
                CommandItem(example: "send everything to bc1q...", description: "Send all funds to an address"),
                CommandItem(example: "send half", description: "Send 50% of your balance"),
                CommandItem(example: "transfer 0.01 BTC to bc1q...", description: "Alternative keyword for sending"),
                CommandItem(example: "pay bc1q...", description: "Start a payment to an address"),
                CommandItem(example: "move 0.1 bitcoin to bc1q...", description: "Move bitcoin to another address"),
                CommandItem(example: "withdraw 0.5 BTC", description: "Withdraw from your wallet"),
                CommandItem(example: "send to bc1q...", description: "Provide address first — AI asks for amount"),
                CommandItem(example: "0.005", description: "Just type an amount when AI asks for it"),
                CommandItem(example: "(paste an address)", description: "Paste a Bitcoin address — AI starts send flow"),
            ]
        ),

        // ──────────────────────────────────────────────
        // 3. RECEIVE BITCOIN
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
        // 4. BITCOIN PRICE
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
        // 5. CURRENCY CONVERSION
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
                CommandItem(example: "and in EUR?", description: "Follow-up: convert to euros"),
                CommandItem(example: "what about GBP?", description: "Follow-up: convert to pounds"),
                CommandItem(example: "in sats?", description: "Follow-up: show in satoshis"),
                CommandItem(example: "and dollars?", description: "Follow-up: show in USD"),
            ]
        ),

        // ──────────────────────────────────────────────
        // 6. TRANSACTION HISTORY
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
                CommandItem(example: "what did I send recently", description: "Past-tense query — shows history, not send"),
                CommandItem(example: "what did I receive", description: "Past-tense receive query"),
                CommandItem(example: "my transfers", description: "View all transfer history"),
                CommandItem(example: "export history", description: "Export transactions as CSV"),
                CommandItem(example: "export csv", description: "Download transaction history file"),
                CommandItem(example: "(paste a txid)", description: "Paste a 64-char hex txid for details"),
            ]
        ),

        // ──────────────────────────────────────────────
        // 7. NETWORK FEES
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
            ]
        ),

        // ──────────────────────────────────────────────
        // 8. CONFIRM & CANCEL
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
                CommandItem(example: "no", description: "Decline or cancel"),
                CommandItem(example: "cancel", description: "Cancel the current operation"),
                CommandItem(example: "stop", description: "Stop the current flow"),
                CommandItem(example: "nevermind", description: "Dismiss the current action"),
                CommandItem(example: "go back", description: "Return to the previous step"),
                CommandItem(example: "forget it", description: "Abandon the current operation"),
                CommandItem(example: "changed my mind", description: "Cancel with context"),
                CommandItem(example: "wait", description: "Pause — keeps flow active, doesn't cancel"),
                CommandItem(example: "hold on", description: "Soft pause without cancelling"),
            ]
        ),

        // ──────────────────────────────────────────────
        // 9. ADJUST & MODIFY (IN-FLIGHT)
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
                CommandItem(example: "send half", description: "Change to half the amount"),
                CommandItem(example: "change amount", description: "Modify the send amount mid-flow"),
                CommandItem(example: "change to 0.05", description: "Set a specific new amount"),
                CommandItem(example: "use slow fee", description: "Switch to economy fee level"),
                CommandItem(example: "use fast fee", description: "Switch to priority fee level"),
                CommandItem(example: "that's too much", description: "AI suggests a lower amount or fee"),
                CommandItem(example: "not enough", description: "AI suggests increasing the amount"),
                CommandItem(example: "good enough", description: "Accept the current values"),
            ]
        ),

        // ──────────────────────────────────────────────
        // 10. SMART QUESTIONS
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
                CommandItem(example: "why?", description: "AI explains its last response"),
                CommandItem(example: "explain", description: "Get a deeper explanation"),
                CommandItem(example: "what does that mean", description: "AI clarifies its last message"),
                CommandItem(example: "try again", description: "Repeat the last action"),
                CommandItem(example: "do it again", description: "Redo the previous operation"),
                CommandItem(example: "same", description: "Repeat the last action with same parameters"),
            ]
        ),

        // ──────────────────────────────────────────────
        // 11. WALLET MANAGEMENT
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
        // 12. UTXOs & COINS
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
            ]
        ),

        // ──────────────────────────────────────────────
        // 13. NETWORK STATUS
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
            ]
        ),

        // ──────────────────────────────────────────────
        // 14. PRIVACY
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
        // 15. GREETINGS & SOCIAL
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
                CommandItem(example: "good evening", description: "Evening greeting"),
                CommandItem(example: "howdy", description: "Friendly greeting"),
                CommandItem(example: "what's up", description: "Casual \"how are you\" style greeting"),
                CommandItem(example: "how's it going", description: "Conversational greeting"),
                CommandItem(example: "what's good", description: "Social greeting"),
                CommandItem(example: "g'day", description: "Australian-style greeting"),
                CommandItem(example: "greetings", description: "Formal greeting"),
            ]
        ),

        // ──────────────────────────────────────────────
        // 16. EMOTIONS & REACTIONS
        // ──────────────────────────────────────────────
        CommandCategory(
            name: "Emotions & Reactions",
            icon: "face.smiling.fill",
            color: AppColors.success,
            commands: [
                CommandItem(example: "thanks!", description: "AI acknowledges your gratitude"),
                CommandItem(example: "thank you", description: "Express appreciation — AI responds warmly"),
                CommandItem(example: "awesome", description: "AI shares your excitement"),
                CommandItem(example: "cool", description: "Positive acknowledgment"),
                CommandItem(example: "nice!", description: "AI celebrates with you"),
                CommandItem(example: "love it", description: "Strong positive reaction"),
                CommandItem(example: "wow", description: "AI responds to amazement"),
                CommandItem(example: "ugh", description: "AI empathizes with frustration"),
                CommandItem(example: "damn", description: "AI acknowledges frustration"),
                CommandItem(example: "oops", description: "AI offers help after a mistake"),
                CommandItem(example: "hmm", description: "AI asks what you're thinking about"),
                CommandItem(example: "lol", description: "AI responds to humor"),
                CommandItem(example: "haha", description: "AI joins in the fun"),
                CommandItem(example: "sorry", description: "AI reassures you"),
                CommandItem(example: "not bad", description: "Cautiously positive reaction"),
                CommandItem(example: "to the moon!", description: "Bitcoin enthusiasm!"),
            ]
        ),

        // ──────────────────────────────────────────────
        // 17. NAVIGATION
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
                CommandItem(example: "the last one", description: "Select the last item from a list"),
                CommandItem(example: "next", description: "Move to the next item or step"),
                CommandItem(example: "show more", description: "Display more results"),
            ]
        ),

        // ──────────────────────────────────────────────
        // 18. SETTINGS & HELP
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
                CommandItem(example: "settings", description: "Open the settings panel"),
                CommandItem(example: "preferences", description: "View app preferences"),
                CommandItem(example: "about", description: "App version and information"),
                CommandItem(example: "version", description: "Check current app version"),
            ]
        ),

        // ──────────────────────────────────────────────
        // 19. ARABIC عربي
        // ──────────────────────────────────────────────
        CommandCategory(
            name: "عربي (Arabic)",
            icon: "globe",
            color: AppColors.accent,
            commands: [
                CommandItem(example: "رصيدي", description: "التحقق من رصيد المحفظة — Check balance"),
                CommandItem(example: "كم عندي", description: "كم بتكوين لدي — How much do I have"),
                CommandItem(example: "ارسل", description: "بدء عملية إرسال — Start a send"),
                CommandItem(example: "أرسل 0.01 بتكوين", description: "إرسال مبلغ محدد — Send specific amount"),
                CommandItem(example: "حول", description: "تحويل عملة — Convert currency"),
                CommandItem(example: "استقبال", description: "عرض عنوان الاستقبال — Show receive address"),
                CommandItem(example: "عنواني", description: "عرض عنوان المحفظة — My address"),
                CommandItem(example: "سعر البتكوين", description: "سعر البتكوين الحالي — Current BTC price"),
                CommandItem(example: "سعر", description: "سعر البتكوين — Price check"),
                CommandItem(example: "رسوم", description: "رسوم الشبكة — Network fees"),
                CommandItem(example: "سجل المعاملات", description: "عرض السجل — Transaction history"),
                CommandItem(example: "مساعدة", description: "عرض المساعدة — Help"),
                CommandItem(example: "نعم", description: "تأكيد العملية — Confirm"),
                CommandItem(example: "لا", description: "إلغاء العملية — Cancel"),
                CommandItem(example: "إلغاء", description: "إلغاء العملية الحالية — Cancel operation"),
                CommandItem(example: "تحديث", description: "تحديث المحفظة — Refresh wallet"),
                CommandItem(example: "مرحبا", description: "تحية — Greeting"),
                CommandItem(example: "شكرا", description: "شكر وتقدير — Thank you"),
                CommandItem(example: "إعدادات", description: "فتح الإعدادات — Settings"),
                CommandItem(example: "اخفاء الرصيد", description: "وضع الخصوصية — Hide balance"),
            ]
        ),

        // ──────────────────────────────────────────────
        // 20. SPANISH ESPAÑOL
        // ──────────────────────────────────────────────
        CommandCategory(
            name: "Español (Spanish)",
            icon: "globe.americas.fill",
            color: AppColors.accent,
            commands: [
                CommandItem(example: "saldo", description: "Ver el saldo de la cartera — Check balance"),
                CommandItem(example: "cuánto tengo", description: "Consulta natural del saldo — How much do I have"),
                CommandItem(example: "enviar", description: "Iniciar envío — Start a send"),
                CommandItem(example: "enviar 0.01 BTC", description: "Enviar cantidad específica — Send amount"),
                CommandItem(example: "recibir", description: "Mostrar dirección — Show receive address"),
                CommandItem(example: "mi dirección", description: "Ver dirección de la cartera — My address"),
                CommandItem(example: "precio", description: "Precio actual del bitcoin — Current price"),
                CommandItem(example: "precio del bitcoin", description: "Consulta de precio — Price check"),
                CommandItem(example: "historial", description: "Historial de transacciones — Transaction history"),
                CommandItem(example: "transacciones", description: "Ver transacciones — View transactions"),
                CommandItem(example: "comisión", description: "Tarifas de red — Network fees"),
                CommandItem(example: "ayuda", description: "Mostrar ayuda — Help"),
                CommandItem(example: "confirmar", description: "Confirmar operación — Confirm"),
                CommandItem(example: "cancelar", description: "Cancelar operación — Cancel"),
                CommandItem(example: "actualizar", description: "Sincronizar cartera — Refresh wallet"),
                CommandItem(example: "hola", description: "Saludo — Greeting"),
                CommandItem(example: "ajustes", description: "Abrir ajustes — Settings"),
                CommandItem(example: "ocultar saldo", description: "Modo privado — Hide balance"),
                CommandItem(example: "nueva dirección", description: "Generar dirección — New address"),
            ]
        ),

        // ──────────────────────────────────────────────
        // 21. SMART DETECTION
        // ──────────────────────────────────────────────
        CommandCategory(
            name: "Smart Detection",
            icon: "sparkles",
            color: AppColors.warning,
            commands: [
                CommandItem(example: "(paste a Bitcoin address)", description: "Auto-detects bc1q.../bc1p.../1.../3... addresses"),
                CommandItem(example: "(paste a transaction ID)", description: "Auto-detects 64-character hex txids"),
                CommandItem(example: "(type a number)", description: "Auto-detects amounts in active send flow"),
                CommandItem(example: "hlep", description: "Typo tolerance — auto-corrects to \"help\""),
                CommandItem(example: "recieve", description: "Typo tolerance — auto-corrects to \"receive\""),
                CommandItem(example: "ballance", description: "Typo tolerance — auto-corrects to \"balance\""),
                CommandItem(example: "one bitcoin", description: "Word numbers — \"one\" through \"thousand\""),
                CommandItem(example: "...", description: "AI prompts you for what you'd like to do"),
                CommandItem(example: "?", description: "Re-prompts current state or asks how to help"),
            ]
        ),

        // ──────────────────────────────────────────────
        // 22. FOLLOW-UP QUERIES
        // ──────────────────────────────────────────────
        CommandCategory(
            name: "Follow-Up Queries",
            icon: "bubble.left.and.bubble.right.fill",
            color: AppColors.info,
            commands: [
                CommandItem(example: "and EUR?", description: "After price/balance — show in euros"),
                CommandItem(example: "in GBP?", description: "After price/balance — show in pounds"),
                CommandItem(example: "what about yen?", description: "After price — show in JPY"),
                CommandItem(example: "and in dollars?", description: "After balance — show USD value"),
                CommandItem(example: "in sats?", description: "After balance — show in satoshis"),
                CommandItem(example: "is that a lot?", description: "After balance — contextual evaluation"),
                CommandItem(example: "is that good?", description: "After any response — AI evaluates"),
                CommandItem(example: "can I send some?", description: "After balance — check sendability"),
                CommandItem(example: "how much is that in dollars", description: "Convert last shown value to USD"),
            ]
        ),
    ]
}
