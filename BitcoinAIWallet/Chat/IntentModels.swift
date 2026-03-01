// MARK: - IntentModels.swift
// Bitcoin AI Wallet
//
// All intent types and associated data for the chat engine.
// These models represent the structured output of the intent parser,
// mapping natural language user input into actionable wallet operations.
//
// Expanded with 30+ intent types covering all wallet operations,
// price queries, currency conversion, wallet health, and more.
//
// Platform: iOS 17.0+
// Framework: Foundation

import Foundation

// MARK: - WalletIntent

/// Represents a parsed user intent for the Bitcoin wallet.
///
/// Each case corresponds to a discrete wallet operation that the chat engine
/// can dispatch to the appropriate handler. Associated values carry the
/// structured entities extracted from the user's natural language input.
enum WalletIntent: Equatable {

    // MARK: - Core Operations

    /// User wants to send Bitcoin.
    case send(amount: Decimal?, unit: BitcoinUnit?, address: String?, feeLevel: FeeLevel?)

    /// User wants to receive Bitcoin (show address / QR code).
    case receive

    /// User wants to check their wallet balance.
    case balance

    /// User wants to view transaction history.
    case history(count: Int?)

    /// User wants to see current network fee estimates.
    case feeEstimate

    /// User wants details about a specific transaction.
    case transactionDetail(txid: String)

    // MARK: - Price & Conversion

    /// User wants to check the current Bitcoin price.
    case price(currency: String?)

    /// User wants to convert an amount from a fiat currency to BTC.
    case convertAmount(amount: Decimal, fromCurrency: String)

    // MARK: - Address Management

    /// User wants to generate a new receive address.
    case newAddress

    // MARK: - Wallet Management

    /// User wants a wallet health check.
    case walletHealth

    /// User wants to export transaction history.
    case exportHistory

    /// User wants to list their UTXOs.
    case utxoList

    // MARK: - Advanced

    /// User wants to bump the fee on a pending transaction (RBF).
    case bumpFee(txid: String?)

    /// User wants network status information.
    case networkStatus

    // MARK: - Navigation

    /// User wants to open or modify settings.
    case settings

    /// User is asking for help or a list of commands.
    case help

    /// User wants to know about the app.
    case about

    // MARK: - Stateful Actions

    /// User is confirming a pending action (e.g., "yes", "confirm").
    case confirmAction

    /// User is cancelling a pending action (e.g., "no", "cancel").
    case cancelAction

    // MARK: - UI Control

    /// User wants to hide the balance display.
    case hideBalance

    /// User wants to show the balance display (unhide).
    case showBalance

    /// User wants to refresh/sync the wallet.
    case refreshWallet

    // MARK: - Social

    /// User is greeting the assistant.
    case greeting

    // MARK: - Fallback

    /// The parser could not determine a specific intent.
    /// - Parameter rawText: The original unmodified user input.
    case unknown(rawText: String)

    // MARK: - Equatable

    static func == (lhs: WalletIntent, rhs: WalletIntent) -> Bool {
        switch (lhs, rhs) {
        case let (.send(lA, lU, lAd, lF), .send(rA, rU, rAd, rF)):
            return lA == rA && lU == rU && lAd == rAd && lF == rF
        case (.receive, .receive): return true
        case (.balance, .balance): return true
        case let (.history(l), .history(r)): return l == r
        case (.feeEstimate, .feeEstimate): return true
        case let (.transactionDetail(l), .transactionDetail(r)): return l == r
        case let (.price(l), .price(r)): return l == r
        case let (.convertAmount(lA, lC), .convertAmount(rA, rC)): return lA == rA && lC == rC
        case (.newAddress, .newAddress): return true
        case (.walletHealth, .walletHealth): return true
        case (.exportHistory, .exportHistory): return true
        case (.utxoList, .utxoList): return true
        case let (.bumpFee(l), .bumpFee(r)): return l == r
        case (.networkStatus, .networkStatus): return true
        case (.settings, .settings): return true
        case (.help, .help): return true
        case (.about, .about): return true
        case (.confirmAction, .confirmAction): return true
        case (.cancelAction, .cancelAction): return true
        case (.hideBalance, .hideBalance): return true
        case (.showBalance, .showBalance): return true
        case (.refreshWallet, .refreshWallet): return true
        case (.greeting, .greeting): return true
        case let (.unknown(l), .unknown(r)): return l == r
        default: return false
        }
    }
}

