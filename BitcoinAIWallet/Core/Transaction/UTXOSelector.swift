// MARK: - UTXOSelector.swift
// Bitcoin AI Wallet
//
// UTXO selection algorithms for choosing which unspent outputs to consume
// when building a transaction. Implements three strategies:
//
// 1. Branch-and-Bound: attempts to find an exact match (no change output)
//    to improve privacy and reduce on-chain footprint.
// 2. Largest-First: greedy algorithm that picks the highest-value UTXOs,
//    reliable fallback when exact match is not possible.
// 3. Smallest-First: picks the smallest UTXOs first, useful for UTXO
//    consolidation during low-fee periods.
//
// All fee calculations use virtual bytes (vBytes) for SegWit compatibility.
//
// Platform: iOS 17.0+
// Framework: Foundation

import Foundation

// MARK: - UTXOSelector

/// Algorithms for selecting UTXOs to fund a Bitcoin transaction.
///
/// The selector considers the target amount, fee rate, change output cost,
/// and dust limits to find the optimal set of UTXOs.
struct UTXOSelector {

    // MARK: - Dust Limits

    /// Dust limit for native SegWit (P2WPKH) outputs in satoshis.
    /// An output is dust if the cost to spend it exceeds its value.
    /// For P2WPKH: 294 sats at the minimum relay fee of 3 sat/vB.
    static let dustLimitSegWit: UInt64 = 294

    /// Dust limit for legacy (P2PKH) outputs in satoshis.
    static let dustLimitLegacy: UInt64 = 546

    /// Dust limit for Taproot (P2TR) outputs in satoshis.
    static let dustLimitTaproot: UInt64 = 330

    // MARK: - Selection Strategy

    /// Strategy for selecting UTXOs to fund a transaction.
    enum SelectionStrategy {
        /// Pick the largest UTXOs first (greedy). Fast and always succeeds
        /// if sufficient funds exist.
        case largestFirst

        /// Pick the smallest UTXOs first, useful for UTXO consolidation.
        case smallestFirst

        /// Try to find a UTXO combination that exactly matches the target
        /// (avoiding a change output). Falls back to largestFirst.
        case branchAndBound
    }

    // MARK: - Selection Result

    /// The result of UTXO selection, containing the chosen UTXOs and
    /// fee/change breakdown.
    struct SelectionResult {
        /// The UTXOs selected to fund the transaction.
        let selectedUTXOs: [UTXO]

        /// Total input value in satoshis (sum of selected UTXOs).
        let totalInput: UInt64

        /// Estimated transaction fee in satoshis.
        let fee: UInt64

        /// Change amount to return to the sender in satoshis.
        /// Zero if no change output is needed.
        let changeAmount: UInt64

        /// Whether a change output will be created.
        let hasChange: Bool
    }

    // MARK: - Public API

    /// Select UTXOs to fund a transaction.
    ///
    /// - Parameters:
    ///   - utxos: Available UTXOs to select from.
    ///   - targetAmount: Amount to send in satoshis (excluding fees).
    ///   - feeRate: Fee rate in sat/vB.
    ///   - changeScriptType: Script type for the change output (affects fee estimation).
    ///   - strategy: Selection strategy to use.
    /// - Returns: A `SelectionResult` with the chosen UTXOs and fee breakdown.
    /// - Throws: `TransactionError` if selection fails.
    static func select(
        from utxos: [UTXO],
        targetAmount: UInt64,
        feeRate: Decimal,
        changeScriptType: ScriptType = .p2wpkh,
        strategy: SelectionStrategy = .branchAndBound
    ) throws -> SelectionResult {
        guard !utxos.isEmpty else {
            throw TransactionError.noUTXOs
        }

        guard targetAmount > 0 else {
            throw TransactionError.invalidAmount
        }

        switch strategy {
        case .branchAndBound:
            // Try branch-and-bound first for an exact match
            if let result = branchAndBound(
                utxos: utxos,
                target: targetAmount,
                feeRate: feeRate,
                changeType: changeScriptType
            ) {
                return result
            }
            // Fall back to largest-first
            return try largestFirst(
                utxos: utxos,
                target: targetAmount,
                feeRate: feeRate,
                changeType: changeScriptType
            )

        case .largestFirst:
            return try largestFirst(
                utxos: utxos,
                target: targetAmount,
                feeRate: feeRate,
                changeType: changeScriptType
            )

        case .smallestFirst:
            return try smallestFirst(
                utxos: utxos,
                target: targetAmount,
                feeRate: feeRate,
                changeType: changeScriptType
            )
        }
    }

