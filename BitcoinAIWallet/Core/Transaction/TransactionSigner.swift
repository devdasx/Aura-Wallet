// MARK: - TransactionSigner.swift
// Bitcoin AI Wallet
//
// Signs Bitcoin transactions using the appropriate signature scheme:
//   - SegWit (P2WPKH)  -> ECDSA (RFC 6979 deterministic nonce, BIP62 low-S)
//   - Taproot (P2TR)    -> Schnorr (BIP340)
//
// Relies on:
//   - EllipticCurve.swift (Secp256k1) for curve operations
//   - ECDSASigner.swift for ECDSA signing
//   - SchnorrSigner.swift for BIP340 Schnorr signing
//   - WitnessBuilder.swift for BIP143/BIP341 sighash computation
//   - TransactionBuilder.swift for serialization and varint encoding
//   - TransactionModels.swift for UnsignedTransaction, SignedTransaction, etc.
//
// Zero external dependencies -- system frameworks only (CryptoKit for SHA256).
//
// Platform: iOS 17.0+
// Frameworks: Foundation, CryptoKit

import Foundation
import CryptoKit

// MARK: - TransactionSigner

/// Signs unsigned Bitcoin transactions using ECDSA (P2WPKH) or Schnorr (P2TR).
///
/// The signer:
/// 1. Precomputes shared hash components for BIP143 and BIP341.
/// 2. Iterates over inputs, computing the appropriate sighash and signing.
/// 3. Populates the witness stack on each input.
/// 4. Serializes the result and computes the transaction ID.
///
/// Private key memory is zeroed after use via `defer` blocks.
final class TransactionSigner {

    // MARK: - Sign

