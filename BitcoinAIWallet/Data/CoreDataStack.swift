// MARK: - CoreDataStack.swift
// Bitcoin AI Wallet
//
// Core Data persistence setup and management.
// Uses a fully programmatic NSManagedObjectModel so that no .xcdatamodeld
// file is required. Defines three entities: CachedTransaction, CachedUTXO,
// and WalletInfo, covering all persistent storage needs for the wallet.
//
// Platform: iOS 17.0+
// Frameworks: Foundation, CoreData, os

import Foundation
import CoreData
import os

// MARK: - DataLogger

/// Lightweight logger wrapping Apple's unified logging system.
/// Provides a consistent interface for the data persistence layer.
/// Named DataLogger to avoid shadowing Apple's os.DataLogger.
enum DataLogger {

    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.bitcoinai.wallet"

    private static let osLog = os.Logger(subsystem: subsystem, category: "DataPersistence")

    /// Log an informational message.
    static func info(_ message: String) {
        osLog.info("\(message, privacy: .private)")
    }

    /// Log a debug-level message.
    static func debug(_ message: String) {
        osLog.debug("\(message, privacy: .private)")
    }

    /// Log a warning.
    static func warning(_ message: String) {
        osLog.warning("\(message, privacy: .private)")
    }

    /// Log an error.
    static func error(_ message: String) {
        osLog.error("\(message, privacy: .private)")
    }
}

// MARK: - CoreDataStack

/// Central Core Data persistence controller for the Bitcoin AI Wallet.
///
/// `CoreDataStack` creates and manages an `NSPersistentContainer` backed
/// by a fully programmatic `NSManagedObjectModel`. This eliminates the
/// need for a `.xcdatamodeld` file and keeps the data schema versioned
/// alongside the source code.
///
/// ## Entities
/// - **CachedTransaction** -- locally cached transaction history
/// - **CachedUTXO** -- locally cached unspent transaction outputs
/// - **WalletInfo** -- aggregate wallet metadata (balances, indices)
///
/// ## Thread Safety
/// - Read from `viewContext` on the main thread.
/// - Write using `performBackgroundTask(_:)` which provides a
///   private-queue context that automatically merges into `viewContext`.
final class CoreDataStack {

    // MARK: - Singleton

    /// Shared instance used throughout the application.
    static let shared = CoreDataStack()

    // MARK: - Properties

    /// The persistent container managing the Core Data stack.
    let container: NSPersistentContainer

    /// Main-thread managed object context for UI reads.
    var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    // MARK: - Initialization

    private init() {
        container = NSPersistentContainer(
            name: "WalletDataModel",
            managedObjectModel: Self.createModel()
        )

        // Configure the persistent store description
        if let description = container.persistentStoreDescriptions.first {
            // Enable lightweight migration
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
            // Enable persistent history tracking for background sync
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            // Encrypt the SQLite file at rest; only accessible while the device is unlocked
            description.setOption(FileProtectionType.complete as NSObject, forKey: NSPersistentStoreFileProtectionKey)
        }

        container.loadPersistentStores { [weak container] description, error in
            if let error = error {
                DataLogger.error("Core Data failed to load: \(error.localizedDescription)")

                // Schema mismatch or corruption: delete the store and retry.
                // All data in CoreData is cache-only (re-fetchable from the network),
                // so this is safe. Keychain data (seed, passcode) is unaffected.
                if let storeURL = description.url {
                    DataLogger.warning("Attempting to delete and recreate the persistent store.")
                    Self.destroyStore(at: storeURL)
                    container?.loadPersistentStores { retryDescription, retryError in
                        if let retryError = retryError {
                            DataLogger.error("Core Data retry also failed: \(retryError.localizedDescription)")
                        } else {
                            DataLogger.info("Core Data store recreated: \(retryDescription.url?.lastPathComponent ?? "unknown")")
                        }
                    }
                }
            } else {
                DataLogger.info("Core Data store loaded: \(description.url?.lastPathComponent ?? "unknown")")
            }
        }

        // Automatically merge background changes into the view context
        container.viewContext.automaticallyMergesChangesFromParent = true

        // Object-level merge: in-memory changes trump persisted values
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        // Avoid unnecessary undo tracking on the view context
        container.viewContext.undoManager = nil
    }

    // MARK: - Model Definition

    /// Creates the `NSManagedObjectModel` programmatically.
    ///
    /// This replaces the traditional `.xcdatamodeld` file. All entities,
    /// attributes, and relationships are defined in code, making the
    /// schema easy to review in pull requests and version alongside
    /// the rest of the source.
    ///
    /// - Returns: A fully configured managed object model.
    private static func createModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        // ----- CachedTransaction Entity -----
        let transactionEntity = NSEntityDescription()
        transactionEntity.name = "CachedTransaction"
        transactionEntity.managedObjectClassName = "CachedTransaction"

