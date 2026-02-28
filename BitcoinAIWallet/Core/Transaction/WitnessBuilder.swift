// MARK: - WitnessBuilder.swift
// Bitcoin AI Wallet
//
// Builds witness data for SegWit (BIP141/BIP143) and Taproot (BIP341)
// transactions. Provides sighash computation for signing and witness
// stack serialization.
//
// BIP143: Defines the transaction digest algorithm for SegWit (witness v0)
//         inputs, fixing the quadratic hashing problem in legacy signing.
//
// BIP341: Defines the Schnorr signature scheme and sighash algorithm for
//         Taproot (witness v1) key-path spending.
//
// Platform: iOS 17.0+
// Frameworks: Foundation, CryptoKit

import Foundation
import CryptoKit

// MARK: - WitnessBuilder

/// Builds witness data for SegWit and Taproot transactions and computes
/// the signing hashes (sighash) per BIP143 and BIP341.
enum WitnessBuilder {

    // =========================================================================
    // MARK: - BIP143 SegWit v0 Hash Components
    // =========================================================================

    /// Hash of all input outpoints for BIP143: SHA256d(prevhash1 || previndex1 || ...)
    ///
    /// Used as a shared component across all inputs when computing BIP143 sighashes.
    /// For SIGHASH_ANYONECANPAY, this is replaced with 32 zero bytes.
    ///
    /// - Parameter inputs: Transaction inputs.
    /// - Returns: 32-byte double-SHA256 hash.
    static func hashPrevouts(inputs: [TransactionInput]) -> Data {
        var data = Data()
        for input in inputs {
            data.append(input.previousTxid)           // 32 bytes (internal byte order)
            data.append(uint32LE(input.previousIndex)) // 4 bytes LE
        }
        return doubleSHA256(data)
    }

    /// Hash of all input sequences for BIP143: SHA256d(seq1 || seq2 || ...)
    ///
    /// - Parameter inputs: Transaction inputs.
    /// - Returns: 32-byte double-SHA256 hash.
    static func hashSequence(inputs: [TransactionInput]) -> Data {
        var data = Data()
        for input in inputs {
            data.append(uint32LE(input.sequence))
        }
        return doubleSHA256(data)
    }

    /// Hash of all outputs for BIP143: SHA256d(value1 || scriptPubKey1_len || scriptPubKey1 || ...)
    ///
    /// - Parameter outputs: Transaction outputs.
    /// - Returns: 32-byte double-SHA256 hash.
    static func hashOutputs(outputs: [TransactionOutput]) -> Data {
        var data = Data()
        for output in outputs {
            data.append(uint64LE(output.amountSats))
            data.append(TransactionBuilder.encodeVarInt(UInt64(output.scriptPubKey.count)))
            data.append(output.scriptPubKey)
        }
        return doubleSHA256(data)
    }

    // =========================================================================
    // MARK: - BIP143 SegWit Sighash
    // =========================================================================