    // MARK: - Branch and Bound

    /// Branch-and-bound algorithm that attempts to find a UTXO combination
    /// whose total value matches the target plus fee without needing change.
    ///
    /// This avoids creating a change output, which improves privacy and
    /// saves the cost of the extra output. The algorithm explores UTXO
    /// combinations using depth-first search with pruning.
    ///
    /// Based on Bitcoin Core's implementation (BIP-compliant coin selection).
    ///
    /// - Parameters:
    ///   - utxos: Available UTXOs.
    ///   - target: Target amount in satoshis.
    ///   - feeRate: Fee rate in sat/vB.
    ///   - changeType: Script type for change output (used to determine cost avoidance threshold).
    /// - Returns: A selection result if an exact match is found, nil otherwise.
    private static func branchAndBound(
        utxos: [UTXO],
        target: UInt64,
        feeRate: Decimal,
        changeType: ScriptType
    ) -> SelectionResult? {
        // Sort UTXOs by value descending for better pruning
        let sorted = utxos.sorted { $0.amountSats > $1.amountSats }

        // The cost of creating and spending a change output
        let changeDustLimit = dustLimit(for: changeType)
        let changeOutputSize = outputVirtualSize(for: changeType)
        let changeCost = NSDecimalNumber(decimal: feeRate * Decimal(changeOutputSize)).uint64Value

        // Maximum number of iterations to prevent excessive computation
        let maxIterations = 100_000
        var iterations = 0

        // Track the best selection found
        var bestSelection: [UTXO]?
        var bestWaste: UInt64 = UInt64.max

        // Current selection state
        var currentSelection = [Bool](repeating: false, count: sorted.count)

        func search(index: Int, currentValue: UInt64) {
            guard iterations < maxIterations else { return }
            iterations += 1

            // Calculate fee for current selection
            let selectedCount = currentSelection.filter { $0 }.count
            guard selectedCount > 0 else { return }

            let selectedUTXOs = sorted.enumerated().compactMap { (i, utxo) -> UTXO? in
                currentSelection[i] ? utxo : nil
            }

            let estimatedSize = estimateVirtualSize(
                inputCount: selectedCount,
                inputType: selectedUTXOs.first?.scriptType ?? .p2wpkh,
                outputCount: 1, // No change output for branch-and-bound
                hasChange: false,
                changeType: changeType
            )
            let fee = NSDecimalNumber(decimal: feeRate * Decimal(estimatedSize)).uint64Value

            let targetWithFee = target + fee

            if currentValue >= targetWithFee {
                // We have enough. Check if this is close enough (within change dust + cost).
                let excess = currentValue - targetWithFee
                if excess <= changeDustLimit + changeCost {
                    // This is a valid no-change selection
                    if excess < bestWaste {
                        bestWaste = excess
                        bestSelection = selectedUTXOs
                    }
                }
                // Pruning: adding more UTXOs would only increase waste
                return
            }

            // Try including/excluding remaining UTXOs
            guard index < sorted.count else { return }

            // Include current UTXO
            currentSelection[index] = true
            search(index: index + 1, currentValue: currentValue + sorted[index].amountSats)

            // Exclude current UTXO
            currentSelection[index] = false

            // Pruning: check if remaining UTXOs could possibly reach target
            let remainingValue = sorted[(index + 1)...].reduce(UInt64(0)) { $0 + $1.amountSats }
            if currentValue + remainingValue >= targetWithFee {
                search(index: index + 1, currentValue: currentValue)
            }
        }

        search(index: 0, currentValue: 0)

        guard let selection = bestSelection else {
            return nil
        }

        let totalInput = selection.reduce(UInt64(0)) { $0 + $1.amountSats }
        let estimatedSize = estimateVirtualSize(
            inputCount: selection.count,
            inputType: selection.first?.scriptType ?? .p2wpkh,
            outputCount: 1,
            hasChange: false,
            changeType: changeType
        )
        let fee = NSDecimalNumber(decimal: feeRate * Decimal(estimatedSize)).uint64Value

        return SelectionResult(
            selectedUTXOs: selection,
            totalInput: totalInput,
            fee: fee,
            changeAmount: totalInput - target - fee,
            hasChange: false
        )
    }

