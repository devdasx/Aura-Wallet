// MARK: - TransactionBuilder.swift
// Bitcoin AI Wallet
//
// Builds unsigned Bitcoin transactions from UTXOs and destination outputs.
// Handles UTXO selection, output construction, fee calculation, and
// serialization to the Bitcoin wire format.
//
// Also provides low-level serialization utilities (VarInt encoding,
// witness/non-witness serialization, weight computation) used by
// TransactionSigner and other modules.
//
// Supports P2PKH, P2SH-P2WPKH, P2WPKH, and P2TR output types.
// All serialization follows the exact Bitcoin protocol specification.
//
// Platform: iOS 17.0+
// Framework: Foundation, CryptoKit

import Foundation
import CryptoKit

// MARK: - TransactionBuilder

/// Builds unsigned Bitcoin transactions and provides serialization utilities.
///
/// High-level API:
/// - `build(...)` creates an unsigned transaction for a specific amount.
/// - `buildSendAll(...)` creates a sweep transaction (send entire balance).
///
/// Low-level API (used by TransactionSigner):
/// - `serialize(...)` produces the full SegWit serialization.
/// - `serializeNonWitness(...)` produces the legacy serialization (for txid).
/// - `computeWeight(...)` calculates BIP141 weight units.
/// - `encodeVarInt(...)` encodes CompactSize integers.
enum TransactionBuilder {

    // =========================================================================
    // MARK: - Build Standard Transaction
    // =========================================================================

    /// Build an unsigned transaction sending a specific amount.
    ///
    /// Steps:
    /// 1. Validate inputs and destination address.
    /// 2. Select UTXOs using the configured strategy.
    /// 3. Create the destination output.
    /// 4. Create a change output if needed (above dust threshold).
    /// 5. Build inputs from selected UTXOs.
    /// 6. Assemble and return the unsigned transaction.
    ///
    /// - Parameters:
    ///   - utxos: Available UTXOs to spend from.
    ///   - toAddress: Destination Bitcoin address.
    ///   - amount: Amount to send in satoshis.
    ///   - feeRate: Fee rate in sat/vB.
    ///   - changeAddress: Address for the change output.
    ///   - strategy: UTXO selection strategy (default: branchAndBound).
    /// - Returns: An unsigned transaction ready for signing.
    /// - Throws: `TransactionError` on validation or construction failure.
    static func build(
        utxos: [UTXO],
        toAddress: String,
        amount: UInt64,
        feeRate: Decimal,
        changeAddress: String,
        strategy: UTXOSelector.SelectionStrategy = .branchAndBound
    ) throws -> UnsignedTransaction {
        // Validate inputs
        guard !utxos.isEmpty else {
            throw TransactionError.noUTXOs
        }
        guard amount > 0 else {
            throw TransactionError.invalidAmount
        }

        // Validate destination address
        guard let destScriptType = ScriptType.from(address: toAddress) else {
            throw TransactionError.invalidAddress
        }

        // Validate change address has a recognized script type
        guard let changeScriptType = ScriptType.from(address: changeAddress) else {
            throw TransactionError.invalidAddress
        }

        // Check dust limit on destination
        let destDustLimit = UTXOSelector.dustLimit(for: destScriptType)
        if amount < destDustLimit {
            throw TransactionError.dustOutput(amount: amount, dustLimit: destDustLimit)
        }

        // Build destination scriptPubKey
        let destScriptPubKey = try ScriptBuilder.scriptPubKey(for: toAddress)

        // Select UTXOs
        let selection = try UTXOSelector.select(
            from: utxos,
            targetAmount: amount,
            feeRate: feeRate,
            changeScriptType: changeScriptType,
            strategy: strategy
        )

        // Build outputs
        var outputs = [TransactionOutput]()

        // Destination output
        let destOutput = TransactionOutput(
            address: toAddress,
            amount: Decimal(amount) / Decimal(100_000_000),
            amountSats: amount,
            scriptPubKey: destScriptPubKey
        )
        outputs.append(destOutput)

        // Change output (if needed and above dust)
        var changeOutputIndex: Int? = nil
        if selection.hasChange && selection.changeAmount > 0 {
            let changeScriptPubKey = try ScriptBuilder.scriptPubKey(for: changeAddress)
            let changeDustLimit = UTXOSelector.dustLimit(for: changeScriptType)

            if selection.changeAmount >= changeDustLimit {
                let changeOutput = TransactionOutput(
                    address: changeAddress,
                    amount: Decimal(selection.changeAmount) / Decimal(100_000_000),
                    amountSats: selection.changeAmount,
                    scriptPubKey: changeScriptPubKey
                )
                outputs.append(changeOutput)
                changeOutputIndex = outputs.count - 1
            }
        }

        // Build inputs from selected UTXOs
        let inputs = selection.selectedUTXOs.map { utxo -> TransactionInput in
            let prevTxid = reverseHex(utxo.txid)
            return TransactionInput(
                previousTxid: prevTxid,
                previousIndex: utxo.vout,
                sequence: 0xFFFFFFFE, // Enable locktime, allow RBF
                utxo: utxo,
                scriptSig: Data(),    // Empty for SegWit
                witness: []           // Populated during signing
            )
        }

        // Calculate totals
        let totalInputAmount = selection.totalInput
        let totalOutputAmount = outputs.reduce(UInt64(0)) { $0 + $1.amountSats }
        let fee = totalInputAmount - totalOutputAmount

        // Verify fee is reasonable:
        // 1. Fee must not exceed total input
        // 2. Fee must not exceed 50% of the send amount (safety against fee manipulation)
        guard fee <= totalInputAmount else {
            throw TransactionError.feeExceedsAmount
        }
        let maxReasonableFee = amount / 2
        if fee > maxReasonableFee && fee > 50_000 {
            // Only flag as excessive if both > 50% of amount AND > 50,000 sats (~$40)
            throw TransactionError.feeExceedsAmount
        }

        return UnsignedTransaction(
            version: 2,
            inputs: inputs,
            outputs: outputs,
            lockTime: 0,
            totalInputAmount: totalInputAmount,
            totalOutputAmount: totalOutputAmount,
            fee: fee,
            changeOutputIndex: changeOutputIndex
        )
    }