        let txTxid = NSAttributeDescription()
        txTxid.name = "txid"
        txTxid.attributeType = .stringAttributeType
        txTxid.isOptional = false

        let txType = NSAttributeDescription()
        txType.name = "type"
        txType.attributeType = .stringAttributeType
        txType.isOptional = false
        txType.defaultValue = "received"

        let txAmount = NSAttributeDescription()
        txAmount.name = "amount"
        txAmount.attributeType = .decimalAttributeType
        txAmount.isOptional = false
        txAmount.defaultValue = Decimal.zero

        let txFee = NSAttributeDescription()
        txFee.name = "fee"
        txFee.attributeType = .decimalAttributeType
        txFee.isOptional = false
        txFee.defaultValue = Decimal.zero

        let txFromAddresses = NSAttributeDescription()
        txFromAddresses.name = "fromAddresses"
        txFromAddresses.attributeType = .transformableAttributeType
        txFromAddresses.valueTransformerName = NSValueTransformerName.secureUnarchiveFromDataTransformerName.rawValue
        txFromAddresses.isOptional = true

        let txToAddresses = NSAttributeDescription()
        txToAddresses.name = "toAddresses"
        txToAddresses.attributeType = .transformableAttributeType
        txToAddresses.valueTransformerName = NSValueTransformerName.secureUnarchiveFromDataTransformerName.rawValue
        txToAddresses.isOptional = true

        let txConfirmations = NSAttributeDescription()
        txConfirmations.name = "confirmations"
        txConfirmations.attributeType = .integer32AttributeType
        txConfirmations.isOptional = false
        txConfirmations.defaultValue = 0

        let txBlockHeight = NSAttributeDescription()
        txBlockHeight.name = "blockHeight"
        txBlockHeight.attributeType = .integer32AttributeType
        txBlockHeight.isOptional = true

        let txTimestamp = NSAttributeDescription()
        txTimestamp.name = "timestamp"
        txTimestamp.attributeType = .dateAttributeType
        txTimestamp.isOptional = false
        txTimestamp.defaultValue = Date()

        let txSize = NSAttributeDescription()
        txSize.name = "size"
        txSize.attributeType = .integer32AttributeType
        txSize.isOptional = true

        let txVirtualSize = NSAttributeDescription()
        txVirtualSize.name = "virtualSize"
        txVirtualSize.attributeType = .integer32AttributeType
        txVirtualSize.isOptional = true

        let txStatus = NSAttributeDescription()
        txStatus.name = "status"
        txStatus.attributeType = .stringAttributeType
        txStatus.isOptional = false
        txStatus.defaultValue = "pending"

        let txAddress = NSAttributeDescription()
        txAddress.name = "address"
        txAddress.attributeType = .stringAttributeType
        txAddress.isOptional = true

        transactionEntity.properties = [
            txTxid, txType, txAmount, txFee, txFromAddresses, txToAddresses,
            txConfirmations, txBlockHeight, txTimestamp, txSize, txVirtualSize,
            txStatus, txAddress
        ]

        // Uniqueness constraint on txid
        transactionEntity.uniquenessConstraints = [[txTxid]]

        // ----- CachedUTXO Entity -----
        let utxoEntity = NSEntityDescription()
        utxoEntity.name = "CachedUTXO"
        utxoEntity.managedObjectClassName = "CachedUTXO"

        let utxoTxid = NSAttributeDescription()
        utxoTxid.name = "txid"
        utxoTxid.attributeType = .stringAttributeType
        utxoTxid.isOptional = false

        let utxoVout = NSAttributeDescription()
        utxoVout.name = "vout"
        utxoVout.attributeType = .integer32AttributeType
        utxoVout.isOptional = false
        utxoVout.defaultValue = 0

        let utxoValue = NSAttributeDescription()
        utxoValue.name = "value"
        utxoValue.attributeType = .decimalAttributeType
        utxoValue.isOptional = false
        utxoValue.defaultValue = Decimal.zero

        let utxoValueSats = NSAttributeDescription()
        utxoValueSats.name = "valueSats"
        utxoValueSats.attributeType = .integer64AttributeType
        utxoValueSats.isOptional = false
        utxoValueSats.defaultValue = Int64(0)

        let utxoConfirmations = NSAttributeDescription()
        utxoConfirmations.name = "confirmations"
        utxoConfirmations.attributeType = .integer32AttributeType
        utxoConfirmations.isOptional = false
        utxoConfirmations.defaultValue = 0