    // MARK: - Largest First

    /// Greedy algorithm that selects UTXOs from largest to smallest until
    /// the target amount plus fees is covered.
    ///
    /// - Parameters:
    ///   - utxos: Available UTXOs.
    ///   - target: Target amount in satoshis.
    ///   - feeRate: Fee rate in sat/vB.
    ///   - changeType: Script type for change output.
    /// - Returns: Selection result.
    /// - Throws: `TransactionError.insufficientFunds` if not enough value.
    private static func largestFirst(
        utxos: [UTXO],
        target: UInt64,
        feeRate: Decimal,
        changeType: ScriptType
    ) throws -> SelectionResult {
        let sorted = utxos.sorted { $0.amountSats > $1.amountSats }
        return try accumulateUTXOs(sorted: sorted, target: target, feeRate: feeRate, changeType: changeType)
    }

    // MARK: - Smallest First

    /// Selects UTXOs from smallest to largest, useful for consolidating
    /// many small UTXOs during low-fee periods.
    ///
    /// - Parameters:
    ///   - utxos: Available UTXOs.
    ///   - target: Target amount in satoshis.
    ///   - feeRate: Fee rate in sat/vB.
    ///   - changeType: Script type for change output.
    /// - Returns: Selection result.
    /// - Throws: `TransactionError.insufficientFunds` if not enough value.
    private static func smallestFirst(
        utxos: [UTXO],
        target: UInt64,
        feeRate: Decimal,
        changeType: ScriptType
    ) throws -> SelectionResult {
        let sorted = utxos.sorted { $0.amountSats < $1.amountSats }
        return try accumulateUTXOs(sorted: sorted, target: target, feeRate: feeRate, changeType: changeType)
    }

    // MARK: - Accumulation Core

    /// Accumulate UTXOs in the given order until the target + fee is met.
    ///
    /// Handles change output creation and dust threshold checks.
    ///
    /// - Parameters:
    ///   - sorted: UTXOs in the desired selection order.
    ///   - target: Target amount in satoshis.
    ///   - feeRate: Fee rate in sat/vB.
    ///   - changeType: Script type for the change output.
    /// - Returns: Selection result with change computation.
    /// - Throws: `TransactionError.insufficientFunds` if total UTXO value is insufficient.
    private static func accumulateUTXOs(
        sorted: [UTXO],
        target: UInt64,
        feeRate: Decimal,
        changeType: ScriptType
    ) throws -> SelectionResult {
        var selected = [UTXO]()
        var totalInput: UInt64 = 0

        for utxo in sorted {
            selected.append(utxo)
            totalInput += utxo.amountSats

            // Calculate fee without change output first
            let sizeNoChange = estimateVirtualSize(
                inputCount: selected.count,
                inputType: selected.first?.scriptType ?? .p2wpkh,
                outputCount: 1,
                hasChange: false,
                changeType: changeType
            )
            let feeNoChange = NSDecimalNumber(decimal: feeRate * Decimal(sizeNoChange)).uint64Value

            if totalInput >= target + feeNoChange {
                // We have enough. Determine if we need change.
                let excess = totalInput - target - feeNoChange

                // Calculate fee with change output
                let sizeWithChange = estimateVirtualSize(
                    inputCount: selected.count,
                    inputType: selected.first?.scriptType ?? .p2wpkh,
                    outputCount: 2,
                    hasChange: true,
                    changeType: changeType
                )
                let feeWithChange = NSDecimalNumber(decimal: feeRate * Decimal(sizeWithChange)).uint64Value

                let changeDust = dustLimit(for: changeType)

                if totalInput >= target + feeWithChange {
                    let changeAmount = totalInput - target - feeWithChange

                    if changeAmount >= changeDust {
                        // Create change output
                        return SelectionResult(
                            selectedUTXOs: selected,
                            totalInput: totalInput,
                            fee: feeWithChange,
                            changeAmount: changeAmount,
                            hasChange: true
                        )
                    }
                }

                // No change: the excess goes to miners as extra fee
                // (either change would be dust, or we can't afford the extra output)
                return SelectionResult(
                    selectedUTXOs: selected,
                    totalInput: totalInput,
                    fee: totalInput - target,
                    changeAmount: 0,
                    hasChange: false
                )
            }
        }

        // Not enough funds
        let totalAvailable = sorted.reduce(UInt64(0)) { $0 + $1.amountSats }
        throw TransactionError.insufficientFunds(required: target, available: totalAvailable)
    }

