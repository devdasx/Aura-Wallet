import SwiftUI
import SwiftData

// MARK: - MainWalletView
// Primary app screen combining NavigationSplitView sidebar with
// balance header, chat, quick actions, and input bar.
//
// The sidebar slides in from the left (like Claude) showing
// conversation history. The detail view is the chat interface.
//
// Layout — Detail (top to bottom):
//   1. BalanceHeaderView  — fixed at top, with sidebar toggle
//   2. ChatView / WelcomeView — flex area
//   3. ChatInputBar       — floating at bottom

struct MainWalletView: View {
    @StateObject private var chatViewModel = ChatViewModel()
    @StateObject private var walletState = WalletState()
    @EnvironmentObject var appRouter: AppRouter
    @Environment(\.modelContext) private var modelContext

    @State private var isBalanceSwapped: Bool = false
    @State private var selectedConversation: Conversation?
    @State private var isSidebarOpen: Bool = false
    @State private var conversationManager: ConversationManager?
    @State private var showQRScanner: Bool = false
    @GestureState private var dragOffset: CGFloat = 0

    private let sidebarWidth: CGFloat = min(UIScreen.main.bounds.width * 0.82, 320)

    var body: some View {
        ZStack(alignment: .leading) {
            // DETAIL — the chat interface (always visible)
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .gesture(
                    DragGesture()
                        .onEnded { value in
                            let startX = value.startLocation.x
                            let translationX = value.translation.width
                            // Swipe from left edge to open sidebar
                            if !isSidebarOpen && startX < 25 && translationX > 80 {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    isSidebarOpen = true
                                }
                            }
                            // Swipe left to close sidebar
                            if isSidebarOpen && translationX < -80 {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    isSidebarOpen = false
                                }
                            }
                        }
                )

            // Dimming overlay when sidebar is open
            Color.black.opacity(isSidebarOpen ? 0.35 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(isSidebarOpen)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isSidebarOpen = false
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: isSidebarOpen)

