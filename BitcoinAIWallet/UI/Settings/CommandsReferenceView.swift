import SwiftUI

// MARK: - CommandsReferenceView
// Searchable, categorized reference of all chat commands.
// Tapping a command copies it to the clipboard and optionally injects it into chat.
//
// Platform: iOS 17.0+

struct CommandsReferenceView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""

    var body: some View {
        List {
            ForEach(filteredCategories) { category in
                Section {
                    ForEach(category.commands) { command in
                        commandRow(command)
                    }
                } header: {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: category.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(category.color)
                        Text(category.name)
                            .font(AppTypography.labelSmall)
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppColors.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Commands")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search commands...")
    }

    // MARK: - Command Row

    private func commandRow(_ command: CommandItem) -> some View {
        Button {
            HapticManager.lightTap()
            UIPasteboard.general.string = command.example
            // Inject into chat
            NotificationCenter.default.post(
                name: .chatInjectCommand,
                object: nil,
                userInfo: ["command": command.example]
            )
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(command.example)
                    .font(AppTypography.bodyMedium)
                    .fontWeight(.medium)
                    .foregroundColor(AppColors.textPrimary)

                Text(command.description)
                    .font(AppTypography.labelSmall)
                    .foregroundColor(AppColors.textTertiary)
                    .lineLimit(2)
            }
            .padding(.vertical, AppSpacing.xxxs)
        }
        .buttonStyle(.plain)
        .listRowBackground(AppColors.backgroundCard)
    }

    // MARK: - Filtered Data

    private var filteredCategories: [CommandCategory] {
        if searchText.isEmpty {
            return Self.allCategories
        }
        let query = searchText.lowercased()
        return Self.allCategories.compactMap { category in
            let matched = category.commands.filter { cmd in
                cmd.example.lowercased().contains(query)
                || cmd.description.lowercased().contains(query)
                || category.name.lowercased().contains(query)
            }
            guard !matched.isEmpty else { return nil }
            return CommandCategory(
                name: category.name,
                icon: category.icon,
                color: category.color,
                commands: matched
            )
        }
    }

    // MARK: - Data Model

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

    // MARK: - All Categories

    static let allCategories: [CommandCategory] = [
        // 1. Balance
        CommandCategory(
            name: "Balance",
            icon: "bitcoinsign.circle.fill",
            color: AppColors.warning,
            commands: [
                CommandItem(example: "balance", description: "Show your current BTC balance and fiat value"),
                CommandItem(example: "how much do I have", description: "Natural language balance check"),
                CommandItem(example: "my btc", description: "Quick balance inquiry"),
                CommandItem(example: "check wallet", description: "Check wallet balance and status"),
                CommandItem(example: "show balance", description: "Reveal balance if hidden"),
                CommandItem(example: "total balance", description: "View total balance including pending"),
                CommandItem(example: "available balance", description: "View spendable balance"),
                CommandItem(example: "what's my balance", description: "Conversational balance check"),
            ]
        ),

        // 2. Send
        CommandCategory(
            name: "Send",
            icon: "arrow.up.circle.fill",
            color: AppColors.error,
            commands: [
                CommandItem(example: "send", description: "Start a new send flow — AI will guide you"),
                CommandItem(example: "send 0.005 to bc1q...", description: "Send a specific BTC amount to an address"),
                CommandItem(example: "send 50000 sats to bc1q...", description: "Send in satoshis"),
                CommandItem(example: "send $50 to bc1q...", description: "Send a fiat-denominated amount"),
                CommandItem(example: "send all to bc1q...", description: "Sweep your entire balance"),
                CommandItem(example: "transfer 0.01 BTC to bc1q...", description: "Alternative send keyword"),
                CommandItem(example: "pay bc1q...", description: "Start a payment to an address"),
                CommandItem(example: "yes", description: "Confirm a pending transaction"),
                CommandItem(example: "cancel", description: "Cancel the current operation"),
            ]
        ),

        // 3. Receive
        CommandCategory(
            name: "Receive",
            icon: "arrow.down.circle.fill",
            color: AppColors.success,
            commands: [
                CommandItem(example: "receive", description: "Show your receiving address and QR code"),
                CommandItem(example: "my address", description: "Display your current receive address"),
                CommandItem(example: "show address", description: "Show address with QR code"),
                CommandItem(example: "qr code", description: "Display QR code for receiving"),
                CommandItem(example: "deposit", description: "Show deposit address"),
                CommandItem(example: "new address", description: "Generate a fresh receiving address"),
                CommandItem(example: "fresh address", description: "Get a new address for privacy"),
                CommandItem(example: "generate address", description: "Derive the next unused address"),
            ]
        ),

        // 4. History
        CommandCategory(
            name: "History",
            icon: "clock.fill",
            color: AppColors.info,
            commands: [
                CommandItem(example: "history", description: "Show recent transaction history"),
                CommandItem(example: "last 5 transactions", description: "View a specific number of transactions"),
                CommandItem(example: "transactions", description: "List all recent transactions"),
                CommandItem(example: "activity", description: "View recent wallet activity"),
                CommandItem(example: "show transactions", description: "Display transaction list"),
                CommandItem(example: "show sent", description: "Filter to sent transactions only"),
                CommandItem(example: "show received", description: "Filter to received transactions only"),
                CommandItem(example: "pending", description: "Show unconfirmed transactions"),
                CommandItem(example: "export history", description: "Export transactions as CSV"),
                CommandItem(example: "export csv", description: "Download transaction history"),
            ]
        ),

        // 5. Fees
        CommandCategory(
            name: "Fees",
            icon: "gauge.medium",
            color: AppColors.accent,
            commands: [
                CommandItem(example: "fees", description: "Show current network fee estimates"),
                CommandItem(example: "fee estimate", description: "Get slow/medium/fast fee rates"),
                CommandItem(example: "fee rate", description: "Check current sat/vB rates"),
                CommandItem(example: "how much to send", description: "Estimate transaction cost"),
                CommandItem(example: "mempool", description: "Check mempool and fee conditions"),
                CommandItem(example: "network fee", description: "View current network fees"),
                CommandItem(example: "check fees", description: "Quick fee check"),
                CommandItem(example: "bump fee", description: "Speed up a stuck transaction (RBF)"),
                CommandItem(example: "speed up", description: "Accelerate a pending transaction"),
            ]
        ),

        // 6. Price
        CommandCategory(
            name: "Price",
            icon: "chart.line.uptrend.xyaxis",
            color: AppColors.success,
            commands: [
                CommandItem(example: "price", description: "Current Bitcoin price in your default currency"),
                CommandItem(example: "btc price", description: "Show BTC market price"),
                CommandItem(example: "bitcoin price", description: "Current Bitcoin exchange rate"),
                CommandItem(example: "price in EUR", description: "BTC price in a specific currency"),
                CommandItem(example: "price in JPY", description: "BTC price in Japanese yen"),
                CommandItem(example: "how much is bitcoin", description: "Conversational price check"),
            ]
        ),

        // 7. Convert
        CommandCategory(
            name: "Convert",
            icon: "arrow.left.arrow.right",
            color: AppColors.info,
            commands: [
                CommandItem(example: "$50", description: "Convert USD to BTC at current rate"),
                CommandItem(example: "100 EUR", description: "Convert euros to BTC"),
                CommandItem(example: "convert $500 to BTC", description: "Explicit currency conversion"),
                CommandItem(example: "how many sats is 0.001 BTC", description: "BTC to sats conversion"),
            ]
        ),

        // 8. Wallet
        CommandCategory(
            name: "Wallet",
            icon: "wallet.pass.fill",
            color: AppColors.accent,
            commands: [
                CommandItem(example: "wallet health", description: "Run a health check on your wallet"),
                CommandItem(example: "wallet status", description: "View wallet overview and status"),
                CommandItem(example: "wallet info", description: "Wallet summary with key metrics"),
                CommandItem(example: "wallet summary", description: "Overview of balance, UTXOs, activity"),
                CommandItem(example: "health check", description: "Run a full wallet diagnostic"),
            ]
        ),

        // 9. UTXOs
        CommandCategory(
            name: "UTXOs",
            icon: "circle.grid.3x3.fill",
            color: AppColors.warning,
            commands: [
                CommandItem(example: "utxo", description: "List your unspent transaction outputs"),
                CommandItem(example: "utxos", description: "Show all UTXOs in your wallet"),
                CommandItem(example: "unspent outputs", description: "View unspent coins"),
                CommandItem(example: "coin control", description: "View individual spendable coins"),
            ]
        ),

        // 10. Network
        CommandCategory(
            name: "Network",
            icon: "network",
            color: AppColors.info,
            commands: [
                CommandItem(example: "network status", description: "Check your blockchain connection"),
                CommandItem(example: "connection status", description: "View connection health"),
                CommandItem(example: "server status", description: "Check Blockbook server status"),
                CommandItem(example: "node status", description: "View node connectivity"),
            ]
        ),

        // 11. Privacy
        CommandCategory(
            name: "Privacy",
            icon: "eye.slash.fill",
            color: AppColors.textSecondary,
            commands: [
                CommandItem(example: "hide balance", description: "Mask amounts with dots for privacy"),
                CommandItem(example: "hide", description: "Quick privacy mode toggle"),
                CommandItem(example: "private mode", description: "Enable privacy display mode"),
                CommandItem(example: "show balance", description: "Reveal hidden balance"),
                CommandItem(example: "unhide", description: "Turn off privacy mode"),
                CommandItem(example: "reveal balance", description: "Show your balance again"),
            ]
        ),

        // 12. Sync
        CommandCategory(
            name: "Sync",
            icon: "arrow.clockwise",
            color: AppColors.success,
            commands: [
                CommandItem(example: "refresh", description: "Sync wallet with the blockchain"),
                CommandItem(example: "sync", description: "Synchronize wallet data"),
                CommandItem(example: "reload", description: "Reload wallet information"),
                CommandItem(example: "update", description: "Update balance and transactions"),
                CommandItem(example: "resync wallet", description: "Full wallet resynchronization"),
            ]
        ),

        // 13. Settings
        CommandCategory(
            name: "Settings",
            icon: "gearshape.fill",
            color: AppColors.textSecondary,
            commands: [
                CommandItem(example: "settings", description: "Open the settings panel"),
                CommandItem(example: "preferences", description: "View app preferences"),
                CommandItem(example: "about", description: "App version and information"),
                CommandItem(example: "version", description: "Check current app version"),
            ]
        ),

        // 14. Help
        CommandCategory(
            name: "Help",
            icon: "questionmark.circle.fill",
            color: AppColors.accent,
            commands: [
                CommandItem(example: "help", description: "Show a quick overview of commands"),
                CommandItem(example: "what can you do", description: "See all available capabilities"),
                CommandItem(example: "commands", description: "List available commands"),
                CommandItem(example: "how to", description: "Get usage instructions"),
            ]
        ),

        // 15. Greetings & General
        CommandCategory(
            name: "General",
            icon: "hand.wave.fill",
            color: AppColors.warning,
            commands: [
                CommandItem(example: "hello", description: "Start a conversation with a greeting"),
                CommandItem(example: "hey", description: "Casual greeting"),
                CommandItem(example: "good morning", description: "Time-based greeting"),
                CommandItem(example: "(paste a txid)", description: "Auto-detect and show transaction details"),
                CommandItem(example: "(paste an address)", description: "Auto-detect and start a send flow"),
            ]
        ),
    ]
}

// MARK: - Preview

#if DEBUG
struct CommandsReferenceView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            CommandsReferenceView()
        }
        .preferredColorScheme(.dark)
    }
}
#endif
