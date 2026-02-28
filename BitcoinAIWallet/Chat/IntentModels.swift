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