    // =========================================================================
    // MARK: - Build Send-All (Sweep) Transaction
    // =========================================================================

    /// Build a send-all (sweep) transaction that sends the entire balance
    /// minus the fee to a single destination.
    ///
    /// No change output is created. All input value minus the fee goes
    /// to the destination.
    ///
    /// - Parameters:
    ///   - utxos: All UTXOs to sweep.
    ///   - toAddress: Destination Bitcoin address.
    ///   - feeRate: Fee rate in sat/vB.
    /// - Returns: An unsigned transaction ready for signing.
    /// - Throws: `TransactionError` on failure.
    static func buildSendAll(
        utxos: [UTXO],
        toAddress: String,
        feeRate: Decimal
    ) throws -> UnsignedTransaction {
        guard !utxos.isEmpty else {
            throw TransactionError.noUTXOs
        }

        guard let destScriptType = ScriptType.from(address: toAddress) else {
            throw TransactionError.invalidAddress
        }

        // Calculate total input
        let totalInput = utxos.reduce(UInt64(0)) { $0 + $1.amountSats }

        // Estimate fee using all UTXOs
        let inputType = utxos.first?.scriptType ?? .p2wpkh
        let estimatedSize = UTXOSelector.estimateVirtualSize(
            inputCount: utxos.count,
            inputType: inputType,
            outputCount: 1,
            hasChange: false,
            changeType: .p2wpkh
        )
        let fee = NSDecimalNumber(decimal: feeRate * Decimal(estimatedSize)).uint64Value

        // Verify we have enough to cover the fee
        guard totalInput > fee else {
            throw TransactionError.feeExceedsAmount
        }

        let sendAmount = totalInput - fee

        // Check dust limit
        let dustLimit = UTXOSelector.dustLimit(for: destScriptType)
        if sendAmount < dustLimit {
            throw TransactionError.dustOutput(amount: sendAmount, dustLimit: dustLimit)
        }

        // Build destination output
        let destScriptPubKey = try ScriptBuilder.scriptPubKey(for: toAddress)
        let destOutput = TransactionOutput(
            address: toAddress,
            amount: Decimal(sendAmount) / Decimal(100_000_000),
            amountSats: sendAmount,
            scriptPubKey: destScriptPubKey
        )

        // Build inputs
        let inputs = utxos.map { utxo -> TransactionInput in
            let prevTxid = reverseHex(utxo.txid)
            return TransactionInput(
                previousTxid: prevTxid,
                previousIndex: utxo.vout,
                sequence: 0xFFFFFFFE,
                utxo: utxo,
                scriptSig: Data(),
                witness: []
            )
        }

        return UnsignedTransaction(
            version: 2,
            inputs: inputs,
            outputs: [destOutput],
            lockTime: 0,
            totalInputAmount: totalInput,
            totalOutputAmount: sendAmount,
            fee: fee,
            changeOutputIndex: nil
        )
    }