    // MARK: - Fee Estimation

    /// Estimate the virtual size of a transaction in vBytes.
    ///
    /// The virtual size accounts for the SegWit witness discount:
    /// vsize = ceil(weight / 4), where weight = base_size * 3 + total_size.
    ///
    /// Sizes used per component:
    /// - Overhead: 10 bytes (version 4 + locktime 4 + input count 1 + output count 1)
    ///   + 2 bytes for SegWit marker/flag (counted at witness weight)
    /// - P2PKH input:  148 vB (scriptSig ~107 bytes, no witness)
    /// - P2SH-P2WPKH:   91 vB (23-byte scriptSig + witness)
    /// - P2WPKH input:   68 vB (empty scriptSig + ~107 bytes witness at 1/4 weight)
    /// - P2TR input:     58 vB (empty scriptSig + 65 bytes witness at 1/4 weight)
    /// - P2PKH output:   34 vB
    /// - P2SH output:    32 vB
    /// - P2WPKH output:  31 vB
    /// - P2TR output:    43 vB
    ///
    /// - Parameters:
    ///   - inputCount: Number of inputs.
    ///   - inputType: Script type of the inputs (assumes homogeneous).
    ///   - outputCount: Number of outputs (including change).
    ///   - hasChange: Whether a change output is included.
    ///   - changeType: Script type of the change output.
    /// - Returns: Estimated virtual size in vBytes.
    static func estimateVirtualSize(
        inputCount: Int,
        inputType: ScriptType,
        outputCount: Int,
        hasChange: Bool,
        changeType: ScriptType
    ) -> Int {
        // Transaction overhead: version (4) + locktime (4) + varint counts (~2)
        var size = 10

        // SegWit marker and flag add 0.5 vB each (2 witness bytes / 4)
        let isSegWit = inputType == .p2wpkh || inputType == .p2tr || inputType == .p2sh
        if isSegWit {
            // marker + flag = 2 witness bytes, which at witness weight = 0.5 vB
            // We round up at the end, so add 1 to account for the fractional byte
            size += 1
        }

        // Inputs
        size += inputCount * inputType.estimatedInputVSize

        // Outputs (all non-change outputs assumed to be the destination type)
        // For simplicity, we use a weighted estimate:
        let destinationOutputCount = hasChange ? outputCount - 1 : outputCount
        size += destinationOutputCount * 31 // Default to P2WPKH output size

        // Change output
        if hasChange {
            size += outputVirtualSize(for: changeType)
        }

        return size
    }

    /// Virtual size of a single output for the given script type.
    ///
    /// Output size = value (8 bytes) + scriptPubKey length varint (1 byte) + scriptPubKey.
    /// - P2PKH:  8 + 1 + 25 = 34 vB
    /// - P2SH:   8 + 1 + 23 = 32 vB
    /// - P2WPKH: 8 + 1 + 22 = 31 vB
    /// - P2TR:   8 + 1 + 34 = 43 vB
    static func outputVirtualSize(for scriptType: ScriptType) -> Int {
        switch scriptType {
        case .p2pkh:  return 34
        case .p2sh:   return 32
        case .p2wpkh: return 31
        case .p2tr:   return 43
        }
    }

    // MARK: - Dust Check

    /// Check if an amount is below the dust limit for the given script type.
    ///
    /// Dust is defined as an output whose cost to spend exceeds its value.
    /// Nodes will reject transactions containing dust outputs.
    ///
    /// - Parameters:
    ///   - amount: Output amount in satoshis.
    ///   - scriptType: The script type of the output.
    /// - Returns: `true` if the amount is at or below the dust threshold.
    static func isDust(amount: UInt64, scriptType: ScriptType) -> Bool {
        return amount < dustLimit(for: scriptType)
    }

    /// Return the dust limit for a given script type.
    ///
    /// - Parameter scriptType: The output script type.
    /// - Returns: Dust limit in satoshis.
    static func dustLimit(for scriptType: ScriptType) -> UInt64 {
        switch scriptType {
        case .p2pkh:  return dustLimitLegacy
        case .p2sh:   return dustLimitLegacy
        case .p2wpkh: return dustLimitSegWit
        case .p2tr:   return dustLimitTaproot
        }
    }
}