    /// Compute the BIP143 sighash for a P2WPKH input.
    ///
    /// BIP143 defines a new transaction digest algorithm for SegWit inputs
    /// that eliminates quadratic hashing and commits to the input value.
    ///
    /// The digest preimage is:
    /// ```
    ///  1. nVersion            (4 bytes LE)
    ///  2. hashPrevouts        (32 bytes) - hash of all input outpoints
    ///  3. hashSequence        (32 bytes) - hash of all input sequences
    ///  4. outpoint            (36 bytes) - this input's prevout
    ///  5. scriptCode          (var)      - P2PKH equivalent script
    ///  6. value               (8 bytes LE) - input amount in satoshis
    ///  7. nSequence           (4 bytes LE) - this input's sequence
    ///  8. hashOutputs         (32 bytes) - hash of all outputs
    ///  9. nLocktime           (4 bytes LE)
    /// 10. sighash type        (4 bytes LE)
    /// ```
    ///
    /// The result is double-SHA256 hashed to produce the 32-byte signing hash.
    ///
    /// - Parameters:
    ///   - version: Transaction version.
    ///   - hashPrevouts: Precomputed hashPrevouts (from `hashPrevouts(inputs:)`).
    ///   - hashSequence: Precomputed hashSequence (from `hashSequence(inputs:)`).
    ///   - input: The input being signed.
    ///   - inputIndex: Index of the input being signed.
    ///   - hashOutputs: Precomputed hashOutputs (from `hashOutputs(outputs:)`).
    ///   - lockTime: Transaction lock time.
    ///   - sigHashType: Sighash type (typically SIGHASH_ALL = 0x01).
    /// - Returns: The 32-byte signing hash.
    static func segwitSighash(
        version: Int32,
        hashPrevouts: Data,
        hashSequence: Data,
        input: TransactionInput,
        inputIndex: Int,
        hashOutputs: Data,
        lockTime: UInt32,
        sigHashType: UInt32
    ) -> Data {
        var preimage = Data()

        // nVersion
        preimage.append(int32LE(version))

        // hashPrevouts
        preimage.append(hashPrevouts)

        // hashSequence
        preimage.append(hashSequence)

        // outpoint (prevhash + previndex)
        preimage.append(input.previousTxid)
        preimage.append(uint32LE(input.previousIndex))

        // scriptCode for P2WPKH: OP_DUP OP_HASH160 <20-byte-pubkey-hash> OP_EQUALVERIFY OP_CHECKSIG
        // The 20-byte hash is derived from the scriptPubKey of the UTXO:
        //   P2WPKH scriptPubKey = 0x0014 <20-byte-hash>
        let scriptPubKey = input.utxo.scriptPubKey
        let pubKeyHash: Data
        if scriptPubKey.count == 22
            && scriptPubKey[scriptPubKey.startIndex] == 0x00
            && scriptPubKey[scriptPubKey.startIndex + 1] == 0x14 {
            pubKeyHash = scriptPubKey[scriptPubKey.startIndex + 2 ..< scriptPubKey.startIndex + 22]
        } else {
            // Fallback: use the full scriptPubKey (should not happen for P2WPKH)
            pubKeyHash = scriptPubKey
        }

        // scriptCode = OP_DUP(0x76) OP_HASH160(0xa9) OP_PUSH20(0x14) <hash> OP_EQUALVERIFY(0x88) OP_CHECKSIG(0xac)
        var scriptCode = Data()
        scriptCode.append(0x76) // OP_DUP
        scriptCode.append(0xa9) // OP_HASH160
        scriptCode.append(0x14) // Push 20 bytes
        scriptCode.append(pubKeyHash)
        scriptCode.append(0x88) // OP_EQUALVERIFY
        scriptCode.append(0xac) // OP_CHECKSIG

        preimage.append(TransactionBuilder.encodeVarInt(UInt64(scriptCode.count)))
        preimage.append(scriptCode)

        // value
        preimage.append(uint64LE(input.utxo.amountSats))

        // nSequence
        preimage.append(uint32LE(input.sequence))

        // hashOutputs
        preimage.append(hashOutputs)

        // nLockTime
        preimage.append(uint32LE(lockTime))

        // nHashType
        preimage.append(uint32LE(sigHashType))

        return doubleSHA256(preimage)
    }

    /// Convenience overload: Compute BIP143 sighash from a full UnsignedTransaction.
    ///
    /// This variant computes the hash components internally rather than
    /// requiring them to be precomputed.
    ///
    /// - Parameters:
    ///   - tx: The unsigned transaction.
    ///   - inputIndex: Index of the input being signed.
    ///   - prevoutScript: The scriptCode for signing.
    ///   - value: The value of the input being spent in satoshis.
    ///   - sigHashType: Sighash type (default: SIGHASH_ALL).
    /// - Returns: The 32-byte signing hash.
    static func segwitSighash(
        tx: UnsignedTransaction,
        inputIndex: Int,
        prevoutScript: Data,
        value: UInt64,
        sigHashType: UInt32 = 0x01
    ) -> Data {
        let hp = hashPrevouts(inputs: tx.inputs)
        let hs = hashSequence(inputs: tx.inputs)
        let ho = hashOutputs(outputs: tx.outputs)

        var preimage = Data()

        // nVersion
        preimage.append(int32LE(tx.version))
        preimage.append(hp)
        preimage.append(hs)

        // outpoint
        let input = tx.inputs[inputIndex]
        preimage.append(input.previousTxid)
        preimage.append(uint32LE(input.previousIndex))

        // scriptCode
        preimage.append(TransactionBuilder.encodeVarInt(UInt64(prevoutScript.count)))
        preimage.append(prevoutScript)

        // value
        preimage.append(uint64LE(value))

        // nSequence
        preimage.append(uint32LE(input.sequence))

        preimage.append(ho)

        // nLockTime
        preimage.append(uint32LE(tx.lockTime))

        // nHashType
        preimage.append(uint32LE(sigHashType))

        return doubleSHA256(preimage)
    }