// MARK: - FeeLevel

/// Fee priority levels for Bitcoin transactions.
enum FeeLevel: String, CaseIterable, Equatable {
    case slow
    case medium
    case fast
    case custom
}

// MARK: - BitcoinUnit

/// Bitcoin denomination units recognized by the parser.
enum BitcoinUnit: String, Equatable {
    case btc
    case sats
    case satoshis
}

// MARK: - ParsedEntity

/// A container for all entities that can be extracted from user input.
struct ParsedEntity: Equatable {
    var amount: Decimal?
    var unit: BitcoinUnit?
    var address: String?
    var txid: String?
    var count: Int?
    var feeLevel: FeeLevel?
    var currency: String?

    init(
        amount: Decimal? = nil,
        unit: BitcoinUnit? = nil,
        address: String? = nil,
        txid: String? = nil,
        count: Int? = nil,
        feeLevel: FeeLevel? = nil,
        currency: String? = nil
    ) {
        self.amount = amount
        self.unit = unit
        self.address = address
        self.txid = txid
        self.count = count
        self.feeLevel = feeLevel
        self.currency = currency
    }
}

// MARK: - TipItem

/// A single tip for the Tips & Tricks engine.
struct TipItem: Equatable, Identifiable {
    let id: String
    let icon: String
    let titleKey: String
    let bodyKey: String
    let category: TipCategory

    var title: String { localizedString(titleKey) }
    var body: String { localizedString(bodyKey) }
}

// MARK: - TipCategory

/// Categories for organizing command-discovery tips.
/// Each category maps to a set of commands the user can discover.
/// The `education` category is only shown after the user asks an educational question.
enum TipCategory: String, CaseIterable {
    case send
    case receive
    case balance
    case history
    case fee
    case settings
    case security
    case contacts
    case alerts
    case analytics
    case calculator
    case price
    case network
    case address
    case sharing
    case general
    case education
}

// MARK: - InlineActionType

/// Types of inline action buttons that appear inside AI chat bubbles.
enum InlineActionType: String, Equatable {
    case pasteAddress
    case scanQR
    case copyText
    case shareText
}

// MARK: - InlineAction

/// A tappable inline button rendered inside an AI chat bubble.
/// Used during active flows (send, receive) and hidden in history.
struct InlineAction: Equatable, Identifiable {
    let id: String
    let icon: String
    let label: String
    let type: InlineActionType
    var context: String?

    init(icon: String, label: String, type: InlineActionType, context: String? = nil) {
        self.id = UUID().uuidString
        self.icon = icon
        self.label = label
        self.type = type
        self.context = context
    }

    static func == (lhs: InlineAction, rhs: InlineAction) -> Bool {
        lhs.type == rhs.type && lhs.label == rhs.label && lhs.context == rhs.context
    }
}

// MARK: - ActionButton

/// An interactive suggestion button displayed below AI responses.
struct ActionButton: Equatable, Identifiable {
    let id: String
    let label: String
    let command: String
    let icon: String?

    init(label: String, command: String, icon: String? = nil) {
        self.id = UUID().uuidString
        self.label = label
        self.command = command
        self.icon = icon
    }

    static func == (lhs: ActionButton, rhs: ActionButton) -> Bool {
        lhs.label == rhs.label && lhs.command == rhs.command
    }
}

// MARK: - Conversation Role

/// Identifies the speaker of a conversation turn.
enum ConversationRole: String, Equatable {
    case user
    case assistant
}

// MARK: - IntentScore

/// A scored intent classification from a single signal source.
struct IntentScore: Comparable {
    let intent: WalletIntent
    let confidence: Double
    let source: String

    static func < (lhs: IntentScore, rhs: IntentScore) -> Bool {
        lhs.confidence < rhs.confidence
    }
}

