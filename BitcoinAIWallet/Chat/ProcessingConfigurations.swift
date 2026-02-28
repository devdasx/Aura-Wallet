import Foundation

// MARK: - ProcessingConfigurations
// Factory methods that return pre-configured ProcessingState instances
// for each async wallet operation. Step labels use localization keys
// resolved via `localizedString()` in ProcessingStep.

@MainActor
enum ProcessingConfigurations {

    // MARK: - Wallet Operations

    static func walletRefresh() -> ProcessingState {
        ProcessingState(steps: [
            ProcessingStep(labelKey: "processing.refresh.connecting"),
            ProcessingStep(labelKey: "processing.refresh.fetching_balance"),
            ProcessingStep(labelKey: "processing.refresh.syncing_transactions"),
            ProcessingStep(labelKey: "processing.refresh.updating_fees"),
        ])
    }

    static func balance() -> ProcessingState {
        ProcessingState(steps: [
            ProcessingStep(labelKey: "processing.balance.connecting"),
            ProcessingStep(labelKey: "processing.balance.fetching_balance"),
            ProcessingStep(labelKey: "processing.balance.calculating"),
        ])
    }

    static func sendTransaction() -> ProcessingState {
        ProcessingState(steps: [
            ProcessingStep(labelKey: "processing.send.signing"),
            ProcessingStep(labelKey: "processing.send.broadcasting"),
            ProcessingStep(labelKey: "processing.send.confirming"),
        ])
    }

    static func historyFetch() -> ProcessingState {
        ProcessingState(steps: [
            ProcessingStep(labelKey: "processing.history.fetching_transactions"),
            ProcessingStep(labelKey: "processing.history.processing_data"),
        ])
    }

    static func txDetail() -> ProcessingState {
        ProcessingState(steps: [
            ProcessingStep(labelKey: "processing.tx_detail.looking_up"),
            ProcessingStep(labelKey: "processing.tx_detail.fetching_details"),
        ])
    }

    static func feeEstimates() -> ProcessingState {
        ProcessingState(steps: [
            ProcessingStep(labelKey: "processing.fees.querying_mempool"),
            ProcessingStep(labelKey: "processing.fees.calculating_rates"),
        ])
    }

    // MARK: - Price & Conversion

    static func priceFetch() -> ProcessingState {
        ProcessingState(steps: [
            ProcessingStep(labelKey: "processing.price.fetching"),
            ProcessingStep(labelKey: "processing.price.converting"),
        ])
    }

    static func convertAmount() -> ProcessingState {
        ProcessingState(steps: [
            ProcessingStep(labelKey: "processing.convert.fetching_rate"),
            ProcessingStep(labelKey: "processing.convert.calculating"),
        ])
    }

    // MARK: - Address

    static func validateAddress() -> ProcessingState {
        ProcessingState(steps: [
            ProcessingStep(labelKey: "processing.validate.checking_format"),
            ProcessingStep(labelKey: "processing.validate.validating_checksum"),
            ProcessingStep(labelKey: "processing.validate.identifying_type"),
        ])
    }

    static func newAddress() -> ProcessingState {
        ProcessingState(steps: [
            ProcessingStep(labelKey: "processing.new_address.deriving_key"),
            ProcessingStep(labelKey: "processing.new_address.verifying"),
        ])
    }

    // MARK: - Wallet Health & Network

    static func walletHealth() -> ProcessingState {
        ProcessingState(steps: [
            ProcessingStep(labelKey: "processing.health.checking_keychain"),
            ProcessingStep(labelKey: "processing.health.verifying_keys"),
            ProcessingStep(labelKey: "processing.health.testing_network"),
            ProcessingStep(labelKey: "processing.health.calculating_score"),
        ])
    }

    static func networkStatus() -> ProcessingState {
        ProcessingState(steps: [
            ProcessingStep(labelKey: "processing.network.checking_connectivity"),
            ProcessingStep(labelKey: "processing.network.analyzing"),
        ])
    }

    // MARK: - Export & Import

    static func exportHistory() -> ProcessingState {
        ProcessingState(steps: [
            ProcessingStep(labelKey: "processing.export.gathering_data"),
            ProcessingStep(labelKey: "processing.export.formatting_file"),
        ])
    }