    /// Build the P2WPKH scriptCode from a 20-byte pubkey hash.
    ///
    /// For P2WPKH, the scriptCode is equivalent to a P2PKH script:
    /// OP_DUP OP_HASH160 <20-byte-pubkey-hash> OP_EQUALVERIFY OP_CHECKSIG
    ///
    /// - Parameter pubKeyHash: The 20-byte HASH160 of the compressed public key.
    /// - Returns: The 25-byte scriptCode.
    static func p2wpkhScriptCode(pubKeyHash: Data) -> Data {
        return ScriptBuilder.p2pkhScriptPubKey(pubKeyHash: pubKeyHash)
    }

    /// Build a P2WPKH witness stack: [signature, compressed-pubkey]
    ///
    /// - Parameters:
    ///   - signature: DER-encoded ECDSA signature with sighash byte appended.
    ///   - publicKey: 33-byte compressed public key.
    /// - Returns: Witness stack as an array of Data items.
    static func p2wpkhWitness(signature: Data, publicKey: Data) -> [Data] {
        [signature, publicKey]
    }

    // =========================================================================
    // MARK: - BIP341 Taproot Hash Components
    // =========================================================================

    /// SHA256 of all prevouts for BIP341: SHA256(prevhash1 || previndex1 || ...)
    ///
    /// Note: BIP341 uses single SHA256, unlike BIP143 which uses double SHA256.
    ///
    /// - Parameter inputs: Transaction inputs.
    /// - Returns: 32-byte SHA256 hash.
    static func taprootHashPrevouts(inputs: [TransactionInput]) -> Data {
        var data = Data()
        for input in inputs {
            data.append(input.previousTxid)
            data.append(uint32LE(input.previousIndex))
        }
        return sha256(data)
    }

    /// SHA256 of all input amounts for BIP341: SHA256(amount1 || amount2 || ...)
    ///
    /// - Parameter inputs: Transaction inputs.
    /// - Returns: 32-byte SHA256 hash.
    static func taprootHashAmounts(inputs: [TransactionInput]) -> Data {
        var data = Data()
        for input in inputs {
            data.append(uint64LE(input.utxo.amountSats))
        }
        return sha256(data)
    }

    /// SHA256 of all input scriptPubKeys for BIP341: SHA256(spk1_len || spk1 || ...)
    ///
    /// Each scriptPubKey is prefixed with its CompactSize length.
    ///
    /// - Parameter inputs: Transaction inputs.
    /// - Returns: 32-byte SHA256 hash.
    static func taprootHashScriptPubKeys(inputs: [TransactionInput]) -> Data {
        var data = Data()
        for input in inputs {
            data.append(TransactionBuilder.encodeVarInt(UInt64(input.utxo.scriptPubKey.count)))
            data.append(input.utxo.scriptPubKey)
        }
        return sha256(data)
    }

    /// SHA256 of all input sequences for BIP341: SHA256(seq1 || seq2 || ...)
    ///
    /// - Parameter inputs: Transaction inputs.
    /// - Returns: 32-byte SHA256 hash.
    static func taprootHashSequences(inputs: [TransactionInput]) -> Data {
        var data = Data()
        for input in inputs {
            data.append(uint32LE(input.sequence))
        }
        return sha256(data)
    }

    /// SHA256 of all outputs for BIP341: SHA256(value1 || spk1_len || spk1 || ...)
    ///
    /// - Parameter outputs: Transaction outputs.
    /// - Returns: 32-byte SHA256 hash.
    static func taprootHashOutputs(outputs: [TransactionOutput]) -> Data {
        var data = Data()
        for output in outputs {
            data.append(uint64LE(output.amountSats))
            data.append(TransactionBuilder.encodeVarInt(UInt64(output.scriptPubKey.count)))
            data.append(output.scriptPubKey)
        }
        return sha256(data)
    }