// MARK: - ClassificationResult

/// The result of scoring an input across all signal sources.
struct ClassificationResult {
    let intent: WalletIntent
    let confidence: Double
    let needsClarification: Bool
    let alternatives: [IntentScore]
    let meaning: SentenceMeaning?

    init(intent: WalletIntent, confidence: Double, needsClarification: Bool, alternatives: [IntentScore], meaning: SentenceMeaning? = nil) {
        self.intent = intent
        self.confidence = confidence
        self.needsClarification = needsClarification
        self.alternatives = alternatives
        self.meaning = meaning
    }
}

// MARK: - SignalWeight

/// Weights for each classification signal source.
/// Context and entity presence always beat raw keywords.
enum SignalWeight {
    static let keyword: Double = 0.6
    static let entityPresence: Double = 0.7
    static let context: Double = 0.95
    static let reference: Double = 0.85
    static let semantic: Double = 0.5
    static let social: Double = 0.7
    static let negation: Double = 0.5
}

// MARK: - ResolvedEntity

/// An entity resolved from conversation memory references.
enum ResolvedEntity {
    case address(String)
    case amount(Decimal, BitcoinUnit)
    case intent(WalletIntent)
    case transaction(TransactionDisplayItem)
}

// MARK: - ShownData

/// Tracks what data was shown to the user in a response.
struct ShownData {
    var balance: Decimal?
    var fiatBalance: Decimal?
    var transactions: [TransactionDisplayItem]?
    var feeEstimates: (slow: Decimal, medium: Decimal, fast: Decimal)?
    var receiveAddress: String?
    var sentTransaction: (txid: String, amount: Decimal, address: String, fee: Decimal)?
}

// MARK: - ConversationTurn

/// A single turn in the conversation history stored in memory.
struct ConversationTurn {
    let role: ConversationRole
    let text: String
    let intent: WalletIntent?
    let entities: ParsedEntity
    let timestamp: Date
}

// MARK: - WalletIntent Helpers

extension WalletIntent {
    /// A human-readable name for display in clarification prompts.
    var friendlyName: String {
        switch self {
        case .balance: return "balance"
        case .send: return "sending Bitcoin"
        case .receive: return "receiving Bitcoin"
        case .history: return "transaction history"
        case .feeEstimate: return "fee estimates"
        case .price: return "Bitcoin price"
        case .convertAmount: return "currency conversion"
        case .newAddress: return "generating a new address"
        case .walletHealth: return "wallet health"
        case .exportHistory: return "exporting history"
        case .utxoList: return "UTXOs"
        case .bumpFee: return "fee bumping"
        case .networkStatus: return "network status"
        case .settings: return "settings"
        case .help: return "help"
        case .about: return "about"
        case .confirmAction: return "confirmation"
        case .cancelAction: return "cancellation"
        case .hideBalance: return "hiding balance"
        case .showBalance: return "showing balance"
        case .refreshWallet: return "wallet refresh"
        case .greeting: return "greeting"
        case .transactionDetail: return "transaction details"
        case .unknown: return "something"
        }
    }

    /// A unique key for grouping scores by intent type.
    var intentKey: String {
        switch self {
        case .send: return "send"
        case .balance: return "balance"
        case .receive: return "receive"
        case .history: return "history"
        case .feeEstimate: return "feeEstimate"
        case .price: return "price"
        case .convertAmount: return "convertAmount"
        case .newAddress: return "newAddress"
        case .walletHealth: return "walletHealth"
        case .exportHistory: return "exportHistory"
        case .utxoList: return "utxoList"
        case .bumpFee: return "bumpFee"
        case .networkStatus: return "networkStatus"
        case .settings: return "settings"
        case .help: return "help"
        case .about: return "about"
        case .confirmAction: return "confirmAction"
        case .cancelAction: return "cancelAction"
        case .hideBalance: return "hideBalance"
        case .showBalance: return "showBalance"
        case .refreshWallet: return "refreshWallet"
        case .greeting: return "greeting"
        case .transactionDetail: return "transactionDetail"
        case .unknown: return "unknown"
        }
    }
}