    /// Sign an unsigned transaction with the provided private keys.
    ///
    /// For each input, the appropriate sighash is computed and the matching
    /// signature scheme is applied:
    /// - P2WPKH inputs are signed with ECDSA and given a 2-item witness
    ///   `[signature || sighash_type, compressed_pubkey]`.
    /// - P2TR inputs are signed with BIP340 Schnorr and given a 1-item
    ///   witness `[schnorr_signature]` (64 bytes for SIGHASH_DEFAULT, or
    ///   65 bytes with an explicit sighash byte appended).
    ///
    /// - Parameters:
    ///   - transaction: The unsigned transaction to sign.
    ///   - privateKeys: Map from BIP-32 derivation path to 32-byte private key.
    /// - Returns: A `SignedTransaction` with the raw hex ready for broadcast.
    /// - Throws: `TransactionError.signingFailed` if a required key is missing
    ///           or if the input script type is not supported.
    static func sign(
        transaction: UnsignedTransaction,
        privateKeys: [String: Data]
    ) throws -> SignedTransaction {
        var signedInputs = transaction.inputs

        // Precompute BIP143 hash components (shared across all SegWit v0 inputs)
        let bip143Prevouts = WitnessBuilder.hashPrevouts(inputs: transaction.inputs)
        let bip143Sequence = WitnessBuilder.hashSequence(inputs: transaction.inputs)
        let bip143Outputs = WitnessBuilder.hashOutputs(outputs: transaction.outputs)

        // Precompute BIP341 hash components (shared across all Taproot inputs)
        let bip341Prevouts = WitnessBuilder.taprootHashPrevouts(inputs: transaction.inputs)
        let bip341Amounts = WitnessBuilder.taprootHashAmounts(inputs: transaction.inputs)
        let bip341ScriptPubKeys = WitnessBuilder.taprootHashScriptPubKeys(inputs: transaction.inputs)
        let bip341Sequences = WitnessBuilder.taprootHashSequences(inputs: transaction.inputs)
        let bip341Outputs = WitnessBuilder.taprootHashOutputs(outputs: transaction.outputs)

        for (index, input) in transaction.inputs.enumerated() {
            let scriptType = input.utxo.scriptType

            guard let path = input.utxo.derivationPath,
                  let privateKey = privateKeys[path] else {
                throw TransactionError.signingFailed
            }

            // Copy key data so we can zero it after use
            var keyData = privateKey

            defer {
                // Zero private key bytes from local copy
                keyData.resetBytes(in: 0..<keyData.count)
            }

            switch scriptType {
            case .p2wpkh:
                // BIP143 sighash for SegWit v0
                let sighash = WitnessBuilder.segwitSighash(
                    version: transaction.version,
                    hashPrevouts: bip143Prevouts,
                    hashSequence: bip143Sequence,
                    input: input,
                    inputIndex: index,
                    hashOutputs: bip143Outputs,
                    lockTime: transaction.lockTime,
                    sigHashType: 0x01 // SIGHASH_ALL
                )

                // Sign with ECDSA (DER-encoded signature + sighash byte)
                let signature = try ECDSASigner.sign(hash: sighash, privateKey: keyData)

                // Derive the compressed public key (33 bytes)
                let pubKey = Secp256k1.publicKey(from: keyData)

                // Verify signature before accepting it
                // Strip the trailing sighash byte for verification
                let sigForVerify = signature.dropLast()
                guard ECDSASigner.verify(hash: sighash, signature: Data(sigForVerify), publicKey: pubKey) else {
                    throw TransactionError.signingFailed
                }

                // Witness stack: [signature, pubkey]
                signedInputs[index].witness = [signature, pubKey]

            case .p2tr:
                // BIP341 sighash for Taproot key-path spend
                let sighash = WitnessBuilder.taprootSighash(
                    version: transaction.version,
                    inputs: transaction.inputs,
                    outputs: transaction.outputs,
                    inputIndex: index,
                    hashPrevouts: bip341Prevouts,
                    hashAmounts: bip341Amounts,
                    hashScriptPubKeys: bip341ScriptPubKeys,
                    hashSequences: bip341Sequences,
                    hashOutputs: bip341Outputs,
                    lockTime: transaction.lockTime,
                    sigHashType: 0x00 // SIGHASH_DEFAULT
                )

                // Sign with BIP340 Schnorr (64-byte signature)
                let signature = try SchnorrSigner.sign(hash: sighash, privateKey: keyData)

                // Verify Schnorr signature before accepting it
                let xOnlyPubKey = Secp256k1.xOnlyPublicKey(from: keyData)
                guard SchnorrSigner.verify(hash: sighash, signature: signature, publicKey: xOnlyPubKey) else {
                    throw TransactionError.signingFailed
                }

                // Witness stack: [signature] (64 bytes for SIGHASH_DEFAULT)
                signedInputs[index].witness = [signature]

            default:
                // P2PKH and P2SH signing not implemented in this module
                throw TransactionError.signingFailed
            }
        }

        // Build a new UnsignedTransaction with populated witness data for serialization
        let signedUnsignedTx = UnsignedTransaction(
            version: transaction.version,
            inputs: signedInputs,
            outputs: transaction.outputs,
            lockTime: transaction.lockTime,
            totalInputAmount: transaction.totalInputAmount,
            totalOutputAmount: transaction.totalOutputAmount,
            fee: transaction.fee,
            changeOutputIndex: transaction.changeOutputIndex
        )

        // Serialize using TransactionBuilder
        let rawTx = TransactionBuilder.serializeWitness(tx: signedUnsignedTx)
        let txid = TransactionBuilder.computeTxid(tx: signedUnsignedTx)

        // Compute weight and virtual size from the signed transaction
        let weight = signedUnsignedTx.weight
        let virtualSize = signedUnsignedTx.virtualSize

        return SignedTransaction(
            txid: txid,
            rawHex: TransactionBuilder.dataToHex(rawTx),
            virtualSize: virtualSize,
            weight: weight,
            fee: transaction.fee
        )
    }

    // MARK: - Convenience

    /// Compute the transaction ID from a raw serialized transaction.
    ///
    /// If the transaction includes SegWit witness data (marker 0x00, flag 0x01
    /// at byte offsets 4-5), the witness data is stripped before hashing.
    /// The txid is the double-SHA256 of the non-witness serialization,
    /// byte-reversed for display (Bitcoin convention).
    ///
    /// - Parameter serialized: Raw serialized transaction bytes.
    /// - Returns: 64-character hex transaction ID.
    static func computeTxid(from serialized: Data) -> String {
        // Check for SegWit marker/flag at bytes 4-5
        if serialized.count > 6 {
            let marker = serialized[serialized.startIndex + 4]
            let flag = serialized[serialized.startIndex + 5]
            if marker == 0x00 && flag == 0x01 {
                let nonWitness = stripWitnessData(serialized)
                let hash = doubleSHA256(nonWitness)
                return TransactionBuilder.dataToHex(Data(hash.reversed()))
            }
        }

        let hash = doubleSHA256(serialized)
        return TransactionBuilder.dataToHex(Data(hash.reversed()))
    }