    // =========================================================================
    // MARK: - BIP341 Taproot Sighash
    // =========================================================================

    /// Compute the BIP341 sighash for a Taproot key-path spend.
    ///
    /// BIP341 "epoch 0" serialization with `ext_flag = 0` (key path):
    /// ```
    /// epoch         = 0x00
    /// hash_type     (1 byte)
    /// nVersion      (4 bytes LE)
    /// nLockTime     (4 bytes LE)
    /// sha_prevouts  (32 bytes)
    /// sha_amounts   (32 bytes)
    /// sha_scriptpubkeys (32 bytes)
    /// sha_sequences (32 bytes)
    /// sha_outputs   (32 bytes)
    /// spend_type    (1 byte: ext_flag * 2 + annex_present)
    /// input_index   (4 bytes LE)
    /// ```
    /// The full preimage is then tagged-hashed with "TapSighash".
    ///
    /// - Parameters:
    ///   - version: Transaction version.
    ///   - inputs: All transaction inputs.
    ///   - outputs: All transaction outputs.
    ///   - inputIndex: Index of the input being signed.
    ///   - hashPrevouts: Precomputed SHA256 of all prevouts.
    ///   - hashAmounts: Precomputed SHA256 of all amounts.
    ///   - hashScriptPubKeys: Precomputed SHA256 of all scriptPubKeys.
    ///   - hashSequences: Precomputed SHA256 of all sequences.
    ///   - hashOutputs: Precomputed SHA256 of all outputs.
    ///   - lockTime: Transaction lock time.
    ///   - sigHashType: Taproot sighash type (0x00 = default = SIGHASH_ALL).
    /// - Returns: The 32-byte signing hash.
    static func taprootSighash(
        version: Int32,
        inputs: [TransactionInput],
        outputs: [TransactionOutput],
        inputIndex: Int,
        hashPrevouts: Data,
        hashAmounts: Data,
        hashScriptPubKeys: Data,
        hashSequences: Data,
        hashOutputs: Data,
        lockTime: UInt32,
        sigHashType: UInt8
    ) -> Data {
        var preimage = Data()

        // Epoch (0x00)
        preimage.append(0x00)

        // hash_type
        preimage.append(sigHashType)

        // nVersion
        preimage.append(int32LE(version))

        // nLockTime
        preimage.append(uint32LE(lockTime))

        // For SIGHASH_ALL (0x00 = default, or 0x01):
        // sha_prevouts, sha_amounts, sha_scriptpubkeys, sha_sequences
        if sigHashType == 0x00 || sigHashType == 0x01 {
            preimage.append(hashPrevouts)
            preimage.append(hashAmounts)
            preimage.append(hashScriptPubKeys)
            preimage.append(hashSequences)
        }

        // sha_outputs (for SIGHASH_ALL or SIGHASH_DEFAULT)
        if sigHashType == 0x00 || sigHashType == 0x01 {
            preimage.append(hashOutputs)
        }

        // spend_type = (ext_flag * 2) + annex_present
        // For key path spend: ext_flag = 0, no annex
        let spendType: UInt8 = 0x00
        preimage.append(spendType)

        // input_index
        preimage.append(uint32LE(UInt32(inputIndex)))

        // No annex, no script path data for key-path spend

        // Tagged hash with "TapSighash"
        return taggedHash(tag: "TapSighash", data: preimage)
    }

