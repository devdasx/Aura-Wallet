import SwiftData
import Foundation

// MARK: - SwiftData Models
// Unified database schema for the Bitcoin AI Wallet.
// Conversations and messages are the primary models for chat persistence.
// Wallet data models (transactions, UTXOs, addresses) are defined here
// for future migration from Core Data.
//
// IMPORTANT: Private keys and seed phrases stay in Keychain (encrypted by
// Secure Enclave). SwiftData stores a reference ID, never raw key material.

// MARK: - Conversation
// Each conversation is a chat session (like Claude's conversations).

@Model
final class Conversation {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var isPinned: Bool

    @Relationship(deleteRule: .cascade, inverse: \PersistedMessage.conversation)
    var messages: [PersistedMessage]

    init(title: String = "New Chat") {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.updatedAt = Date()
        self.isPinned = false
        self.messages = []
    }
}

// MARK: - PersistedMessage
// A single message (user or AI) stored in SwiftData.
// Converted to/from the in-memory ChatMessage struct for the view layer.

@Model
final class PersistedMessage {
    var id: UUID
    var role: String
    var content: String
    var timestamp: Date
    var intentType: String?
    var responseData: String?

    var conversation: Conversation?

    init(role: String, content: String, intentType: String? = nil, responseData: String? = nil) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.intentType = intentType
        self.responseData = responseData
    }

    /// Whether this message is from the user.
    var isFromUser: Bool {
        role == "user"
    }
}

// MARK: - WalletAccountRecord
// Represents a wallet account. References Keychain for private keys.

@Model
final class WalletAccountRecord {
    var id: UUID
    var name: String
    var keychainRef: String
    var addressType: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \TransactionRecord.account)
    var transactions: [TransactionRecord]

    @Relationship(deleteRule: .cascade, inverse: \UTXORecord.account)
    var utxos: [UTXORecord]

    @Relationship(deleteRule: .cascade, inverse: \AddressRecord.account)
    var addresses: [AddressRecord]

    init(name: String, keychainRef: String, addressType: String = "segwit") {
        self.id = UUID()
        self.name = name
        self.keychainRef = keychainRef
        self.addressType = addressType
        self.createdAt = Date()
        self.transactions = []
        self.utxos = []
        self.addresses = []
    }
}

// MARK: - TransactionRecord

@Model
final class TransactionRecord {
    var id: UUID
    var txid: String
    var type: String
    var amount: Decimal
    var fee: Decimal
    var fromAddresses: String
    var toAddresses: String
    var confirmations: Int
    var blockHeight: Int
    var timestamp: Date
    var status: String

    var account: WalletAccountRecord?

    init(txid: String, type: String, amount: Decimal, fee: Decimal = 0) {
        self.id = UUID()
        self.txid = txid
        self.type = type
        self.amount = amount
        self.fee = fee
        self.fromAddresses = ""
        self.toAddresses = ""
        self.confirmations = 0
        self.blockHeight = 0
        self.timestamp = Date()
        self.status = "pending"
    }
}

// MARK: - UTXORecord

@Model
final class UTXORecord {
    var id: UUID
    var txid: String
    var vout: Int
    var value: Decimal
    var valueSats: Int64
    var confirmations: Int
    var address: String
    var scriptPubKey: String?
    var isSpent: Bool
    var derivationPath: String?

    var account: WalletAccountRecord?

    init(txid: String, vout: Int, value: Decimal, valueSats: Int64) {
        self.id = UUID()
        self.txid = txid
        self.vout = vout
        self.value = value
        self.valueSats = valueSats
        self.confirmations = 0
        self.address = ""
        self.isSpent = false
    }
}

// MARK: - AddressRecord

@Model
final class AddressRecord {
    var id: UUID
    var address: String
    var addressType: String
    var derivationPath: String
    var isChange: Bool
    var isUsed: Bool
    var createdAt: Date

    var account: WalletAccountRecord?

    init(address: String, addressType: String, derivationPath: String, isChange: Bool = false) {
        self.id = UUID()
        self.address = address
        self.addressType = addressType
        self.derivationPath = derivationPath
        self.isChange = isChange
        self.isUsed = false
        self.createdAt = Date()
    }
}

// MARK: - ContactRecord

@Model
final class ContactRecord {
    var id: UUID
    var name: String
    var address: String
    var notes: String?
    var createdAt: Date

    init(name: String, address: String) {
        self.id = UUID()
        self.name = name
        self.address = address
        self.createdAt = Date()
    }
}

// MARK: - AlertRecord

@Model
final class AlertRecord {
    var id: UUID
    var type: String
    var message: String
    var isRead: Bool
    var createdAt: Date

    init(type: String, message: String) {
        self.id = UUID()
        self.type = type
        self.message = message
        self.isRead = false
        self.createdAt = Date()
    }
}