    static func importWallet() -> ProcessingState {
        ProcessingState(steps: [
            ProcessingStep(labelKey: "processing.import.validating_seed"),
            ProcessingStep(labelKey: "processing.import.deriving_keys"),
            ProcessingStep(labelKey: "processing.import.scanning_blockchain"),
            ProcessingStep(labelKey: "processing.import.syncing"),
            ProcessingStep(labelKey: "processing.import.building_utxos"),
        ])
    }

    static func createWallet() -> ProcessingState {
        ProcessingState(steps: [
            ProcessingStep(labelKey: "processing.create.generating_entropy"),
            ProcessingStep(labelKey: "processing.create.creating_seed"),
            ProcessingStep(labelKey: "processing.create.deriving_keys"),
            ProcessingStep(labelKey: "processing.create.securing_keychain"),
        ])
    }

    static func deleteWallet() -> ProcessingState {
        ProcessingState(steps: [
            ProcessingStep(labelKey: "processing.delete.authenticating"),
            ProcessingStep(labelKey: "processing.delete.erasing_keys"),
            ProcessingStep(labelKey: "processing.delete.clearing_data"),
        ])
    }

    // MARK: - Backup

    static func backupSeed() -> ProcessingState {
        ProcessingState(steps: [
            ProcessingStep(labelKey: "processing.backup.authenticating"),
            ProcessingStep(labelKey: "processing.backup.decrypting"),
        ])
    }

    // MARK: - Fee Management

    static func bumpFee() -> ProcessingState {
        ProcessingState(steps: [
            ProcessingStep(labelKey: "processing.bump_fee.creating_replacement"),
            ProcessingStep(labelKey: "processing.bump_fee.signing"),
            ProcessingStep(labelKey: "processing.bump_fee.broadcasting"),
        ])
    }

    static func consolidateUTXOs() -> ProcessingState {
        ProcessingState(steps: [
            ProcessingStep(labelKey: "processing.consolidate.selecting_utxos"),
            ProcessingStep(labelKey: "processing.consolidate.building_tx"),
            ProcessingStep(labelKey: "processing.consolidate.signing"),
            ProcessingStep(labelKey: "processing.consolidate.broadcasting"),
        ])
    }

    // MARK: - Server

    static func testConnection() -> ProcessingState {
        ProcessingState(steps: [
            ProcessingStep(labelKey: "processing.test_connection.pinging_server"),
            ProcessingStep(labelKey: "processing.test_connection.checking_api"),
            ProcessingStep(labelKey: "processing.test_connection.measuring_latency"),
        ])
    }

    static func changeServer() -> ProcessingState {
        ProcessingState(steps: [
            ProcessingStep(labelKey: "processing.change_server.testing_server"),
            ProcessingStep(labelKey: "processing.change_server.validating_api"),
            ProcessingStep(labelKey: "processing.change_server.switching"),
        ])
    }

    // MARK: - Rescan

    static func rescanWallet() -> ProcessingState {
        ProcessingState(steps: [
            ProcessingStep(labelKey: "processing.rescan.scanning_addresses"),
            ProcessingStep(labelKey: "processing.rescan.fetching_history"),
            ProcessingStep(labelKey: "processing.rescan.building_utxos"),
            ProcessingStep(labelKey: "processing.rescan.finalizing"),
        ])
    }

    // MARK: - Signing & Verification

    static func signMessage() -> ProcessingState {
        ProcessingState(steps: [
            ProcessingStep(labelKey: "processing.sign_message.authenticating"),
            ProcessingStep(labelKey: "processing.sign_message.signing"),
        ])
    }

    static func verifyMessage() -> ProcessingState {
        ProcessingState(steps: [
            ProcessingStep(labelKey: "processing.verify_message.parsing_signature"),
            ProcessingStep(labelKey: "processing.verify_message.verifying_proof"),
        ])
    }

    // MARK: - Analytics

    static func spendingSummary() -> ProcessingState {
        ProcessingState(steps: [
            ProcessingStep(labelKey: "processing.spending.fetching_transactions"),
            ProcessingStep(labelKey: "processing.spending.calculating"),
            ProcessingStep(labelKey: "processing.spending.generating_summary"),
        ])
    }

    static func mempoolStatus() -> ProcessingState {
        ProcessingState(steps: [
            ProcessingStep(labelKey: "processing.mempool.connecting"),
            ProcessingStep(labelKey: "processing.mempool.fetching_mempool"),
            ProcessingStep(labelKey: "processing.mempool.analyzing"),
        ])
    }
}