    /// Convenience overload: Compute BIP341 sighash from a full UnsignedTransaction.
    ///
    /// This variant computes the hash components internally from the prevouts array.
    ///
    /// - Parameters:
    ///   - tx: The unsigned transaction.
    ///   - inputIndex: Index of the input being signed.
    ///   - prevouts: Array of (scriptPubKey, value) for ALL inputs.
    ///   - sigHashType: Taproot sighash type (default: 0x00).
    /// - Returns: The 32-byte signing hash.
    static func taprootSighash(
        tx: UnsignedTransaction,
        inputIndex: Int,
        prevouts: [(script: Data, value: UInt64)],
        sigHashType: UInt8 = 0x00
    ) -> Data {
        let hp = taprootHashPrevouts(inputs: tx.inputs)

        // Build amounts from prevouts
        var amountsData = Data()
        for prevout in prevouts {
            amountsData.append(uint64LE(prevout.value))
        }
        let ha = sha256(amountsData)

        // Build scriptPubKeys from prevouts
        var spkData = Data()
        for prevout in prevouts {
            spkData.append(TransactionBuilder.encodeVarInt(UInt64(prevout.script.count)))
            spkData.append(prevout.script)
        }
        let hspk = sha256(spkData)

        let hseq = taprootHashSequences(inputs: tx.inputs)
        let ho = taprootHashOutputs(outputs: tx.outputs)

        return taprootSighash(
            version: tx.version,
            inputs: tx.inputs,
            outputs: tx.outputs,
            inputIndex: inputIndex,
            hashPrevouts: hp,
            hashAmounts: ha,
            hashScriptPubKeys: hspk,
            hashSequences: hseq,
            hashOutputs: ho,
            lockTime: tx.lockTime,
            sigHashType: sigHashType
        )
    }

    /// Build the witness stack for a Taproot key-path spend.
    ///
    /// For SIGHASH_DEFAULT (0x00), the signature is 64 bytes (no sighash
    /// byte appended). For other sighash types, the sighash byte is
    /// appended (65 bytes total).
    ///
    /// - Parameters:
    ///   - signature: 64-byte Schnorr signature.
    ///   - sigHashType: Sighash type (default: 0x00).
    /// - Returns: Witness stack as an array of Data items.
    static func p2trKeyPathWitness(signature: Data, sigHashType: UInt8 = 0x00) -> [Data] {
        if sigHashType == 0x00 {
            return [signature] // 64 bytes
        } else {
            var sigWithType = signature
            sigWithType.append(sigHashType)
            return [sigWithType] // 65 bytes
        }
    }

    // =========================================================================
    // MARK: - Witness Serialization
    // =========================================================================

    /// Serialize a witness stack for a single input.
    ///
    /// Format: [item_count_varint] [item_1_length_varint] [item_1] ...
    ///
    /// - Parameter witnessStack: Array of witness data items.
    /// - Returns: Serialized witness bytes.
    static func serializeWitness(_ witnessStack: [Data]) -> Data {
        var data = Data()

        // Number of stack items
        data.append(contentsOf: TransactionBuilder.encodeVarInt(UInt64(witnessStack.count)))

        // Each stack item: length + data
        for item in witnessStack {
            data.append(contentsOf: TransactionBuilder.encodeVarInt(UInt64(item.count)))
            data.append(item)
        }

        return data
    }

    // =========================================================================
    // MARK: - Hashing Utilities
    // =========================================================================

    /// Double SHA-256 hash (hash256 / SHA256d).
    ///
    /// Used extensively in Bitcoin for txids, block hashes, and merkle trees.
    ///
    /// - Parameter data: Input data.
    /// - Returns: 32-byte hash.
    static func hash256(_ data: Data) -> Data {
        return doubleSHA256(data)
    }