    // MARK: - Private Helpers

    /// Strip witness data from a SegWit-serialized transaction.
    ///
    /// Parses the BIP144 format and rebuilds without the marker, flag,
    /// and per-input witness stacks, producing the legacy serialization
    /// needed for txid computation.
    private static func stripWitnessData(_ data: Data) -> Data {
        let bytes = [UInt8](data)
        guard bytes.count > 6 else { return data }

        var result = Data()

        // Version (4 bytes)
        result.append(contentsOf: bytes[0..<4])

        // Skip marker (0x00) and flag (0x01) at positions 4-5
        var offset = 6

        // Input count (varint)
        let (inputCount, inputCountSize) = readVarInt(bytes, offset: offset)
        result.append(contentsOf: bytes[offset..<offset + inputCountSize])
        offset += inputCountSize

        // Inputs: prevhash(32) + previndex(4) + scriptSig_len(var) + scriptSig + sequence(4)
        for _ in 0..<inputCount {
            let inputStart = offset
            offset += 36 // prevhash + previndex
            let (scriptSigLen, scriptSigLenSize) = readVarInt(bytes, offset: offset)
            offset += scriptSigLenSize + Int(scriptSigLen)
            offset += 4 // sequence
            result.append(contentsOf: bytes[inputStart..<offset])
        }

        // Output count (varint)
        let (outputCount, outputCountSize) = readVarInt(bytes, offset: offset)
        result.append(contentsOf: bytes[offset..<offset + outputCountSize])
        offset += outputCountSize

        // Outputs: value(8) + scriptPubKey_len(var) + scriptPubKey
        for _ in 0..<outputCount {
            let outputStart = offset
            offset += 8 // value
            let (spkLen, spkLenSize) = readVarInt(bytes, offset: offset)
            offset += spkLenSize + Int(spkLen)
            result.append(contentsOf: bytes[outputStart..<offset])
        }

        // Skip witness data for all inputs
        for _ in 0..<inputCount {
            let (witnessItemCount, witnessCountSize) = readVarInt(bytes, offset: offset)
            offset += witnessCountSize
            for _ in 0..<witnessItemCount {
                let (itemLen, itemLenSize) = readVarInt(bytes, offset: offset)
                offset += itemLenSize + Int(itemLen)
            }
        }

        // Locktime (4 bytes)
        if offset + 4 <= bytes.count {
            result.append(contentsOf: bytes[offset..<offset + 4])
        }

        return result
    }

    /// Read a Bitcoin CompactSize varint from a byte array.
    /// - Returns: Tuple of (decoded value, number of bytes consumed).
    private static func readVarInt(_ bytes: [UInt8], offset: Int) -> (UInt64, Int) {
        guard offset < bytes.count else { return (0, 0) }
        let first = bytes[offset]
        if first < 0xFD {
            return (UInt64(first), 1)
        } else if first == 0xFD {
            guard offset + 3 <= bytes.count else { return (0, 1) }
            let value = UInt64(bytes[offset + 1]) | (UInt64(bytes[offset + 2]) << 8)
            return (value, 3)
        } else if first == 0xFE {
            guard offset + 5 <= bytes.count else { return (0, 1) }
            let value = UInt64(bytes[offset + 1])
                | (UInt64(bytes[offset + 2]) << 8)
                | (UInt64(bytes[offset + 3]) << 16)
                | (UInt64(bytes[offset + 4]) << 24)
            return (value, 5)
        } else {
            guard offset + 9 <= bytes.count else { return (0, 1) }
            var value: UInt64 = 0
            for i in 0..<8 {
                value |= UInt64(bytes[offset + 1 + i]) << (i * 8)
            }
            return (value, 9)
        }
    }

    /// Double SHA-256 hash (SHA256d).
    private static func doubleSHA256(_ data: Data) -> Data {
        let first = Data(SHA256.hash(data: data))
        return Data(SHA256.hash(data: first))
    }
}