            // SIDEBAR — slides from left
            if let manager = conversationManager {
                ConversationSidebarView(
                    selectedConversation: $selectedConversation,
                    isOpen: $isSidebarOpen,
                    conversationManager: manager,
                    onSettings: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isSidebarOpen = false
                        }
                        NotificationCenter.default.post(
                            name: .navigateToSettings,
                            object: nil
                        )
                    }
                )
                .frame(width: sidebarWidth)
                .background(AppColors.backgroundPrimary)
                .appShadow(AppShadows.large)
                .offset(x: isSidebarOpen ? 0 : -sidebarWidth - 20)
                .animation(.easeInOut(duration: 0.25), value: isSidebarOpen)
            }
        }
        .onAppear {
            setupConversationManager()
            appRouter.registerUserActivity()
            syncWalletStateToChatViewModel()
            Task { await walletState.refresh() }
        }
        .onChange(of: selectedConversation) { _, newConversation in
            if let conversation = newConversation {
                chatViewModel.loadConversation(conversation)
            }
        }
        .onChange(of: walletState.btcBalance) { _, _ in
            syncWalletStateToChatViewModel()
        }
        .onChange(of: walletState.currentReceiveAddress) { _, _ in
            syncWalletStateToChatViewModel()
        }
        .onChange(of: walletState.recentTransactions.count) { _, _ in
            syncWalletStateToChatViewModel()
        }
        .onChange(of: walletState.lastUpdated) { _, _ in
            syncWalletStateToChatViewModel()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .chatInjectCommand)
        ) { notification in
            if let command = notification.userInfo?["command"] as? String {
                chatViewModel.sendMessage(command)
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .walletRefreshRequested)
        ) { _ in
            let processing = ProcessingConfigurations.walletRefresh()
            chatViewModel.activeProcessingState = processing
            processing.start()

            Task {
                processing.completeCurrentStep()
                await walletState.refresh()
                processing.completeCurrentStep()
                syncWalletStateToChatViewModel()
                processing.completeCurrentStep()
                processing.completeCurrentStep()
                await chatViewModel.dismissProcessingCard()

                let context = chatViewModel.buildContext()
                let responses = chatViewModel.responseGenerator.generateResponse(for: .balance, context: context)
                chatViewModel.appendResponses(responses)
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .openQRScannerForSend)
        ) { _ in
            showQRScanner = true
        }
        .sheet(isPresented: $showQRScanner) {
            QRScannerView { scannedText in
                chatViewModel.inputText = scannedText
                chatViewModel.sendMessage()
            }
        }
        .sheet(isPresented: $chatViewModel.showAuthSheet) {
            AuthenticationSheet(
                reason: "Authenticate to sign this Bitcoin transaction",
                onSuccess: {
                    Task { await chatViewModel.handleAuthSuccess() }
                },
                onCancel: {
                    chatViewModel.handleAuthCancelled()
                }
            )
        }
    }

    // MARK: - Detail View

    private var detailView: some View {
        VStack(spacing: 0) {
            // 1. Balance Header (with sidebar toggle + new chat)
            BalanceHeaderView(
                btcBalance: walletState.btcBalance,
                fiatBalance: walletState.fiatBalance,
                currencyCode: UserPreferences.shared.displayCurrency,
                isHidden: walletState.isBalanceHidden,
                isSwapped: $isBalanceSwapped,
                onSidebar: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isSidebarOpen = true
                    }
                },
                onNewChat: {
                    guard let manager = conversationManager else { return }
                    let conversation = manager.createNewConversation()
                    selectedConversation = conversation
                    chatViewModel.loadConversation(conversation)
                }
            )

            Divider()
                .background(AppColors.separator)

            // 2. Chat Area or Welcome View
            if chatViewModel.isNewEmptyConversation {
                NewChatWelcomeView(
                    btcBalance: walletState.btcBalance,
                    fiatBalance: walletState.fiatBalance,
                    currencyCode: UserPreferences.shared.displayCurrency
                )
            } else {
                ChatView(viewModel: chatViewModel)
                    .environmentObject(chatViewModel)
            }

            // 3. Chat Input Bar
            ChatInputBar(
                text: $chatViewModel.inputText,
                onSend: { chatViewModel.sendMessage() },
                onScanQR: { showQRScanner = true },
                onPaste: { handlePaste() }
            )
        }
        .background(AppColors.backgroundPrimary)
        .onTapGesture {
            dismissKeyboard()
        }
    }

    // MARK: - Setup

    private func setupConversationManager() {
        guard conversationManager == nil else { return }
        let manager = ConversationManager(modelContext: modelContext)
        manager.loadOrCreateInitial()
        conversationManager = manager
        chatViewModel.conversationManager = manager

        // Load the initial conversation
        if let current = manager.currentConversation {
            selectedConversation = current
            chatViewModel.loadConversation(current)
        }
    }

    // MARK: - Helpers

    /// Bridges wallet state properties into the ChatViewModel so the chat
    /// response generator can access live wallet data (balance, addresses, etc.).
    private func syncWalletStateToChatViewModel() {
        chatViewModel.walletState = walletState
        chatViewModel.walletBalance = walletState.btcBalance
        chatViewModel.fiatBalance = walletState.fiatBalance
        chatViewModel.pendingBalance = walletState.pendingBalance
        chatViewModel.currentReceiveAddress = walletState.currentReceiveAddress
        chatViewModel.addressType = walletState.addressTypeLabel
        chatViewModel.utxoCount = walletState.utxoStore.count

        // Sync fee estimates
        chatViewModel.currentFeeEstimates = walletState.feeEstimates

        // Convert TransactionModel → TransactionDisplayItem for chat
        chatViewModel.recentTransactions = walletState.recentTransactions.map { tx in
            TransactionDisplayItem(
                txid: tx.txid,
                type: tx.type == .sent ? "sent" : "received",
                amount: tx.amount,
                address: tx.type == .sent
                    ? (tx.toAddresses.first ?? "Unknown")
                    : (tx.fromAddresses.first ?? "Unknown"),
                date: tx.timestamp,
                confirmations: tx.confirmations,
                status: tx.status == .confirmed ? "confirmed" : "pending"
            )
        }
    }

    /// Handles the paste button: reads clipboard, detects content type,
    /// and populates the input field or sends directly.
    private func handlePaste() {
        guard let text = UIPasteboard.general.string else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check for BIP21 URI
        if let parsed = BIP21Parser.parse(trimmed) {
            var command = "send"
            if let amount = parsed.amount { command += " \(amount) BTC" }
            command += " to \(parsed.address)"
            chatViewModel.inputText = command
            chatViewModel.sendMessage()
            return
        }

        // Check for plain Bitcoin address
        let validator = AddressValidator()
        if validator.isValid(trimmed) {
            chatViewModel.inputText = trimmed
            return
        }

        // Check for transaction ID (64 hex chars)
        let hexSet = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        if trimmed.count == 64 && trimmed.unicodeScalars.allSatisfy({ hexSet.contains($0) }) {
            chatViewModel.inputText = trimmed
            chatViewModel.sendMessage()
            return
        }

        // Fallback: paste as plain text
        chatViewModel.inputText = trimmed
    }

    /// Dismisses the keyboard by resigning first responder.
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

