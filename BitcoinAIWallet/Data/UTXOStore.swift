// MARK: - UTXOStore.swift
// Bitcoin AI Wallet
//
// Manages the wallet's UTXO (Unspent Transaction Output) set using Core Data
// for persistence and exposes reactive state for SwiftUI bindings.
// Provides methods for querying spendable outputs, marking spent UTXOs,
// and recalculating balances from the current UTXO set.
//
// Platform: iOS 17.0+
// Frameworks: Foundation, CoreData, Combine

import Foundation
import CoreData
import Combine

// MARK: - UTXOStore

/// Manages the wallet's set of Unspent Transaction Outputs (UTXOs).
///
/// UTXOs are the fundamental unit of spendable bitcoin. This store
/// maintains a locally cached copy of the wallet's UTXO set, providing
/// fast access for balance display and transaction construction.
///
/// ## Thread Safety
/// All published properties update on the main thread. Write operations
/// are performed on background Core Data contexts and automatically
/// merged into the view context.
///
/// ## Usage
/// ```swift
/// let store = UTXOStore()
/// store.updateUTXOs(freshUTXOs)
/// let spendable = store.spendableUTXOs()
/// ```
@MainActor
final class UTXOStore: ObservableObject {

    // MARK: - Published State

    /// All UTXOs currently held by the wallet (both spent and unspent).
    @Published var utxos: [UTXOModel] = []

    /// Total balance (confirmed + unconfirmed) in BTC.
    @Published var totalBalance: Decimal = 0

    /// Balance from confirmed UTXOs only, in BTC.
    @Published var confirmedBalance: Decimal = 0

    /// Balance from unconfirmed UTXOs only, in BTC.
    @Published var unconfirmedBalance: Decimal = 0

    // MARK: - Private Properties

    /// Reference to the Core Data stack.
    private let coreData: CoreDataStack

    // MARK: - Initialization

    /// Creates a new UTXO store backed by the given Core Data stack.
    ///
    /// - Parameter coreData: The Core Data stack to use. Defaults to the shared singleton.
    init(coreData: CoreDataStack = .shared) {
        self.coreData = coreData
        loadUTXOs()
        recalculateBalance()
    }

    // MARK: - Update UTXOs

    /// Replaces the entire UTXO set with fresh data from the network.
    ///
    /// This performs a full reconciliation: existing UTXOs that are no longer
    /// in the new set are removed, new UTXOs are inserted, and existing ones
    /// are updated. Uses a background context for thread safety.
    ///
    /// - Parameter newUTXOs: The complete set of UTXOs from the API.
    func updateUTXOs(_ newUTXOs: [UTXOModel]) {
        coreData.performBackgroundTaskAndSave { [weak self] context in
            // Delete all existing UTXOs
            let deleteRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "CachedUTXO")
            let batchDelete = NSBatchDeleteRequest(fetchRequest: deleteRequest)
            _ = try? context.execute(batchDelete)

            // Insert all new UTXOs
            for utxo in newUTXOs {
                let managedObject = NSEntityDescription.insertNewObject(
                    forEntityName: "CachedUTXO",
                    into: context
                )
                Self.populate(managedObject: managedObject, from: utxo)
            }

            // Update in-memory state on the main thread
            DispatchQueue.main.async {
                self?.utxos = newUTXOs
                self?.recalculateBalance()
            }
        }