        let utxoAddress = NSAttributeDescription()
        utxoAddress.name = "address"
        utxoAddress.attributeType = .stringAttributeType
        utxoAddress.isOptional = false

        let utxoScriptPubKey = NSAttributeDescription()
        utxoScriptPubKey.name = "scriptPubKey"
        utxoScriptPubKey.attributeType = .stringAttributeType
        utxoScriptPubKey.isOptional = true

        let utxoIsSpent = NSAttributeDescription()
        utxoIsSpent.name = "isSpent"
        utxoIsSpent.attributeType = .booleanAttributeType
        utxoIsSpent.isOptional = false
        utxoIsSpent.defaultValue = false

        let utxoDerivationPath = NSAttributeDescription()
        utxoDerivationPath.name = "derivationPath"
        utxoDerivationPath.attributeType = .stringAttributeType
        utxoDerivationPath.isOptional = true

        utxoEntity.properties = [
            utxoTxid, utxoVout, utxoValue, utxoValueSats, utxoConfirmations,
            utxoAddress, utxoScriptPubKey, utxoIsSpent, utxoDerivationPath
        ]

        // Composite uniqueness on (txid, vout)
        utxoEntity.uniquenessConstraints = [[utxoTxid, utxoVout]]

        // ----- WalletInfo Entity -----
        let walletEntity = NSEntityDescription()
        walletEntity.name = "WalletInfo"
        walletEntity.managedObjectClassName = "WalletInfo"

        let walletId = NSAttributeDescription()
        walletId.name = "id"
        walletId.attributeType = .UUIDAttributeType
        walletId.isOptional = false

        let walletName = NSAttributeDescription()
        walletName.name = "name"
        walletName.attributeType = .stringAttributeType
        walletName.isOptional = false
        walletName.defaultValue = "Main Wallet"

        let walletTotalBalance = NSAttributeDescription()
        walletTotalBalance.name = "totalBalance"
        walletTotalBalance.attributeType = .decimalAttributeType
        walletTotalBalance.isOptional = false
        walletTotalBalance.defaultValue = Decimal.zero

        let walletConfirmedBalance = NSAttributeDescription()
        walletConfirmedBalance.name = "confirmedBalance"
        walletConfirmedBalance.attributeType = .decimalAttributeType
        walletConfirmedBalance.isOptional = false
        walletConfirmedBalance.defaultValue = Decimal.zero

        let walletUnconfirmedBalance = NSAttributeDescription()
        walletUnconfirmedBalance.name = "unconfirmedBalance"
        walletUnconfirmedBalance.attributeType = .decimalAttributeType
        walletUnconfirmedBalance.isOptional = false
        walletUnconfirmedBalance.defaultValue = Decimal.zero

        let walletUtxoCount = NSAttributeDescription()
        walletUtxoCount.name = "utxoCount"
        walletUtxoCount.attributeType = .integer32AttributeType
        walletUtxoCount.isOptional = false
        walletUtxoCount.defaultValue = 0

        let walletTransactionCount = NSAttributeDescription()
        walletTransactionCount.name = "transactionCount"
        walletTransactionCount.attributeType = .integer32AttributeType
        walletTransactionCount.isOptional = false
        walletTransactionCount.defaultValue = 0

        let walletLastUpdated = NSAttributeDescription()
        walletLastUpdated.name = "lastUpdated"
        walletLastUpdated.attributeType = .dateAttributeType
        walletLastUpdated.isOptional = false
        walletLastUpdated.defaultValue = Date()

        let walletAddressType = NSAttributeDescription()
        walletAddressType.name = "addressType"
        walletAddressType.attributeType = .stringAttributeType
        walletAddressType.isOptional = false
        walletAddressType.defaultValue = "segwit"

        let walletReceiveIndex = NSAttributeDescription()
        walletReceiveIndex.name = "currentReceiveIndex"
        walletReceiveIndex.attributeType = .integer32AttributeType
        walletReceiveIndex.isOptional = false
        walletReceiveIndex.defaultValue = UInt32(0)

        let walletChangeIndex = NSAttributeDescription()
        walletChangeIndex.name = "currentChangeIndex"
        walletChangeIndex.attributeType = .integer32AttributeType
        walletChangeIndex.isOptional = false
        walletChangeIndex.defaultValue = UInt32(0)

        walletEntity.properties = [
            walletId, walletName, walletTotalBalance, walletConfirmedBalance,
            walletUnconfirmedBalance, walletUtxoCount, walletTransactionCount,
            walletLastUpdated, walletAddressType, walletReceiveIndex, walletChangeIndex
        ]

        // Only one wallet record
        walletEntity.uniquenessConstraints = [[walletId]]

