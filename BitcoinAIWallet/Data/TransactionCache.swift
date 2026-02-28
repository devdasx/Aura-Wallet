// MARK: - TransactionCache.swift
// Bitcoin AI Wallet
//
// Caches transaction history locally using Core Data for offline access
// and performance. Provides CRUD operations that bridge between the
// Core Data managed objects and the domain TransactionModel value type.
//
// Platform: iOS 17.0+
// Frameworks: Foundation, CoreData, Combine

import Foundation
import CoreData
import Combine

// MARK: - TransactionCache

/// Caches Bitcoin transaction history in Core Data for offline access
/// and fast UI rendering.
///
/// `TransactionCache` serves as the single source of truth for persisted
/// transaction data. It exposes a `@Published` array for SwiftUI bindings
/// and provides thread-safe write operations via Core Data background contexts.
///
/// ## Usage
/// ```swift
/// let cache = TransactionCache()
/// await cache.cacheTransactions(freshTransactions)
/// let recent = cache.getTransactions(for: "bc1q...", limit: 20)
/// ```
@MainActor
final class TransactionCache: ObservableObject {

    // MARK: - Published State

    /// The current set of cached transactions, sorted by timestamp descending.
    @Published var cachedTransactions: [TransactionModel] = []

    // MARK: - Private Properties

    /// Reference to the Core Data stack.
    private let coreData: CoreDataStack

    // MARK: - Initialization

    /// Creates a new transaction cache backed by the given Core Data stack.
    ///
    /// - Parameter coreData: The Core Data stack to use. Defaults to the shared singleton.
    init(coreData: CoreDataStack = .shared) {
        self.coreData = coreData
        loadCachedTransactions()
    }

    // MARK: - Cache Transactions

    /// Persists an array of transactions to Core Data.
    ///
    /// Existing transactions (matched by `txid`) are updated with new data;
    /// new transactions are inserted. Uses `NSBatchInsertRequest`-style
    /// upsert logic via the uniqueness constraint on `txid`.
    ///
    /// - Parameter transactions: The transactions to cache.
    func cacheTransactions(_ transactions: [TransactionModel]) async {
        guard !transactions.isEmpty else { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            coreData.performBackgroundTask { context in
                context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
                context.undoManager = nil

                for transaction in transactions {
                    // Fetch or create
                    let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "CachedTransaction")
                    fetchRequest.predicate = NSPredicate(format: "txid == %@", transaction.txid)
                    fetchRequest.fetchLimit = 1

                    let existingObject = try? context.fetch(fetchRequest).first
                    let managedObject = existingObject ?? NSEntityDescription.insertNewObject(
                        forEntityName: "CachedTransaction",
                        into: context
                    )

                    managedObject.setValue(transaction.txid, forKey: "txid")
                    managedObject.setValue(transaction.type.rawValue, forKey: "type")
                    managedObject.setValue(transaction.amount, forKey: "amount")
                    managedObject.setValue(transaction.fee, forKey: "fee")
                    managedObject.setValue(transaction.fromAddresses as NSArray, forKey: "fromAddresses")
                    managedObject.setValue(transaction.toAddresses as NSArray, forKey: "toAddresses")
                    managedObject.setValue(Int32(transaction.confirmations), forKey: "confirmations")
                    if let blockHeight = transaction.blockHeight {
                        managedObject.setValue(Int32(blockHeight), forKey: "blockHeight")
                    }
                    managedObject.setValue(transaction.timestamp, forKey: "timestamp")
                    if let size = transaction.size {
                        managedObject.setValue(Int32(size), forKey: "size")
                    }
                    if let vSize = transaction.virtualSize {
                        managedObject.setValue(Int32(vSize), forKey: "virtualSize")
                    }
                    managedObject.setValue(transaction.status.rawValue, forKey: "status")

                    // Store the first "to" address for indexed lookups
                    if let primaryAddress = transaction.toAddresses.first {
                        managedObject.setValue(primaryAddress, forKey: "address")
                    }
                }

                // Save and THEN resume the continuation so the caller
                // reads the committed data, not a stale snapshot.
                if context.hasChanges {
                    do {
                        try context.save()
                        DataLogger.debug("Transaction cache background save completed.")
                    } catch {
                        DataLogger.error("Transaction cache save failed: \(error.localizedDescription)")
                    }
                }

                continuation.resume()
            }
        }