// MARK: - WalletState
// Observable state for wallet balance data displayed in the main view.
// Manages BTC balance, fiat equivalent, pending amounts, and refresh state.
// Performs full HD wallet address discovery across BIP44, BIP49, BIP84, BIP86
// with gap limit scanning for both receive and change chains.
// Coordinates blockchain data fetching through BlockbookAPI and stores
// results in UTXOStore and TransactionCache.

@MainActor
final class WalletState: ObservableObject {

    // MARK: - Published Properties

    /// The total confirmed BTC balance in the wallet (all address types combined).
    @Published var btcBalance: Decimal = 0

    /// The fiat (USD) equivalent of the BTC balance.
    @Published var fiatBalance: Decimal = 0

    /// The amount of BTC in unconfirmed/pending transactions.
    @Published var pendingBalance: Decimal = 0

    /// Whether the balance display is hidden for privacy.
    @Published var isBalanceHidden: Bool = false

    /// Whether a balance refresh is currently in progress.
    @Published var isRefreshing: Bool = false

    /// Timestamp of the last successful balance fetch.
    @Published var lastUpdated: Date = Date()

    /// The current unused receive address, generated locally from the HD wallet.
    @Published var currentReceiveAddress: String = ""

    /// The address type label for the current receive address.
    @Published var addressTypeLabel: String = "SegWit"

    /// Recent transactions for display (all address types merged, sorted by timestamp).
    @Published var recentTransactions: [TransactionModel] = []

    /// Discovery progress message shown during full scan.
    @Published var discoveryStatus: String = ""

    /// Current fee estimates (sat/vB) for the three tiers, fetched from Blockbook.
    @Published var feeEstimates: (slow: Decimal, medium: Decimal, fast: Decimal)?

    // MARK: - Dependencies

    /// The Blockbook API client for fetching blockchain data.
    private let blockbookAPI: BlockbookAPIProtocol

    /// Fee estimator for fetching network fee rates.
    private let feeEstimator: FeeEstimator

    /// The UTXO store for persisting and querying UTXOs.
    let utxoStore: UTXOStore

    /// The transaction cache for persisting transaction history.
    let transactionCache: TransactionCache

    /// The preferred address type for receiving.
    var preferredAddressType: AddressType = .segwit

    /// The HD wallet instance for address generation.
    var hdWallet: HDWallet? {
        didSet {
            generateReceiveAddressIfNeeded()
        }
    }

    /// Gap limit: stop scanning after this many consecutive unused addresses.
    private let gapLimit: Int = 20

    /// All wallet addresses discovered during scanning (for tx classification).
    private var allWalletAddresses: Set<String> = []

    // MARK: - Initialization