    // =========================================================================
    // MARK: - Legacy Serialization for Signing
    // =========================================================================

    /// Serialize a transaction for legacy (pre-SegWit) signing.
    ///
    /// For the input being signed, the scriptSig is replaced with the
    /// previous output's scriptPubKey. All other inputs have empty scriptSigs.
    /// The sighash type is appended as a 4-byte little-endian integer.
    ///
    /// - Parameters:
    ///   - tx: The unsigned transaction.
    ///   - inputIndex: The index of the input being signed.
    ///   - sigHashType: The signature hash type (typically SIGHASH_ALL = 0x01).
    /// - Returns: The serialized preimage for signing.
    static func serializeForSigning(tx: UnsignedTransaction, inputIndex: Int, sigHashType: UInt32) -> Data {
        var data = Data()

        // Version
        appendUInt32LE(&data, UInt32(bitPattern: tx.version))

        // Input count
        data.append(contentsOf: encodeVarInt(UInt64(tx.inputs.count)))

        // Inputs
        for (i, input) in tx.inputs.enumerated() {
            data.append(input.previousTxid)
            appendUInt32LE(&data, input.previousIndex)

            if i == inputIndex {
                let script = input.utxo.scriptPubKey
                data.append(contentsOf: encodeVarInt(UInt64(script.count)))
                data.append(script)
            } else {
                data.append(0x00)
            }

            appendUInt32LE(&data, input.sequence)
        }

        // Output count
        data.append(contentsOf: encodeVarInt(UInt64(tx.outputs.count)))

        // Outputs
        for output in tx.outputs {
            appendUInt64LE(&data, output.amountSats)
            data.append(contentsOf: encodeVarInt(UInt64(output.scriptPubKey.count)))
            data.append(output.scriptPubKey)
        }

        // Locktime
        appendUInt32LE(&data, tx.lockTime)

        // Sighash type (4 bytes LE)
        appendUInt32LE(&data, sigHashType)

        return data
    }

    // =========================================================================
    // MARK: - Full Transaction Serialization
    // =========================================================================

    /// Serialize a complete transaction with witness data (SegWit format).
    ///
    /// SegWit serialization format (BIP144):
    /// ```
    /// [version(4)] [marker(1)=0x00] [flag(1)=0x01] [input_count(var)] [inputs...]
    /// [output_count(var)] [outputs...] [witness...] [locktime(4)]
    /// ```
    ///
    /// If no inputs contain witness data, the legacy format (without marker/flag/witness)
    /// is used instead.
    ///
    /// - Parameters:
    ///   - version: Transaction version.
    ///   - inputs: Transaction inputs (with witness data populated after signing).
    ///   - outputs: Transaction outputs.
    ///   - lockTime: Transaction lock time.
    /// - Returns: Serialized transaction bytes.
    static func serialize(
        version: Int32,
        inputs: [TransactionInput],
        outputs: [TransactionOutput],
        lockTime: UInt32
    ) -> Data {
        let hasWitness = inputs.contains { !$0.witness.isEmpty }

        var data = Data()

        // Version (4 bytes LE)
        var ver = version.littleEndian
        data.append(Data(bytes: &ver, count: 4))

        if hasWitness {
            data.append(Data([0x00, 0x01])) // Marker + Flag
        }

        // Input count
        data.append(encodeVarInt(UInt64(inputs.count)))

        // Inputs
        for input in inputs {
            data.append(input.previousTxid)
            var prevIdx = input.previousIndex.littleEndian
            data.append(Data(bytes: &prevIdx, count: 4))
            data.append(encodeVarInt(UInt64(input.scriptSig.count)))
            data.append(input.scriptSig)
            var seq = input.sequence.littleEndian
            data.append(Data(bytes: &seq, count: 4))
        }

        // Output count
        data.append(encodeVarInt(UInt64(outputs.count)))

        // Outputs
        for output in outputs {
            var value = output.amountSats.littleEndian
            data.append(Data(bytes: &value, count: 8))
            data.append(encodeVarInt(UInt64(output.scriptPubKey.count)))
            data.append(output.scriptPubKey)
        }

        // Witness data
        if hasWitness {
            for input in inputs {
                if input.witness.isEmpty {
                    data.append(0x00) // Empty witness stack
                } else {
                    data.append(encodeVarInt(UInt64(input.witness.count)))
                    for item in input.witness {
                        data.append(encodeVarInt(UInt64(item.count)))
                        data.append(item)
                    }
                }
            }
        }

        // Locktime (4 bytes LE)
        var lt = lockTime.littleEndian
        data.append(Data(bytes: &lt, count: 4))

        return data
    }

