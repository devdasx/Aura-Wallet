// MARK: - ResponseGenerator.swift
// Bitcoin AI Wallet
//
// Generates context-aware AI-style responses based on parsed intents
// and current wallet state. Produces typed response values that the
// UI layer can render as text bubbles, rich cards, or error banners.
//
// Expanded with tips, action buttons, price cards, and smart fallback.
//
// Platform: iOS 17.0+
// Framework: Foundation

import Foundation

// MARK: - ResponseType

/// A typed response that the chat UI can render.
enum ResponseType: Equatable {

    /// A plain text message bubble.
    case text(String)

    /// A balance summary card.
    case balanceCard(btc: Decimal, fiat: Decimal, pending: Decimal, utxoCount: Int)

    /// A send confirmation card.
    case sendConfirmCard(
        toAddress: String,
        amount: Decimal,
        fee: Decimal,
        feeRate: Decimal,
        estimatedTime: Int,
        remainingBalance: Decimal
    )

    /// A receive address card with QR code.
    case receiveCard(address: String, addressType: String)

    /// A transaction history card.
    case historyCard(transactions: [TransactionDisplayItem])

    /// A success card after transaction broadcast.
    case successCard(txid: String, amount: Decimal, toAddress: String)

    /// A fee estimate card with three tiers.
    case feeCard(slow: FeeDisplayItem, medium: FeeDisplayItem, fast: FeeDisplayItem)

    /// A Bitcoin price card.
    case priceCard(btcPrice: Decimal, currency: String, formattedPrice: String)

    /// A tip card displayed below responses.
    case tipsCard(tip: TipItem)

    /// Interactive action buttons below a response.
    case actionButtons(buttons: [ActionButton])

    /// An error message displayed as a distinct error bubble.
    case errorText(String)

    // MARK: - Equatable