    init() {
        let api = BlockbookAPI()
        self.blockbookAPI = api
        self.feeEstimator = FeeEstimator(blockbookAPI: api)
        self.utxoStore = UTXOStore()
        self.transactionCache = TransactionCache()

        // Load persisted balance from UTXO store
        self.btcBalance = utxoStore.confirmedBalance
        self.pendingBalance = utxoStore.unconfirmedBalance

        // Load wallet from Keychain if available
        loadWalletFromKeychain()
    }

    // MARK: - Wallet Loading

    private func loadWalletFromKeychain() {
        do {
            let seedData = try KeychainManager.shared.read(key: .encryptedSeed)
            guard let phrase = String(data: seedData, encoding: .utf8) else {
                AppLogger.error("Seed data is not valid UTF-8", category: .wallet)
                return
            }
            let wallet = try HDWallet.restore(phrase: phrase)

            // Restore all address indices from UserPreferences
            let prefs = UserPreferences.shared
            wallet.currentLegacyReceiveIndex = UInt32(prefs.legacyReceiveIndex)
            wallet.currentLegacyChangeIndex = UInt32(prefs.legacyChangeIndex)
            wallet.currentNestedSegwitReceiveIndex = UInt32(prefs.nestedSegwitReceiveIndex)
            wallet.currentNestedSegwitChangeIndex = UInt32(prefs.nestedSegwitChangeIndex)
            wallet.currentReceiveIndex = UInt32(prefs.receiveAddressIndex)
            wallet.currentChangeIndex = UInt32(prefs.changeAddressIndex)
            wallet.currentTaprootReceiveIndex = UInt32(prefs.taprootReceiveIndex)
            wallet.currentTaprootChangeIndex = UInt32(prefs.taprootChangeIndex)

            self.hdWallet = wallet
            AppLogger.info("HD Wallet loaded from Keychain successfully", category: .wallet)
        } catch KeychainManager.KeychainError.itemNotFound {
            AppLogger.info("No seed in Keychain -- wallet not yet created", category: .wallet)
        } catch KeychainManager.KeychainError.accessError {
            AppLogger.info("Keychain access denied (biometric needed) -- will retry", category: .wallet)
        } catch {
            AppLogger.error("Failed to load wallet from Keychain: \(error.localizedDescription)", category: .wallet)
        }
    }

    // MARK: - Address Generation (Offline)

    func generateReceiveAddressIfNeeded() {
        guard let wallet = hdWallet, currentReceiveAddress.isEmpty else { return }
        do {
            let index: UInt32
            switch preferredAddressType {
            case .legacy:
                index = wallet.currentLegacyReceiveIndex
            case .nestedSegwit:
                index = wallet.currentNestedSegwitReceiveIndex
            case .segwit:
                index = wallet.currentReceiveIndex
            case .taproot:
                index = wallet.currentTaprootReceiveIndex
            }
            let address = try wallet.addressAt(
                type: preferredAddressType,
                change: 0,
                index: index
            )
            currentReceiveAddress = address
            addressTypeLabel = preferredAddressType.displayName
        } catch {
            currentReceiveAddress = ""
        }
    }

    func generateNextReceiveAddress() {
        guard let wallet = hdWallet else { return }
        do {
            let address = try wallet.nextReceiveAddress(type: preferredAddressType)
            currentReceiveAddress = address
            addressTypeLabel = preferredAddressType.displayName
        } catch {
            currentReceiveAddress = ""
        }
    }

    // MARK: - Full HD Wallet Refresh via xpub/zpub/ypub

