// MARK: - TransactionModels.swift
// Bitcoin AI Wallet
//
// Core data structures for building, signing, and serializing Bitcoin transactions.
// All monetary values use UInt64 (satoshis) or Decimal (BTC) -- never Double.
//
// Platform: iOS 17.0+
// Framework: Foundation

import Foundation

// MARK: - UTXO

/// Represents an unspent transaction output available for spending.
///
/// A UTXO is the fundamental unit of value in Bitcoin. Each UTXO is uniquely
/// identified by its originating transaction ID and output index, and carries
/// a locking script that must be satisfied to spend it.
struct UTXO {
    /// 32-byte transaction hash as a 64-character hex string (display byte order).
    let txid: String

    /// Output index within the referenced transaction.
    let vout: UInt32

    /// Value in BTC. Use `Decimal` to avoid floating-point precision loss.
    let amount: Decimal

    /// Value in satoshis (1 BTC = 100,000,000 satoshis).
    let amountSats: UInt64

    /// The locking script (scriptPubKey) that must be satisfied to spend this output.
    let scriptPubKey: Data

    /// The script type of this output, used for fee estimation and signing.
    let scriptType: ScriptType

    /// The Bitcoin address that controls this UTXO.
    let address: String

    /// Number of confirmations on the blockchain.
    let confirmations: Int

    /// The BIP-32 derivation path used to derive the key controlling this UTXO.
    /// Example: "m/84'/0'/0'/0/3". May be nil for imported addresses.
    let derivationPath: String?
}

// MARK: - TransactionOutput

/// Represents a transaction output (destination).
///
/// Each output locks a specific amount of satoshis behind a scriptPubKey.
/// The recipient must provide a valid scriptSig or witness to spend it later.
struct TransactionOutput {
    /// The destination Bitcoin address.
    let address: String

    /// Value in BTC.
    let amount: Decimal

    /// Value in satoshis.
    let amountSats: UInt64

    /// The locking script for this output.
    let scriptPubKey: Data
}

// MARK: - TransactionInput

/// Represents a transaction input that references a previous output.
///
/// Inputs consume UTXOs by providing the txid and vout of the output being
/// spent, along with a scriptSig and/or witness data to satisfy the locking
/// conditions.
struct TransactionInput {
    /// Previous transaction hash in internal byte order (reversed from display).
    let previousTxid: Data // 32 bytes

    /// Output index of the previous transaction being spent.
    let previousIndex: UInt32

    /// Sequence number. 0xFFFFFFFE enables locktime; 0xFFFFFFFF disables RBF.
    let sequence: UInt32

    /// The UTXO being consumed by this input.
    let utxo: UTXO

    /// Script signature (empty for SegWit inputs; populated for legacy P2PKH).
    var scriptSig: Data

    /// Witness data stack (populated after signing for SegWit and Taproot inputs).
    var witness: [Data]
}

// MARK: - UnsignedTransaction

/// A complete unsigned transaction ready for signing.
///
/// Contains all structural information needed to serialize the transaction
/// and compute signing hashes (BIP143 for SegWit, BIP341 for Taproot).
struct UnsignedTransaction {
    /// Transaction version. Typically 2 for modern transactions.
    let version: Int32

    /// Ordered list of inputs consuming previous UTXOs.
    let inputs: [TransactionInput]

    /// Ordered list of outputs creating new UTXOs.
    let outputs: [TransactionOutput]

    /// Lock time. 0 means the transaction is immediately spendable.
    let lockTime: UInt32

    /// Total value of all inputs in satoshis.
    let totalInputAmount: UInt64

    /// Total value of all outputs in satoshis.
    let totalOutputAmount: UInt64

    /// Transaction fee in satoshis (totalInputAmount - totalOutputAmount).
    let fee: UInt64

    /// Index of the change output within `outputs`, or nil if no change.
    let changeOutputIndex: Int?

    /// Virtual size in vBytes, used for fee calculation.
    ///
    /// For SegWit transactions: vsize = ceil(weight / 4)
    /// Weight = base_size * 3 + total_size
    var virtualSize: Int {
        let w = self.weight
        return (w + 3) / 4
    }

    /// Transaction weight units (BIP141).
    ///
    /// Delegates to `TransactionBuilder.computeWeight` which serializes
    /// both the witness and non-witness forms and computes:
    /// `weight = base_size * 3 + total_size`
    var weight: Int {
        return TransactionBuilder.computeWeight(
            version: version,
            inputs: inputs,
            outputs: outputs,
            lockTime: lockTime
        )
    }

    /// Fee rate in sat/vB.
    var feeRate: Decimal {
        guard virtualSize > 0 else { return 0 }
        return Decimal(fee) / Decimal(virtualSize)
    }
}

// MARK: - SignedTransaction

/// Result of building and signing a transaction, ready for broadcast.
struct SignedTransaction {
    /// The transaction ID (double SHA-256 of non-witness serialization, reversed).
    let txid: String

    /// The fully serialized transaction as a hex string, including witness data.
    let rawHex: String

    /// Virtual size in vBytes.
    let virtualSize: Int

    /// Weight units (BIP141).
    let weight: Int

    /// Fee paid in satoshis.
    let fee: UInt64
}

// MARK: - TransactionError

/// Error types for transaction building, signing, and serialization.
enum TransactionError: Error, LocalizedError {
    /// The selected UTXOs do not provide enough value to cover the send amount plus fees.
    case insufficientFunds(required: UInt64, available: UInt64)

    /// No UTXOs were provided for the transaction.
    case noUTXOs

    /// The destination address is invalid or could not be decoded.
    case invalidAddress

    /// The send amount is invalid (zero or negative).
    case invalidAmount

    /// An output amount is below the dust limit and would be rejected by nodes.
    case dustOutput(amount: UInt64, dustLimit: UInt64)

    /// The calculated fee exceeds the send amount.
    case feeExceedsAmount

    /// Failed to encode the transaction to binary format.
    case encodingFailed

    /// A script could not be constructed from the provided data.
    case invalidScript

    /// Transaction signing failed.
    case signingFailed

    /// Transaction serialization failed.
    case serializationFailed

    var errorDescription: String? {
        switch self {
        case .insufficientFunds(let required, let available):
            return "Insufficient funds: need \(required) sats but only \(available) sats available."
        case .noUTXOs:
            return "No unspent outputs available to fund this transaction."
        case .invalidAddress:
            return "The destination address is invalid or unrecognized."
        case .invalidAmount:
            return "The send amount must be greater than zero."
        case .dustOutput(let amount, let dustLimit):
            return "Output of \(amount) sats is below the dust limit of \(dustLimit) sats."
        case .feeExceedsAmount:
            return "The transaction fee exceeds the available amount."
        case .encodingFailed:
            return "Failed to encode transaction data."
        case .invalidScript:
            return "Failed to construct a valid script."
        case .signingFailed:
            return "Failed to sign the transaction."
        case .serializationFailed:
            return "Failed to serialize the transaction."
        }
    }
}