    static func == (lhs: ResponseType, rhs: ResponseType) -> Bool {
        switch (lhs, rhs) {
        case (.text(let a), .text(let b)):
            return a == b
        case (.balanceCard(let aB, let aF, let aP, let aU), .balanceCard(let bB, let bF, let bP, let bU)):
            return aB == bB && aF == bF && aP == bP && aU == bU
        case (.sendConfirmCard(let aAddr, let aAmt, let aFee, let aRate, let aTime, let aRem),
              .sendConfirmCard(let bAddr, let bAmt, let bFee, let bRate, let bTime, let bRem)):
            return aAddr == bAddr && aAmt == bAmt && aFee == bFee && aRate == bRate && aTime == bTime && aRem == bRem
        case (.receiveCard(let aAddr, let aType), .receiveCard(let bAddr, let bType)):
            return aAddr == bAddr && aType == bType
        case (.historyCard(let a), .historyCard(let b)):
            return a == b
        case (.successCard(let aTx, let aAmt, let aAddr), .successCard(let bTx, let bAmt, let bAddr)):
            return aTx == bTx && aAmt == bAmt && aAddr == bAddr
        case (.feeCard(let aS, let aM, let aF), .feeCard(let bS, let bM, let bF)):
            return aS == bS && aM == bM && aF == bF
        case (.priceCard(let aP, let aC, let aFP), .priceCard(let bP, let bC, let bFP)):
            return aP == bP && aC == bC && aFP == bFP
        case (.tipsCard(let a), .tipsCard(let b)):
            return a == b
        case (.actionButtons(let a), .actionButtons(let b)):
            return a == b
        case (.errorText(let a), .errorText(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - TransactionDisplayItem

struct TransactionDisplayItem: Equatable, Identifiable {
    let id: String
    let txid: String
    let type: String
    let amount: Decimal
    let address: String
    let date: Date
    let confirmations: Int
    let status: String

    init(txid: String, type: String, amount: Decimal, address: String, date: Date, confirmations: Int, status: String) {
        self.id = txid
        self.txid = txid
        self.type = type
        self.amount = amount
        self.address = address
        self.date = date
        self.confirmations = confirmations
        self.status = status
    }

    static func == (lhs: TransactionDisplayItem, rhs: TransactionDisplayItem) -> Bool {
        lhs.txid == rhs.txid && lhs.type == rhs.type && lhs.amount == rhs.amount
            && lhs.address == rhs.address && lhs.confirmations == rhs.confirmations
    }
}

// MARK: - FeeDisplayItem

struct FeeDisplayItem: Equatable {
    let level: String
    let satPerVB: Decimal
    let estimatedMinutes: Int
    let estimatedCost: Decimal
}

// MARK: - ConversationContext

struct ConversationContext {
    var walletBalance: Decimal?
    var fiatBalance: Decimal?
    var pendingBalance: Decimal?
    var utxoCount: Int?
    var pendingTransaction: PendingTransactionInfo?
    var recentTransactions: [TransactionDisplayItem]?
    var currentFeeEstimates: (slow: Decimal, medium: Decimal, fast: Decimal)?
    var currentReceiveAddress: String?
    var addressType: String?
    var conversationState: ConversationState
    var btcPrice: Decimal?
    var priceCurrency: String?

    init(
        walletBalance: Decimal? = nil,
        fiatBalance: Decimal? = nil,
        pendingBalance: Decimal? = nil,
        utxoCount: Int? = nil,
        pendingTransaction: PendingTransactionInfo? = nil,
        recentTransactions: [TransactionDisplayItem]? = nil,
        currentFeeEstimates: (slow: Decimal, medium: Decimal, fast: Decimal)? = nil,
        currentReceiveAddress: String? = nil,
        addressType: String? = nil,
        conversationState: ConversationState = .idle,
        btcPrice: Decimal? = nil,
        priceCurrency: String? = nil
    ) {
        self.walletBalance = walletBalance
        self.fiatBalance = fiatBalance
        self.pendingBalance = pendingBalance
        self.utxoCount = utxoCount
        self.pendingTransaction = pendingTransaction
        self.recentTransactions = recentTransactions
        self.currentFeeEstimates = currentFeeEstimates
        self.currentReceiveAddress = currentReceiveAddress
        self.addressType = addressType
        self.conversationState = conversationState
        self.btcPrice = btcPrice
        self.priceCurrency = priceCurrency
    }
}

// MARK: - PendingTransactionInfo

struct PendingTransactionInfo: Equatable {
    let toAddress: String
    let amount: Decimal
    let fee: Decimal
    let feeRate: Decimal
    let estimatedMinutes: Int
}

// MARK: - ResponseGenerator

final class ResponseGenerator {

    private static let satoshisPerBTC: Decimal = 100_000_000
    private static let typicalVSize: Int = 140

    private let tipsEngine = TipsEngine()

    // MARK: - Public API (Legacy — no memory)

    @MainActor
    func generateResponse(
        for intent: WalletIntent,
        context: ConversationContext
    ) -> [ResponseType] {
        generateResponse(for: intent, context: context, memory: nil, classification: nil)
    }

    // MARK: - Smart API (with memory + classification)

    /// Memory-aware response generation with varied templates and context-aware output.
    @MainActor
    func generateResponse(
        for intent: WalletIntent,
        context: ConversationContext,
        memory: ConversationMemory?,
        classification: ClassificationResult?
    ) -> [ResponseType] {
        var responses: [ResponseType]

        switch intent {
        case .balance:
            responses = generateBalanceResponse(context: context, memory: memory)
        case .send(let amount, let unit, let address, let feeLevel):
            responses = generateSendResponse(amount: amount, unit: unit, address: address, feeLevel: feeLevel, context: context)
        case .receive:
            responses = generateReceiveResponse(context: context)
        case .history(let count):
            responses = generateHistoryResponse(count: count, context: context)
        case .feeEstimate:
            responses = generateFeeResponse(context: context)
        case .price(let currency):
            responses = generatePriceResponse(currency: currency, context: context)
        case .convertAmount(let amount, let fromCurrency):
            responses = generateConvertResponse(amount: amount, currency: fromCurrency, context: context)
        case .newAddress:
            responses = generateNewAddressResponse(context: context)
        case .walletHealth:
            responses = generateWalletHealthResponse(context: context)
        case .exportHistory:
            responses = generateExportResponse(context: context)
        case .utxoList:
            responses = generateUTXOResponse(context: context)
        case .bumpFee(let txid):
            responses = generateBumpFeeResponse(txid: txid, context: context)
        case .networkStatus:
            responses = generateNetworkStatusResponse(context: context)
        case .help:
            responses = [.text(ResponseTemplates.helpResponse())]
        case .about:
            responses = [.text(ResponseTemplates.aboutResponse())]
        case .greeting:
            responses = generateGreetingResponse(memory: memory)
        case .confirmAction:
            responses = generateConfirmResponse(context: context)
        case .cancelAction:
            responses = generateCancelResponse(context: context)
        case .hideBalance:
            responses = [.text(ResponseTemplates.balanceHidden())]
        case .showBalance:
            responses = [.text(ResponseTemplates.balanceShown())]
        case .refreshWallet:
            responses = [.text(ResponseTemplates.walletRefreshing())]
        case .settings:
            responses = [.text(ResponseTemplates.openingSettings())]
        case .transactionDetail(let txid):
            responses = generateTxDetailResponse(txid: txid, context: context)
        case .unknown:
            responses = generateSmartFallback(context: context, classification: classification)
        }

        return responses
    }

    // MARK: - ShownData Extraction

    /// Extracts what data was shown to the user from the generated responses.
    /// Used by ChatViewModel to update ConversationMemory.
    func extractShownData(from responses: [ResponseType], context: ConversationContext) -> ShownData? {
        var data = ShownData()
        var hasData = false

        for response in responses {
            switch response {
            case .balanceCard(let btc, let fiat, _, _):
                data.balance = btc
                data.fiatBalance = fiat
                hasData = true
            case .historyCard(let txs):
                data.transactions = txs
                hasData = true
            case .feeCard(let slow, let medium, let fast):
                data.feeEstimates = (slow: slow.satPerVB, medium: medium.satPerVB, fast: fast.satPerVB)
                hasData = true
            case .receiveCard(let address, _):
                data.receiveAddress = address
                hasData = true
            case .successCard(let txid, let amount, let toAddress):
                data.sentTransaction = (txid: txid, amount: amount, address: toAddress, fee: 0)
                hasData = true
            default:
                break
            }
        }

        return hasData ? data : nil
    }

    // MARK: - Balance Response

    @MainActor
    private func generateBalanceResponse(context: ConversationContext, memory: ConversationMemory? = nil) -> [ResponseType] {
        guard let btc = context.walletBalance else {
            return [.errorText(ResponseTemplates.networkError())]
        }
        let fiat = context.fiatBalance ?? Decimal.zero
        let pending = context.pendingBalance ?? Decimal.zero
        let utxos = context.utxoCount ?? 0

        let textResponse: String

        // Context-aware: balance after a recent send
        if let mem = memory, let sent = mem.lastSentTx, mem.turnsSinceLastSend() < 4 {
            textResponse = ResponseTemplates.balanceAfterSend(
                btcAmount: formatBTC(btc),
                fiatAmount: formatFiat(fiat),
                sentAmount: formatBTC(sent.amount),
                pendingAmount: pending > 0 ? formatBTC(pending) : nil,
                utxoCount: utxos
            )
        }
        // Context-aware: balance unchanged since last check
        else if let mem = memory, let lastBal = mem.lastShownBalance, lastBal == btc {
            textResponse = ResponseTemplates.balanceUnchanged(
                btcAmount: formatBTC(btc),
                fiatAmount: formatFiat(fiat),
                utxoCount: utxos
            )
        }
        // Default balance response
        else {
            textResponse = ResponseTemplates.balanceResponse(
                btcAmount: formatBTC(btc),
                fiatAmount: formatFiat(fiat),
                pendingAmount: pending > 0 ? formatBTC(pending) : nil,
                utxoCount: utxos
            )
        }

        return [
            .text(textResponse),
            .balanceCard(btc: btc, fiat: fiat, pending: pending, utxoCount: utxos),
        ]
    }

    // MARK: - Send Response

    private func generateSendResponse(
        amount: Decimal?, unit: BitcoinUnit?, address: String?,
        feeLevel: FeeLevel?, context: ConversationContext
    ) -> [ResponseType] {
        if let addr = address {
            let validator = AddressValidator()
            if !validator.isValid(addr) {
                return [.errorText(ResponseTemplates.invalidAddress())]
            }
        }

        guard let resolvedAddress = address ?? extractAddressFromState(context) else {
            return [.text(ResponseTemplates.askForAddressVaried())]
        }
        guard let rawAmount = amount else {
            return [.text(ResponseTemplates.askForAmountVaried())]
        }

        let btcAmount = normalizeAmount(rawAmount, unit: unit)
        let sendAmount: Decimal
        if btcAmount < 0 {
            guard let balance = context.walletBalance, balance > 0 else {
                return [.errorText(ResponseTemplates.networkError())]
            }
            sendAmount = balance
        } else {
            sendAmount = btcAmount
        }

        if let balance = context.walletBalance, sendAmount > balance {
            return [.errorText(ResponseTemplates.insufficientFunds(available: formatBTC(balance)))]
        }

        let feeRate = resolveFeeRate(level: feeLevel, context: context)
        let feeSats = feeRate * Decimal(Self.typicalVSize)
        let feeBTC = feeSats / Self.satoshisPerBTC
        let estimatedMinutes = resolveEstimatedTime(level: feeLevel)
        let walletBalance = context.walletBalance ?? Decimal.zero
        let remainingBalance = max(walletBalance - sendAmount - feeBTC, Decimal.zero)

        return [
            .text(ResponseTemplates.sendConfirmation()),
            .sendConfirmCard(
                toAddress: resolvedAddress,
                amount: sendAmount,
                fee: feeBTC,
                feeRate: feeRate,
                estimatedTime: estimatedMinutes,
                remainingBalance: remainingBalance
            ),
        ]
    }

    // MARK: - Receive Response

    private func generateReceiveResponse(context: ConversationContext) -> [ResponseType] {
        guard let address = context.currentReceiveAddress, !address.isEmpty else {
            return [.errorText(ResponseTemplates.walletNotReady())]
        }
        let addressType = context.addressType ?? "SegWit"
        let textResponse = ResponseTemplates.receiveAddress(address: address, type: addressType)
        return [
            .text(textResponse),
            .receiveCard(address: address, addressType: addressType),
        ]
    }

    // MARK: - History Response

    private func generateHistoryResponse(count: Int?, context: ConversationContext) -> [ResponseType] {
        guard let transactions = context.recentTransactions, !transactions.isEmpty else {
            return [.text(ResponseTemplates.noTransactions())]
        }
        let limit = count ?? 10
        let displayTransactions = Array(transactions.prefix(limit))
        return [
            .text(ResponseTemplates.historyResponse(count: displayTransactions.count)),
            .historyCard(transactions: displayTransactions),
        ]
    }

    // MARK: - Fee Response

    private func generateFeeResponse(context: ConversationContext) -> [ResponseType] {
        guard let estimates = context.currentFeeEstimates else {
            return [.errorText(ResponseTemplates.networkError())]
        }
        let slowItem = buildFeeDisplayItem(level: L10n.Fee.slow, satPerVB: estimates.slow, estimatedMinutes: 60)
        let mediumItem = buildFeeDisplayItem(level: L10n.Fee.medium, satPerVB: estimates.medium, estimatedMinutes: 20)
        let fastItem = buildFeeDisplayItem(level: L10n.Fee.fast, satPerVB: estimates.fast, estimatedMinutes: 10)

        let textResponse = ResponseTemplates.feeEstimateResponse(
            slow: "\(formatSatPerVB(estimates.slow)) \(L10n.Fee.satVb) (~\(L10n.Format.estimatedMinutes(60)))",
            medium: "\(formatSatPerVB(estimates.medium)) \(L10n.Fee.satVb) (~\(L10n.Format.estimatedMinutes(20)))",
            fast: "\(formatSatPerVB(estimates.fast)) \(L10n.Fee.satVb) (~\(L10n.Format.estimatedMinutes(10)))"
        )
        return [
            .text(textResponse),
            .feeCard(slow: slowItem, medium: mediumItem, fast: fastItem),
        ]
    }

    // MARK: - Price Response

    private func generatePriceResponse(currency: String?, context: ConversationContext) -> [ResponseType] {
        guard let price = context.btcPrice else {
            return [.text(ResponseTemplates.priceFetching())]
        }
        let curr = currency ?? context.priceCurrency ?? "USD"
        let formatted = formatFiat(price)
        return [
            .text(ResponseTemplates.priceResponse(formattedPrice: formatted, currency: curr)),
            .priceCard(btcPrice: price, currency: curr, formattedPrice: formatted),
        ]
    }

    // MARK: - Convert Response

    private func generateConvertResponse(amount: Decimal, currency: String, context: ConversationContext) -> [ResponseType] {
        guard let price = context.btcPrice, price > 0 else {
            return [.text(ResponseTemplates.priceFetching())]
        }
        let btcAmount = amount / price
        let symbol = CurrencyParser.symbol(for: currency)
        let text = ResponseTemplates.convertResponse(
            fiatAmount: "\(symbol)\(amount)",
            currency: currency,
            btcAmount: formatBTC(btcAmount)
        )
        return [.text(text)]
    }

    // MARK: - New Address Response

    private func generateNewAddressResponse(context: ConversationContext) -> [ResponseType] {
        return [.text(ResponseTemplates.newAddressGenerated())]
    }

    // MARK: - Wallet Health Response

    private func generateWalletHealthResponse(context: ConversationContext) -> [ResponseType] {
        let btc = context.walletBalance ?? Decimal.zero
        let utxos = context.utxoCount ?? 0
        let pending = context.pendingBalance ?? Decimal.zero
        let txCount = context.recentTransactions?.count ?? 0

        let text = ResponseTemplates.walletHealthResponse(
            balance: formatBTC(btc),
            utxoCount: utxos,
            pendingBalance: formatBTC(pending),
            transactionCount: txCount
        )
        return [.text(text)]
    }

    // MARK: - Export Response

    private func generateExportResponse(context: ConversationContext) -> [ResponseType] {
        return [.text(ResponseTemplates.exportHistoryResponse())]
    }

    // MARK: - UTXO Response

    private func generateUTXOResponse(context: ConversationContext) -> [ResponseType] {
        let count = context.utxoCount ?? 0
        let text = ResponseTemplates.utxoListResponse(count: count)
        return [.text(text)]
    }

    // MARK: - Bump Fee Response

    private func generateBumpFeeResponse(txid: String?, context: ConversationContext) -> [ResponseType] {
        return [.text(ResponseTemplates.bumpFeeResponse(txid: txid))]
    }

    // MARK: - Network Status Response

    private func generateNetworkStatusResponse(context: ConversationContext) -> [ResponseType] {
        let hasFees = context.currentFeeEstimates != nil
        let text = ResponseTemplates.networkStatusResponse(isConnected: hasFees)
        return [.text(text)]
    }

    // MARK: - Confirm Response

    private func generateConfirmResponse(context: ConversationContext) -> [ResponseType] {
        guard let pending = context.pendingTransaction else {
            return [.text(ResponseTemplates.nothingToConfirm())]
        }
        return [
            .text(ResponseTemplates.processingTransaction()),
            .sendConfirmCard(
                toAddress: pending.toAddress,
                amount: pending.amount,
                fee: pending.fee,
                feeRate: pending.feeRate,
                estimatedTime: pending.estimatedMinutes,
                remainingBalance: max((context.walletBalance ?? Decimal.zero) - pending.amount - pending.fee, Decimal.zero)
            ),
        ]
    }

    // MARK: - Cancel Response

    private func generateCancelResponse(context: ConversationContext) -> [ResponseType] {
        return [.text(ResponseTemplates.operationCancelledVaried())]
    }

    // MARK: - Transaction Detail Response

    private func generateTxDetailResponse(txid: String, context: ConversationContext) -> [ResponseType] {
        if let transactions = context.recentTransactions,
           let tx = transactions.first(where: { $0.txid.lowercased() == txid.lowercased() }) {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .short
            let dateString = dateFormatter.string(from: tx.date)

            let detailText = ResponseTemplates.transactionDetail(
                txid: tx.txid, type: tx.type, amount: formatBTC(tx.amount),
                address: tx.address, confirmations: tx.confirmations, date: dateString
            )
            return [.text(detailText)]
        }
        let notFoundText = "\(L10n.History.txid): \(txid)\n\n\(L10n.History.viewOnExplorer)"
        return [.text(notFoundText)]
    }

    // MARK: - Smart Greeting

    @MainActor
    private func generateGreetingResponse(memory: ConversationMemory?) -> [ResponseType] {
        guard let mem = memory else {
            return [.text(ResponseTemplates.greeting(walletName: nil))]
        }

        // Check if this is a "thanks" response based on last user message
        if let lastMsg = mem.lastUserMessage?.lowercased() {
            let thanksTriggers = ["thanks", "thank you", "thx", "ty", "appreciate", "cheers", "gracias", "شكرا"]
            if thanksTriggers.contains(where: { lastMsg.contains($0) }) {
                return [.text(ResponseTemplates.thankYouResponse())]
            }
        }

        // The welcome greeting is already shown by addGreeting().
        // Any subsequent greeting intent ("hi", "hello") gets a social response.
        return [.text(ResponseTemplates.socialPositiveResponse())]
    }

    // MARK: - Smart Fallback

    private func generateSmartFallback(context: ConversationContext, classification: ClassificationResult? = nil) -> [ResponseType] {
        // Use classification-aware fallback if available
        if let cls = classification {
            let bestGuess: WalletIntent? = cls.alternatives.first?.intent
            return [.text(ResponseTemplates.smartFallbackWithGuess(
                bestGuess: bestGuess,
                confidence: cls.confidence,
                alternatives: cls.alternatives
            ))]
        }
        return [.text(ResponseTemplates.smartFallback())]
    }

    // MARK: - Private Helpers

    private func extractAddressFromState(_ context: ConversationContext) -> String? {
        switch context.conversationState {
        case .awaitingAmount(let address): return address
        case .awaitingFeeLevel(_, let address): return address
        case .awaitingConfirmation(_, let address, _): return address
        default: return nil
        }
    }

    private func normalizeAmount(_ amount: Decimal, unit: BitcoinUnit?) -> Decimal {
        guard let unit = unit else { return amount }
        switch unit {
        case .btc: return amount
        case .sats, .satoshis: return amount / Self.satoshisPerBTC
        }
    }

    private func resolveFeeRate(level: FeeLevel?, context: ConversationContext) -> Decimal {
        guard let estimates = context.currentFeeEstimates else { return 15 }
        switch level {
        case .slow: return estimates.slow
        case .fast: return estimates.fast
        case .medium, .custom, .none: return estimates.medium
        }
    }

    private func resolveEstimatedTime(level: FeeLevel?) -> Int {
        switch level {
        case .fast: return 10
        case .medium, .custom, .none: return 20
        case .slow: return 60
        }
    }

    private func buildFeeDisplayItem(level: String, satPerVB: Decimal, estimatedMinutes: Int) -> FeeDisplayItem {
        let feeSats = satPerVB * Decimal(Self.typicalVSize)
        let feeBTC = feeSats / Self.satoshisPerBTC
        return FeeDisplayItem(level: level, satPerVB: satPerVB, estimatedMinutes: estimatedMinutes, estimatedCost: feeBTC)
    }

    private func formatBTC(_ amount: Decimal) -> String {
        let handler = NSDecimalNumberHandler(
            roundingMode: .plain, scale: 8,
            raiseOnExactness: false, raiseOnOverflow: false,
            raiseOnUnderflow: false, raiseOnDivideByZero: false
        )
        let number = NSDecimalNumber(decimal: amount)
        return number.rounding(accordingToBehavior: handler).stringValue
    }

    private func formatFiat(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "$0.00"
    }

    private func formatSatPerVB(_ rate: Decimal) -> String {
        let handler = NSDecimalNumberHandler(
            roundingMode: .plain, scale: 1,
            raiseOnExactness: false, raiseOnOverflow: false,
            raiseOnUnderflow: false, raiseOnDivideByZero: false
        )
        let number = NSDecimalNumber(decimal: rate)
        return number.rounding(accordingToBehavior: handler).stringValue
    }
}