    /// Single SHA-256 hash.
    ///
    /// - Parameter data: Input data.
    /// - Returns: 32-byte hash.
    private static func sha256(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    /// Double SHA-256 hash.
    private static func doubleSHA256(_ data: Data) -> Data {
        sha256(sha256(data))
    }

    /// BIP340 tagged hash: SHA256(SHA256(tag) || SHA256(tag) || data)
    ///
    /// Tagged hashing provides domain separation, ensuring that hashes
    /// computed in different contexts (e.g., TapSighash vs TapLeaf) can
    /// never collide even with identical input data.
    ///
    /// - Parameters:
    ///   - tag: The domain separation tag string.
    ///   - data: The data to hash.
    /// - Returns: 32-byte tagged hash.
    static func taggedHash(tag: String, data: Data) -> Data {
        let tagData = Data(tag.utf8)
        let tagHash = Data(SHA256.hash(data: tagData))

        var hashInput = Data()
        hashInput.append(tagHash)  // SHA256(tag)
        hashInput.append(tagHash)  // SHA256(tag) (repeated)
        hashInput.append(data)     // message

        return Data(SHA256.hash(data: hashInput))
    }

    /// HASH160: RIPEMD160(SHA256(data))
    ///
    /// Used for P2PKH and P2WPKH address derivation.
    ///
    /// - Parameter data: Input data (typically a compressed public key).
    /// - Returns: 20-byte hash.
    static func hash160(_ data: Data) -> Data {
        let sha = Data(SHA256.hash(data: data))
        return ripemd160(sha)
    }

    // =========================================================================
    // MARK: - Little-Endian Serialization Helpers
    // =========================================================================

    private static func uint32LE(_ value: UInt32) -> Data {
        var v = value.littleEndian
        return Data(bytes: &v, count: 4)
    }

    private static func int32LE(_ value: Int32) -> Data {
        var v = value.littleEndian
        return Data(bytes: &v, count: 4)
    }

    private static func uint64LE(_ value: UInt64) -> Data {
        var v = value.littleEndian
        return Data(bytes: &v, count: 8)
    }

    // =========================================================================
    // MARK: - RIPEMD-160 Implementation
    // =========================================================================

    /// Pure Swift implementation of RIPEMD-160.
    ///
    /// RIPEMD-160 produces a 160-bit (20-byte) hash and is used in Bitcoin
    /// for HASH160 = RIPEMD160(SHA256(x)).
    ///
    /// - Parameter message: Input data.
    /// - Returns: 20-byte RIPEMD-160 hash.
    static func ripemd160(_ message: Data) -> Data {
        // Initial hash values
        var h0: UInt32 = 0x67452301
        var h1: UInt32 = 0xEFCDAB89
        var h2: UInt32 = 0x98BADCFE
        var h3: UInt32 = 0x10325476
        var h4: UInt32 = 0xC3D2E1F0

        // Pre-processing: pad message
        var msg = Array(message)
        let originalLength = msg.count
        let bitLength = UInt64(originalLength) * 8

        // Append bit '1' (0x80 byte)
        msg.append(0x80)

        // Pad with zeros until length is 56 mod 64
        while msg.count % 64 != 56 {
            msg.append(0x00)
        }

        // Append original length in bits as 64-bit LE
        for i in 0..<8 {
            msg.append(UInt8((bitLength >> (i * 8)) & 0xFF))
        }

        // Process each 512-bit (64-byte) block
        let blockCount = msg.count / 64
        for blockIndex in 0..<blockCount {
            let blockStart = blockIndex * 64

            // Parse block into sixteen 32-bit LE words
            var x = [UInt32](repeating: 0, count: 16)
            for i in 0..<16 {
                let offset = blockStart + i * 4
                x[i] = UInt32(msg[offset])
                    | (UInt32(msg[offset + 1]) << 8)
                    | (UInt32(msg[offset + 2]) << 16)
                    | (UInt32(msg[offset + 3]) << 24)
            }

            // Left rounds
            var al = h0, bl = h1, cl = h2, dl = h3, el = h4
            // Right rounds
            var ar = h0, br = h1, cr = h2, dr = h3, er = h4

            // Round constants
            let kl: [UInt32] = [0x00000000, 0x5A827999, 0x6ED9EBA1, 0x8F1BBCDC, 0xA953FD4E]
            let kr: [UInt32] = [0x50A28BE6, 0x5C4DD124, 0x6D703EF3, 0x7A6D76E9, 0x00000000]

            // Message word selection (left)
            let rl: [Int] = [
                0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
                7, 4, 13, 1, 10, 6, 15, 3, 12, 0, 9, 5, 2, 14, 11, 8,
                3, 10, 14, 4, 9, 15, 8, 1, 2, 7, 0, 6, 13, 11, 5, 12,
                1, 9, 11, 10, 0, 8, 12, 4, 13, 3, 7, 15, 14, 5, 6, 2,
                4, 0, 5, 9, 7, 12, 2, 10, 14, 1, 3, 8, 11, 6, 15, 13
            ]

            // Message word selection (right)
            let rr: [Int] = [
                5, 14, 7, 0, 9, 2, 11, 4, 13, 6, 15, 8, 1, 10, 3, 12,
                6, 11, 3, 7, 0, 13, 5, 10, 14, 15, 8, 12, 4, 9, 1, 2,
                15, 5, 1, 3, 7, 14, 6, 9, 11, 8, 12, 2, 10, 0, 4, 13,
                8, 6, 4, 1, 3, 11, 15, 0, 5, 12, 2, 13, 9, 7, 10, 14,
                12, 15, 10, 4, 1, 5, 8, 7, 6, 2, 13, 14, 0, 3, 9, 11
            ]

            // Rotation amounts (left)
            let sl: [Int] = [
                11, 14, 15, 12, 5, 8, 7, 9, 11, 13, 14, 15, 6, 7, 9, 8,
                7, 6, 8, 13, 11, 9, 7, 15, 7, 12, 15, 9, 11, 7, 13, 12,
                11, 13, 6, 7, 14, 9, 13, 15, 14, 8, 13, 6, 5, 12, 7, 5,
                11, 12, 14, 15, 14, 15, 9, 8, 9, 14, 5, 6, 8, 6, 5, 12,
                9, 15, 5, 11, 6, 8, 13, 12, 5, 12, 13, 14, 11, 8, 5, 6
            ]

            // Rotation amounts (right)
            let sr: [Int] = [
                8, 9, 9, 11, 13, 15, 15, 5, 7, 7, 8, 11, 14, 14, 12, 6,
                9, 13, 15, 7, 12, 8, 9, 11, 7, 7, 12, 7, 6, 15, 13, 11,
                9, 7, 15, 11, 8, 6, 6, 14, 12, 13, 5, 14, 13, 13, 7, 5,
                15, 5, 8, 11, 14, 14, 6, 14, 6, 9, 12, 9, 12, 5, 15, 8,
                8, 5, 12, 9, 12, 5, 14, 6, 8, 13, 6, 5, 15, 13, 11, 11
            ]

            for j in 0..<80 {
                let round = j / 16

                // Left round function
                var fl: UInt32
                switch round {
                case 0: fl = bl ^ cl ^ dl
                case 1: fl = (bl & cl) | (~bl & dl)
                case 2: fl = (bl | ~cl) ^ dl
                case 3: fl = (bl & dl) | (cl & ~dl)
                case 4: fl = bl ^ (cl | ~dl)
                default: fl = 0
                }

                var tl = al &+ fl &+ x[rl[j]] &+ kl[round]
                tl = rotateLeft(tl, by: sl[j]) &+ el
                al = el
                el = dl
                dl = rotateLeft(cl, by: 10)
                cl = bl
                bl = tl

                // Right round function
                var fr: UInt32
                switch round {
                case 0: fr = br ^ (cr | ~dr)
                case 1: fr = (br & dr) | (cr & ~dr)
                case 2: fr = (br | ~cr) ^ dr
                case 3: fr = (br & cr) | (~br & dr)
                case 4: fr = br ^ cr ^ dr
                default: fr = 0
                }

                var tr = ar &+ fr &+ x[rr[j]] &+ kr[round]
                tr = rotateLeft(tr, by: sr[j]) &+ er
                ar = er
                er = dr
                dr = rotateLeft(cr, by: 10)
                cr = br
                br = tr
            }

            // Final addition
            let t = h1 &+ cl &+ dr
            h1 = h2 &+ dl &+ er
            h2 = h3 &+ el &+ ar
            h3 = h4 &+ al &+ br
            h4 = h0 &+ bl &+ cr
            h0 = t
        }

        // Produce output (20 bytes, LE)
        var result = Data(count: 20)
        for (i, h) in [h0, h1, h2, h3, h4].enumerated() {
            result[i * 4] = UInt8(h & 0xFF)
            result[i * 4 + 1] = UInt8((h >> 8) & 0xFF)
            result[i * 4 + 2] = UInt8((h >> 16) & 0xFF)
            result[i * 4 + 3] = UInt8((h >> 24) & 0xFF)
        }

        return result
    }

    /// Left-rotate a 32-bit integer.
    private static func rotateLeft(_ value: UInt32, by count: Int) -> UInt32 {
        return (value << count) | (value >> (32 - count))
    }
}