    /// Fetches wallet data using Blockbook's xpub API for efficient discovery.
    ///
    /// Instead of scanning addresses one by one, this passes the extended public
    /// key (xpub/ypub/zpub) to Blockbook which performs server-side discovery
    /// with gap limit. This reduces API calls from 160+ to just ~8.
    ///
    /// For each address type (BIP44, BIP49, BIP84, BIP86):
    ///   1. GET /api/v2/xpub/{key}?details=txs&tokens=used  → balance + txs + used addresses
    ///   2. GET /api/v2/utxo/{key}  → all UTXOs with derivation paths
    ///
    /// All results are aggregated into a single balance.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer {
            isRefreshing = false
            discoveryStatus = ""
        }

        // Always fetch BTC price using user's preferred currency,
        // regardless of whether the wallet is loaded yet.
        let currency = UserPreferences.shared.displayCurrency
        if let price = await PriceService.shared.fetchPrice(for: currency) {
            fiatBalance = btcBalance * price
            AppLogger.info("BTC price: \(price) \(currency), fiat balance: \(fiatBalance)", category: .wallet)
        }

        // Try loading wallet from Keychain if not yet loaded
        if hdWallet == nil {
            loadWalletFromKeychain()
        }

        guard let wallet = hdWallet else {
            AppLogger.warning("Cannot refresh: wallet not available.", category: .wallet)
            generateReceiveAddressIfNeeded()
            return
        }

        // Address types to scan with their extended key format
        let addressTypes: [AddressType] = [.legacy, .nestedSegwit, .segwit, .taproot]

        var totalConfirmedSats: Int64 = 0
        var totalPendingSats: Int64 = 0
        var allUTXOs: [UTXOModel] = []
        var allTransactions: [TransactionModel] = []
        var seenTxids: Set<String> = []
        allWalletAddresses = []

        do {
            for addressType in addressTypes {
                discoveryStatus = "Fetching \(addressType.displayName)..."

                // 1. Get the extended public key (xpub/ypub/zpub) for this type
                let extKey: String
                do {
                    extKey = try wallet.extendedPublicKeyForType(addressType)
                } catch {
                    AppLogger.error("Failed to derive extended key for \(addressType.displayName): \(error)", category: .wallet)
                    continue
                }

                AppLogger.info("Querying \(addressType.displayName) balance via extended public key", category: .wallet)

                // 2. Fetch xpub info (balance + transactions + used addresses)
                let xpubInfo: BlockbookXpubInfo
                do {
                    xpubInfo = try await blockbookAPI.getXpub(
                        extKey,
                        details: "txs",
                        tokens: "used",
                        gap: gapLimit
                    )
                } catch {
                    AppLogger.error("Failed to query xpub for \(addressType.displayName): \(error.localizedDescription)", category: .network)
                    continue
                }

                // 3. Accumulate balance
                let confirmedSats = Int64(xpubInfo.balance) ?? 0
                let unconfirmedSats = Int64(xpubInfo.unconfirmedBalance) ?? 0
                totalConfirmedSats += confirmedSats
                totalPendingSats += unconfirmedSats

                AppLogger.info(
                    "\(addressType.displayName): balance=\(confirmedSats) sats, txs=\(xpubInfo.txs), used=\(xpubInfo.usedTokens ?? 0)",
                    category: .wallet
                )

                // 4. Collect all used addresses from tokens for tx classification
                if let tokens = xpubInfo.tokens {
                    for token in tokens {
                        allWalletAddresses.insert(token.name)
                    }
                    // Update wallet indices based on highest used address path
                    updateIndicesFromTokens(wallet: wallet, type: addressType, tokens: tokens)
                }

                // 5. Fetch UTXOs for this extended key
                do {
                    let blockbookUTXOs = try await blockbookAPI.getUTXOs(for: extKey)
                    for utxo in blockbookUTXOs {
                        let valueSats = Int64(utxo.value) ?? 0
                        let valueBTC = Decimal(valueSats) / Constants.satoshisPerBTC
                        allUTXOs.append(UTXOModel(
                            txid: utxo.txid,
                            vout: utxo.vout,
                            value: valueBTC,
                            valueSats: valueSats,
                            confirmations: utxo.confirmations,
                            address: utxo.address ?? "",
                            scriptPubKey: nil,
                            isSpent: false,
                            derivationPath: utxo.path
                        ))
                    }
                } catch {
                    AppLogger.error("Failed to fetch UTXOs for \(addressType.displayName): \(error.localizedDescription)", category: .network)
                }

                // 6. Collect transactions (deduplicated across all types)
                if let transactions = xpubInfo.transactions {
                    for tx in transactions where !seenTxids.contains(tx.txid) {
                        seenTxids.insert(tx.txid)
                        let txModel = self.parseTransaction(tx, walletAddresses: allWalletAddresses)
                        allTransactions.append(txModel)
                    }
                }
            }

            // Update published state with aggregated results
            btcBalance = Decimal(totalConfirmedSats) / Constants.satoshisPerBTC
            pendingBalance = Decimal(totalPendingSats) / Constants.satoshisPerBTC

            // Store all UTXOs
            utxoStore.updateUTXOs(allUTXOs)

            // Sort transactions by timestamp descending and cache
            allTransactions.sort { $0.timestamp > $1.timestamp }
            await transactionCache.cacheTransactions(allTransactions)
            recentTransactions = Array(allTransactions.prefix(50))

            // Generate the next unused receive address for the preferred type
            currentReceiveAddress = ""
            generateReceiveAddressIfNeeded()

            // Persist address indices
            persistAddressIndices(wallet: wallet)

            // Fetch fee estimates from Blockbook
            do {
                let fees = try await feeEstimator.estimateFees()
                feeEstimates = (
                    slow: fees.slow.satPerVByte,
                    medium: fees.medium.satPerVByte,
                    fast: fees.fast.satPerVByte
                )
                AppLogger.info("Fee estimates: slow=\(fees.slow.satPerVByte) med=\(fees.medium.satPerVByte) fast=\(fees.fast.satPerVByte) sat/vB", category: .wallet)
            } catch {
                AppLogger.warning("Fee estimation failed, using fallbacks: \(error.localizedDescription)", category: .network)
                feeEstimates = (slow: 5, medium: 15, fast: 30)
            }

            // Re-compute fiat balance now that btcBalance is finalized
            if let price = PriceService.shared.currentPrice {
                fiatBalance = btcBalance * price
            }

            lastUpdated = Date()
            UserPreferences.shared.recordSync()
            AppLogger.info(
                "Wallet refresh completed. Balance: \(btcBalance) BTC, UTXOs: \(allUTXOs.count), Txs: \(allTransactions.count)",
                category: .wallet
            )

        } catch {
            AppLogger.error("Wallet refresh failed: \(error.localizedDescription)", category: .network)
            ErrorHandler.shared.handle(error) { [weak self] in
                Task { await self?.refresh() }
            }
        }
    }

    // MARK: - Private Helpers

    /// Updates wallet address indices based on the used tokens returned by the xpub query.
    /// Parses derivation paths like "m/84'/0'/0'/0/5" to find the highest used index
    /// for each chain (receive/change).
    private func updateIndicesFromTokens(wallet: HDWallet, type: AddressType, tokens: [BlockbookToken]) {
        var highestReceive: Int = -1
        var highestChange: Int = -1

        for token in tokens {
            let path = token.path
            // Path format: m/purpose'/coin'/account'/change/index
            let components = path.split(separator: "/")
            guard components.count >= 6 else { continue }

            // Parse chain (second-to-last) and index (last)
            let chainStr = String(components[components.count - 2])
            let indexStr = String(components[components.count - 1])

            guard let chain = Int(chainStr), let index = Int(indexStr) else { continue }

            if chain == 0 {
                highestReceive = max(highestReceive, index)
            } else if chain == 1 {
                highestChange = max(highestChange, index)
            }
        }

        // Set next index to one past the highest used
        let nextReceive = UInt32(max(highestReceive + 1, 0))
        let nextChange = UInt32(max(highestChange + 1, 0))

        switch type {
        case .legacy:
            wallet.currentLegacyReceiveIndex = max(wallet.currentLegacyReceiveIndex, nextReceive)
            wallet.currentLegacyChangeIndex = max(wallet.currentLegacyChangeIndex, nextChange)
        case .nestedSegwit:
            wallet.currentNestedSegwitReceiveIndex = max(wallet.currentNestedSegwitReceiveIndex, nextReceive)
            wallet.currentNestedSegwitChangeIndex = max(wallet.currentNestedSegwitChangeIndex, nextChange)
        case .segwit:
            wallet.currentReceiveIndex = max(wallet.currentReceiveIndex, nextReceive)
            wallet.currentChangeIndex = max(wallet.currentChangeIndex, nextChange)
        case .taproot:
            wallet.currentTaprootReceiveIndex = max(wallet.currentTaprootReceiveIndex, nextReceive)
            wallet.currentTaprootChangeIndex = max(wallet.currentTaprootChangeIndex, nextChange)
        }
    }

    /// Persists all address indices to UserPreferences.
    private func persistAddressIndices(wallet: HDWallet) {
        let prefs = UserPreferences.shared
        prefs.legacyReceiveIndex = Int(wallet.currentLegacyReceiveIndex)
        prefs.legacyChangeIndex = Int(wallet.currentLegacyChangeIndex)
        prefs.nestedSegwitReceiveIndex = Int(wallet.currentNestedSegwitReceiveIndex)
        prefs.nestedSegwitChangeIndex = Int(wallet.currentNestedSegwitChangeIndex)
        prefs.receiveAddressIndex = Int(wallet.currentReceiveIndex)
        prefs.changeAddressIndex = Int(wallet.currentChangeIndex)
        prefs.taprootReceiveIndex = Int(wallet.currentTaprootReceiveIndex)
        prefs.taprootChangeIndex = Int(wallet.currentTaprootChangeIndex)
    }

    /// Parses a Blockbook transaction into a TransactionModel.
    /// Uses the full set of wallet addresses for accurate sent/received classification.
    private func parseTransaction(_ tx: BlockbookTransaction, walletAddresses: Set<String>) -> TransactionModel {
        // Determine if sent: any input belongs to our wallet
        let isSent = tx.vin.contains { vin in
            vin.addresses?.contains(where: { walletAddresses.contains($0) }) == true
        }

        let txType: TransactionModel.TransactionType = isSent ? .sent : .received

        // Calculate net amount relevant to our wallet
        var amountSats: Int64 = 0
        if txType == .received {
            for vout in tx.vout {
                if vout.addresses?.contains(where: { walletAddresses.contains($0) }) == true {
                    amountSats += Int64(vout.value) ?? 0
                }
            }
        } else {
            for vin in tx.vin {
                if vin.addresses?.contains(where: { walletAddresses.contains($0) }) == true {
                    amountSats += Int64(vin.value ?? "0") ?? 0
                }
            }
            for vout in tx.vout {
                if vout.addresses?.contains(where: { walletAddresses.contains($0) }) == true {
                    amountSats -= Int64(vout.value) ?? 0
                }
            }
        }

        let amountBTC = Decimal(abs(amountSats)) / Constants.satoshisPerBTC
        let feeSats = Int64(tx.fees) ?? 0
        let feeBTC = Decimal(feeSats) / Constants.satoshisPerBTC

        let fromAddresses = tx.vin.compactMap { $0.addresses?.first }
        let toAddresses = tx.vout.compactMap { $0.addresses?.first }

        let status: TransactionModel.TransactionStatus =
            tx.confirmations > 0 ? .confirmed : .pending
        let timestamp = Date(timeIntervalSince1970: TimeInterval(tx.blockTime))

        return TransactionModel(
            id: tx.txid,
            txid: tx.txid,
            type: txType,
            amount: amountBTC,
            fee: feeBTC,
            fromAddresses: fromAddresses,
            toAddresses: toAddresses,
            confirmations: tx.confirmations,
            blockHeight: tx.blockHeight,
            timestamp: timestamp,
            size: tx.size,
            virtualSize: tx.vsize,
            status: status
        )
    }
}

// MARK: - Preview

#if DEBUG
struct MainWalletView_Previews: PreviewProvider {
    static var previews: some View {
        MainWalletView()
            .environmentObject(AppRouter())
            .preferredColorScheme(.dark)
    }
}
#endif