        DataLogger.info("UTXO set updated with \(newUTXOs.count) outputs.")
    }

    // MARK: - Spendable UTXOs

    /// Returns UTXOs that can be used as inputs for a new transaction.
    ///
    /// By default, only confirmed and unspent UTXOs are returned. Set
    /// `includeUnconfirmed` to `true` to also include zero-confirmation
    /// outputs (use with caution as these may be replaced by RBF).
    ///
    /// The returned array is sorted by value ascending (smallest first),
    /// which is the preferred order for coin selection algorithms that
    /// minimize change output size.
    ///
    /// - Parameter includeUnconfirmed: Whether to include unconfirmed UTXOs. Defaults to `false`.
    /// - Returns: An array of spendable `UTXOModel` sorted by value ascending.
    func spendableUTXOs(includeUnconfirmed: Bool = false) -> [UTXOModel] {
        return utxos
            .filter { utxo in
                guard !utxo.isSpent else { return false }
                if includeUnconfirmed {
                    return true
                }
                return utxo.confirmations >= 1
            }
            .sorted { $0.value < $1.value }
    }

    // MARK: - Mark as Spent

    /// Marks a specific UTXO as spent after broadcasting a transaction.
    ///
    /// This provides immediate UI feedback before the network confirms
    /// the spend. The UTXO will be fully removed on the next sync.
    ///
    /// - Parameters:
    ///   - txid: The transaction ID of the UTXO to mark as spent.
    ///   - vout: The output index of the UTXO to mark as spent.
    func markAsSpent(txid: String, vout: Int) {
        // Update in-memory state
        if let index = utxos.firstIndex(where: { $0.txid == txid && $0.vout == vout }) {
            let original = utxos[index]
            let spent = UTXOModel(
                txid: original.txid,
                vout: original.vout,
                value: original.value,
                valueSats: original.valueSats,
                confirmations: original.confirmations,
                address: original.address,
                scriptPubKey: original.scriptPubKey,
                isSpent: true,
                derivationPath: original.derivationPath
            )
            utxos[index] = spent
            recalculateBalance()
        }

        // Persist to Core Data
        coreData.performBackgroundTaskAndSave { context in
            let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "CachedUTXO")
            fetchRequest.predicate = NSPredicate(
                format: "txid == %@ AND vout == %d",
                txid,
                Int32(vout)
            )
            fetchRequest.fetchLimit = 1

            guard let object = try? context.fetch(fetchRequest).first else {
                DataLogger.warning("Cannot mark UTXO as spent: \(txid):\(vout) not found in store.")
                return
            }

            object.setValue(true, forKey: "isSpent")
        }

        DataLogger.info("Marked UTXO \(txid):\(vout) as spent.")
    }

    // MARK: - Recalculate Balance

    /// Recalculates all balance properties from the current in-memory UTXO set.
    ///
    /// This method aggregates values from unspent UTXOs only, separating
    /// confirmed and unconfirmed balances. Called automatically after any
    /// mutation to the UTXO set.
    func recalculateBalance() {
        var confirmed: Decimal = 0
        var unconfirmed: Decimal = 0

        for utxo in utxos where !utxo.isSpent {
            if utxo.confirmations >= 1 {
                confirmed += utxo.value
            } else {
                unconfirmed += utxo.value
            }
        }

        confirmedBalance = confirmed
        unconfirmedBalance = unconfirmed
        totalBalance = confirmed + unconfirmed
    }

    // MARK: - Clear All

    /// Removes all UTXOs from both memory and persistent storage.
    ///
    /// Used during wallet reset or sign-out.
    func clearAll() {
        utxos = []
        totalBalance = 0
        confirmedBalance = 0
        unconfirmedBalance = 0

        coreData.performBackgroundTaskAndSave { context in
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "CachedUTXO")
            let batchDelete = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            _ = try? context.execute(batchDelete)
        }

        DataLogger.info("UTXO store cleared.")
    }

    // MARK: - Count

    /// The number of UTXOs currently in the store.
    var count: Int {
        utxos.count
    }

    /// The number of spendable (unspent, confirmed) UTXOs.
    var spendableCount: Int {
        spendableUTXOs().count
    }

    // MARK: - Balance Formatting

    /// Total balance formatted as a BTC string with 8 decimal places.
    var formattedTotalBalance: String {
        Self.formatBTC(totalBalance)
    }

    /// Confirmed balance formatted as a BTC string with 8 decimal places.
    var formattedConfirmedBalance: String {
        Self.formatBTC(confirmedBalance)
    }

    /// Unconfirmed balance formatted as a BTC string with 8 decimal places.
    var formattedUnconfirmedBalance: String {
        Self.formatBTC(unconfirmedBalance)
    }

    /// Total balance in satoshis.
    var totalBalanceSats: Int64 {
        let satoshis = totalBalance * Decimal(100_000_000)
        return NSDecimalNumber(decimal: satoshis).int64Value
    }

    // MARK: - Private Helpers

    /// Loads UTXOs from Core Data into the in-memory array.
    private func loadUTXOs() {
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "CachedUTXO")
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(key: "confirmations", ascending: false),
            NSSortDescriptor(key: "valueSats", ascending: false)
        ]

        guard let results = try? coreData.viewContext.fetch(fetchRequest) else {
            DataLogger.warning("Failed to load UTXOs from Core Data.")
            return
        }

        utxos = results.compactMap { Self.utxoModel(from: $0) }
        DataLogger.debug("Loaded \(utxos.count) UTXOs from persistent store.")
    }

    /// Converts a Core Data managed object into a `UTXOModel` value type.
    ///
    /// - Parameter object: The managed object from the `CachedUTXO` entity.
    /// - Returns: A `UTXOModel`, or `nil` if required fields are missing.
    private static func utxoModel(from object: NSManagedObject) -> UTXOModel? {
        guard let txid = object.value(forKey: "txid") as? String,
              let address = object.value(forKey: "address") as? String else {
            return nil
        }

        let vout = Int(object.value(forKey: "vout") as? Int32 ?? 0)
        let value = object.value(forKey: "value") as? Decimal ?? Decimal.zero
        let valueSats = object.value(forKey: "valueSats") as? Int64 ?? Int64(0)
        let confirmations = Int(object.value(forKey: "confirmations") as? Int32 ?? 0)
        let scriptPubKey = object.value(forKey: "scriptPubKey") as? String
        let isSpent = object.value(forKey: "isSpent") as? Bool ?? false
        let derivationPath = object.value(forKey: "derivationPath") as? String

        return UTXOModel(
            txid: txid,
            vout: vout,
            value: value,
            valueSats: valueSats,
            confirmations: confirmations,
            address: address,
            scriptPubKey: scriptPubKey,
            isSpent: isSpent,
            derivationPath: derivationPath
        )
    }

    /// Populates a Core Data managed object with values from a `UTXOModel`.
    ///
    /// - Parameters:
    ///   - managedObject: The managed object to populate.
    ///   - utxo: The source `UTXOModel`.
    private static func populate(managedObject: NSManagedObject, from utxo: UTXOModel) {
        managedObject.setValue(utxo.txid, forKey: "txid")
        managedObject.setValue(Int32(utxo.vout), forKey: "vout")
        managedObject.setValue(utxo.value, forKey: "value")
        managedObject.setValue(utxo.valueSats, forKey: "valueSats")
        managedObject.setValue(Int32(utxo.confirmations), forKey: "confirmations")
        managedObject.setValue(utxo.address, forKey: "address")
        managedObject.setValue(utxo.scriptPubKey, forKey: "scriptPubKey")
        managedObject.setValue(utxo.isSpent, forKey: "isSpent")
        managedObject.setValue(utxo.derivationPath, forKey: "derivationPath")
    }

    /// Formats a `Decimal` as a BTC string with 8 decimal places.
    ///
    /// - Parameter value: The value to format.
    /// - Returns: A formatted string like `"0.00123456"`.
    private static func formatBTC(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 8
        formatter.maximumFractionDigits = 8
        formatter.groupingSeparator = ","
        formatter.decimalSeparator = "."
        return formatter.string(from: value as NSDecimalNumber) ?? "0.00000000"
    }
}