    /// Convenience: serialize from an UnsignedTransaction struct.
    static func serializeWitness(tx: UnsignedTransaction) -> Data {
        return serialize(
            version: tx.version,
            inputs: tx.inputs,
            outputs: tx.outputs,
            lockTime: tx.lockTime
        )
    }

    /// Serialize a transaction without witness data (legacy format).
    ///
    /// Used for computing the transaction ID (txid), which is defined as the
    /// double-SHA256 of the non-witness serialization.
    ///
    /// - Parameters:
    ///   - version: Transaction version.
    ///   - inputs: Transaction inputs.
    ///   - outputs: Transaction outputs.
    ///   - lockTime: Transaction lock time.
    /// - Returns: Serialized transaction bytes without witness.
    static func serializeNonWitness(
        version: Int32,
        inputs: [TransactionInput],
        outputs: [TransactionOutput],
        lockTime: UInt32
    ) -> Data {
        var data = Data()

        // Version (4 bytes LE)
        var ver = version.littleEndian
        data.append(Data(bytes: &ver, count: 4))

        // Input count
        data.append(encodeVarInt(UInt64(inputs.count)))

        // Inputs (without witness)
        for input in inputs {
            data.append(input.previousTxid)
            var prevIdx = input.previousIndex.littleEndian
            data.append(Data(bytes: &prevIdx, count: 4))
            data.append(encodeVarInt(UInt64(input.scriptSig.count)))
            data.append(input.scriptSig)
            var seq = input.sequence.littleEndian
            data.append(Data(bytes: &seq, count: 4))
        }

        // Output count
        data.append(encodeVarInt(UInt64(outputs.count)))

        // Outputs
        for output in outputs {
            var value = output.amountSats.littleEndian
            data.append(Data(bytes: &value, count: 8))
            data.append(encodeVarInt(UInt64(output.scriptPubKey.count)))
            data.append(output.scriptPubKey)
        }

        // Locktime (4 bytes LE)
        var lt = lockTime.littleEndian
        data.append(Data(bytes: &lt, count: 4))

        return data
    }

    /// Convenience: serialize from an UnsignedTransaction struct without witness.
    static func serializeNoWitness(tx: UnsignedTransaction) -> Data {
        return serializeNonWitness(
            version: tx.version,
            inputs: tx.inputs,
            outputs: tx.outputs,
            lockTime: tx.lockTime
        )
    }

    // =========================================================================
    // MARK: - Weight Computation
    // =========================================================================

    /// Compute the BIP141 weight of a transaction.
    ///
    /// `weight = base_size * 3 + total_size`
    /// where `base_size` is the non-witness serialization size and
    /// `total_size` is the full serialization size (including witness).
    ///
    /// - Parameters:
    ///   - version: Transaction version.
    ///   - inputs: Transaction inputs.
    ///   - outputs: Transaction outputs.
    ///   - lockTime: Transaction lock time.
    /// - Returns: Weight in weight units.
    static func computeWeight(
        version: Int32,
        inputs: [TransactionInput],
        outputs: [TransactionOutput],
        lockTime: UInt32
    ) -> Int {
        let nonWitness = serializeNonWitness(
            version: version, inputs: inputs, outputs: outputs, lockTime: lockTime
        )
        let full = serialize(
            version: version, inputs: inputs, outputs: outputs, lockTime: lockTime
        )
        let baseSize = nonWitness.count
        let totalSize = full.count
        return baseSize * 3 + totalSize
    }

    // =========================================================================
    // MARK: - Transaction ID
    // =========================================================================

    /// Compute the transaction ID from an UnsignedTransaction.
    ///
    /// The txid is the double-SHA256 of the non-witness serialization,
    /// displayed in reversed byte order (big-endian hex).
    ///
    /// - Parameter tx: The transaction (signed or unsigned).
    /// - Returns: The 64-character hex txid string.
    static func computeTxid(tx: UnsignedTransaction) -> String {
        let serialized = serializeNoWitness(tx: tx)
        let hash = hash256(serialized)
        return Data(hash.reversed()).hexEncodedString()
    }