        // Reload on main context after background save has committed
        loadCachedTransactions()
    }

    // MARK: - Get Transactions for Address

    /// Retrieves cached transactions associated with a specific Bitcoin address.
    ///
    /// Searches both `fromAddresses` and `toAddresses` transformable fields
    /// as well as the indexed `address` attribute.
    ///
    /// - Parameters:
    ///   - address: The Bitcoin address to filter by.
    ///   - limit: Maximum number of transactions to return. Defaults to 20.
    /// - Returns: An array of `TransactionModel` sorted by timestamp descending.
    func getTransactions(for address: String, limit: Int = 20) -> [TransactionModel] {
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "CachedTransaction")
        fetchRequest.predicate = NSPredicate(format: "address == %@", address)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        fetchRequest.fetchLimit = limit

        guard let results = try? coreData.viewContext.fetch(fetchRequest) else {
            return []
        }

        return results.compactMap { Self.transactionModel(from: $0) }
    }

    // MARK: - Get All Transactions

    /// Retrieves all cached transactions sorted by timestamp descending.
    ///
    /// - Parameter limit: Maximum number of transactions to return. Defaults to 50.
    /// - Returns: An array of `TransactionModel`.
    func getAllTransactions(limit: Int = 50) -> [TransactionModel] {
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "CachedTransaction")
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        fetchRequest.fetchLimit = limit

        guard let results = try? coreData.viewContext.fetch(fetchRequest) else {
            return []
        }

        return results.compactMap { Self.transactionModel(from: $0) }
    }

    // MARK: - Update Confirmations

    /// Updates the confirmation count for a specific transaction.
    ///
    /// Also updates the transaction status from `.pending` to `.confirmed`
    /// when the confirmation count reaches 1 or more.
    ///
    /// - Parameters:
    ///   - txid: The transaction ID to update.
    ///   - confirmations: The new confirmation count.
    func updateConfirmations(txid: String, confirmations: Int) {
        coreData.performBackgroundTaskAndSave { context in
            let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "CachedTransaction")
            fetchRequest.predicate = NSPredicate(format: "txid == %@", txid)
            fetchRequest.fetchLimit = 1

            guard let object = try? context.fetch(fetchRequest).first else {
                DataLogger.warning("Cannot update confirmations: transaction \(txid) not found in cache.")
                return
            }

            object.setValue(Int32(confirmations), forKey: "confirmations")

            // Update status if transitioning from pending to confirmed
            let currentStatus = object.value(forKey: "status") as? String ?? "pending"
            if currentStatus == "pending" && confirmations > 0 {
                object.setValue("confirmed", forKey: "status")
            }
        }

        // Refresh the published array
        loadCachedTransactions()
    }

    // MARK: - Exists

    /// Checks whether a transaction with the given ID exists in the cache.
    ///
    /// - Parameter txid: The transaction ID to look up.
    /// - Returns: `true` if the transaction is cached.
    func exists(txid: String) -> Bool {
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "CachedTransaction")
        fetchRequest.predicate = NSPredicate(format: "txid == %@", txid)
        fetchRequest.fetchLimit = 1

        let count = (try? coreData.viewContext.count(for: fetchRequest)) ?? 0
        return count > 0
    }

    // MARK: - Clear Cache

    /// Removes all cached transactions from the persistent store.
    ///
    /// - Throws: A Core Data error if the batch delete fails.
    func clearCache() throws {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "CachedTransaction")
        let batchDelete = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        batchDelete.resultType = .resultTypeObjectIDs

        let result = try coreData.viewContext.execute(batchDelete) as? NSBatchDeleteResult
        if let objectIDs = result?.result as? [NSManagedObjectID] {
            let changes: [AnyHashable: Any] = [NSDeletedObjectsKey: objectIDs]
            NSManagedObjectContext.mergeChanges(
                fromRemoteContextSave: changes,
                into: [coreData.viewContext]
            )
        }

        cachedTransactions = []
        DataLogger.info("Transaction cache cleared.")
    }

    // MARK: - Latest Timestamp

    /// Returns the timestamp of the most recent cached transaction, if any.
    ///
    /// Useful for incremental sync: fetch only transactions newer than this date.
    ///
    /// - Returns: The most recent transaction timestamp, or `nil` if the cache is empty.
    func latestTimestamp() -> Date? {
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "CachedTransaction")
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        fetchRequest.fetchLimit = 1
        fetchRequest.propertiesToFetch = ["timestamp"]

        guard let result = try? coreData.viewContext.fetch(fetchRequest).first else {
            return nil
        }

        return result.value(forKey: "timestamp") as? Date
    }

    // MARK: - Transaction Count

    /// The total number of transactions in the cache.
    var transactionCount: Int {
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "CachedTransaction")
        return (try? coreData.viewContext.count(for: fetchRequest)) ?? 0
    }

    // MARK: - Private Helpers

    /// Loads all cached transactions from Core Data into the published array.
    private func loadCachedTransactions() {
        cachedTransactions = getAllTransactions(limit: 200)
    }

    /// Converts a Core Data managed object into a `TransactionModel` value type.
    ///
    /// - Parameter object: The managed object from the `CachedTransaction` entity.
    /// - Returns: A `TransactionModel`, or `nil` if required fields are missing.
    private static func transactionModel(from object: NSManagedObject) -> TransactionModel? {
        guard let txid = object.value(forKey: "txid") as? String else { return nil }

        let typeString = object.value(forKey: "type") as? String ?? "received"
        let type = TransactionModel.TransactionType(rawValue: typeString) ?? .received

        let amount = object.value(forKey: "amount") as? Decimal ?? Decimal.zero
        let fee = object.value(forKey: "fee") as? Decimal ?? Decimal.zero

        let fromAddresses = object.value(forKey: "fromAddresses") as? [String] ?? []
        let toAddresses = object.value(forKey: "toAddresses") as? [String] ?? []

        let confirmations = Int(object.value(forKey: "confirmations") as? Int32 ?? 0)

        let blockHeightRaw = object.value(forKey: "blockHeight") as? Int32
        let blockHeight = blockHeightRaw.map { Int($0) }

        let timestamp = object.value(forKey: "timestamp") as? Date ?? Date()

        let sizeRaw = object.value(forKey: "size") as? Int32
        let size = sizeRaw.map { Int($0) }

        let virtualSizeRaw = object.value(forKey: "virtualSize") as? Int32
        let virtualSize = virtualSizeRaw.map { Int($0) }

        let statusString = object.value(forKey: "status") as? String ?? "pending"
        let status = TransactionModel.TransactionStatus(rawValue: statusString) ?? .pending

        return TransactionModel(
            id: txid,
            txid: txid,
            type: type,
            amount: amount,
            fee: fee,
            fromAddresses: fromAddresses,
            toAddresses: toAddresses,
            confirmations: confirmations,
            blockHeight: blockHeight,
            timestamp: timestamp,
            size: size,
            virtualSize: virtualSize,
            status: status
        )
    }
}