        // ----- Assemble Model -----
        model.entities = [transactionEntity, utxoEntity, walletEntity]

        return model
    }

    // MARK: - Save Context

    /// Saves outstanding changes on the view context if any exist.
    ///
    /// Safe to call even when there are no pending changes (no-op in that case).
    /// Logs errors but does not throw to avoid disrupting the UI layer.
    func saveContext() {
        let context = viewContext
        guard context.hasChanges else { return }

        do {
            try context.save()
            DataLogger.debug("View context saved successfully.")
        } catch {
            DataLogger.error("Failed to save view context: \(error.localizedDescription)")
        }
    }

    // MARK: - Background Operations

    /// Executes a block on a background managed object context.
    ///
    /// The background context is configured with the same merge policy as
    /// the view context and automatically merges its changes into
    /// `viewContext` upon save.
    ///
    /// - Parameter block: A closure receiving the background context.
    ///   You are responsible for calling `context.save()` inside the block
    ///   when you want changes persisted.
    func performBackgroundTask(_ block: @escaping (NSManagedObjectContext) -> Void) {
        container.performBackgroundTask { context in
            context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            context.undoManager = nil
            block(context)
        }
    }

    /// Executes a block on a new background context and saves automatically.
    ///
    /// - Parameter block: A closure receiving the background context.
    ///   Changes are saved automatically after the block returns.
    func performBackgroundTaskAndSave(_ block: @escaping (NSManagedObjectContext) -> Void) {
        container.performBackgroundTask { context in
            context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            context.undoManager = nil
            block(context)

            guard context.hasChanges else { return }
            do {
                try context.save()
                DataLogger.debug("Background context saved successfully.")
            } catch {
                DataLogger.error("Failed to save background context: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Delete All Data

    /// Deletes all records from all entities in the persistent store.
    ///
    /// This is a destructive operation intended for wallet reset / sign-out
    /// scenarios. It uses `NSBatchDeleteRequest` for efficiency, which
    /// bypasses the managed object context and operates directly on the store.
    ///
    /// - Throws: An error if any batch delete request fails.
    func deleteAll() throws {
        let entityNames = ["CachedTransaction", "CachedUTXO", "WalletInfo"]

        for entityName in entityNames {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
            let batchDelete = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            batchDelete.resultType = .resultTypeObjectIDs

            do {
                let result = try viewContext.execute(batchDelete) as? NSBatchDeleteResult
                if let objectIDs = result?.result as? [NSManagedObjectID] {
                    // Merge deletions into the view context so the UI updates
                    let changes: [AnyHashable: Any] = [
                        NSDeletedObjectsKey: objectIDs
                    ]
                    NSManagedObjectContext.mergeChanges(
                        fromRemoteContextSave: changes,
                        into: [viewContext]
                    )
                }
                DataLogger.info("Deleted all \(entityName) records.")
            } catch {
                DataLogger.error("Failed to delete \(entityName) records: \(error.localizedDescription)")
                throw error
            }
        }
    }

    // MARK: - Fetch Helpers

    /// Fetches objects matching a request on the view context.
    ///
    /// - Parameter request: A configured `NSFetchRequest`.
    /// - Returns: An array of matching managed objects.
    /// - Throws: A Core Data fetch error.
    func fetch<T: NSManagedObject>(_ request: NSFetchRequest<T>) throws -> [T] {
        return try viewContext.fetch(request)
    }

    /// Returns the count of objects matching a request.
    ///
    /// - Parameter request: A configured `NSFetchRequest`.
    /// - Returns: The number of matching objects.
    func count<T: NSManagedObject>(for request: NSFetchRequest<T>) -> Int {
        return (try? viewContext.count(for: request)) ?? 0
    }

    // MARK: - Store URL

    /// The URL of the SQLite persistent store file, useful for debugging.
    var storeURL: URL? {
        container.persistentStoreDescriptions.first?.url
    }

    /// The total size of the persistent store file in bytes.
    var storeSizeBytes: Int64 {
        guard let url = storeURL else { return 0 }
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? Int64) ?? 0
    }

    // MARK: - Store Recovery

    /// Deletes the SQLite store files at the given URL.
    /// Used to recover from schema mismatches or corruption.
    private static func destroyStore(at url: URL) {
        let fileManager = FileManager.default
        let storePath = url.path
        // SQLite uses three files: .sqlite, .sqlite-wal, .sqlite-shm
        let suffixes = ["", "-wal", "-shm"]
        for suffix in suffixes {
            let filePath = storePath + suffix
            if fileManager.fileExists(atPath: filePath) {
                try? fileManager.removeItem(atPath: filePath)
            }
        }
    }
}