    // =========================================================================
    // MARK: - VarInt Encoding
    // =========================================================================

    /// Encode a variable-length integer (CompactSize) per Bitcoin protocol.
    ///
    /// Encoding rules:
    /// - 0x00-0xFC:         1 byte
    /// - 0xFD-0xFFFF:       0xFD + 2 bytes LE
    /// - 0x10000-0xFFFFFFFF: 0xFE + 4 bytes LE
    /// - 0x100000000+:      0xFF + 8 bytes LE
    ///
    /// - Parameter value: The integer to encode.
    /// - Returns: The encoded bytes.
    static func encodeVarInt(_ value: UInt64) -> Data {
        if value < 0xFD {
            return Data([UInt8(value)])
        } else if value <= 0xFFFF {
            var data = Data([0xFD])
            var v = UInt16(value).littleEndian
            data.append(Data(bytes: &v, count: 2))
            return data
        } else if value <= 0xFFFFFFFF {
            var data = Data([0xFE])
            var v = UInt32(value).littleEndian
            data.append(Data(bytes: &v, count: 4))
            return data
        } else {
            var data = Data([0xFF])
            var v = value.littleEndian
            data.append(Data(bytes: &v, count: 8))
            return data
        }
    }

    // =========================================================================
    // MARK: - Hex / Byte Order Helpers
    // =========================================================================

    /// Convert a hex string to Data with reversed byte order.
    ///
    /// Bitcoin transaction IDs are displayed in big-endian (human-readable)
    /// order but stored internally in little-endian (reversed) order.
    ///
    /// - Parameter hex: A hex string (e.g., a txid).
    /// - Returns: The bytes in reversed order (internal byte order).
    static func reverseHex(_ hex: String) -> Data {
        let bytes = hexToData(hex)
        return Data(bytes.reversed())
    }

    /// Convert a hex string to Data.
    ///
    /// - Parameter hex: An even-length hex string.
    /// - Returns: The decoded bytes.
    static func hexToData(_ hex: String) -> Data {
        let chars = Array(hex)
        var data = Data()
        data.reserveCapacity(chars.count / 2)

        var i = 0
        while i < chars.count - 1 {
            let byteString = String(chars[i]) + String(chars[i + 1])
            if let byte = UInt8(byteString, radix: 16) {
                data.append(byte)
            }
            i += 2
        }
        return data
    }

    /// Convert Data to a hex string.
    ///
    /// - Parameter data: The bytes to encode.
    /// - Returns: A lowercase hex string.
    static func dataToHex(_ data: Data) -> String {
        return data.map { String(format: "%02x", $0) }.joined()
    }

    // =========================================================================
    // MARK: - Hashing
    // =========================================================================

    /// Double SHA-256 hash (SHA256d / hash256).
    ///
    /// - Parameter data: Input data.
    /// - Returns: The 32-byte double SHA-256 hash.
    static func hash256(_ data: Data) -> Data {
        let first = SHA256.hash(data: data)
        let second = SHA256.hash(data: Data(first))
        return Data(second)
    }

    // =========================================================================
    // MARK: - Private Serialization Helpers
    // =========================================================================

    /// Append a UInt32 in little-endian byte order.
    private static func appendUInt32LE(_ data: inout Data, _ value: UInt32) {
        var val = value.littleEndian
        data.append(Data(bytes: &val, count: 4))
    }

    /// Append a UInt64 in little-endian byte order.
    private static func appendUInt64LE(_ data: inout Data, _ value: UInt64) {
        var val = value.littleEndian
        data.append(Data(bytes: &val, count: 8))
    }
}

// MARK: - Data Extensions

extension Data {
    /// Convert data to a lowercase hex string.
    func hexEncodedString() -> String {
        map { String(format: "%02x", $0) }.joined()
    }

    /// Initialize Data from a hex string.
    init?(hexString: String) {
        let chars = Array(hexString)
        guard chars.count % 2 == 0 else { return nil }
        var data = Data(capacity: chars.count / 2)
        for i in stride(from: 0, to: chars.count, by: 2) {
            let hexByte = String(chars[i]) + String(chars[i + 1])
            guard let byte = UInt8(hexByte, radix: 16) else { return nil }
            data.append(byte)
        }
        self = data
    }
}
