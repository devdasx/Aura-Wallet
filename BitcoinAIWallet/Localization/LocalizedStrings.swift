import Foundation

// MARK: - Localized Strings
// All user-facing strings in the app are accessed through this enum.
// Each key uses `localizedString()` which routes through LocalizationManager's
// custom bundle, enabling in-app language switching without app restart.
//
// IMPORTANT: All properties are computed (`static var`) so they re-evaluate
// each time the language changes. Never use `static let` for localized strings.

enum L10n {

    // MARK: - Common

    enum Common {
        static var appName: String { localizedString("common.app_name") }
        static var ok: String { localizedString("common.ok") }
        static var cancel: String { localizedString("common.cancel") }
        static var confirm: String { localizedString("common.confirm") }
        static var done: String { localizedString("common.done") }
        static var next: String { localizedString("common.next") }
        static var back: String { localizedString("common.back") }
        static var close: String { localizedString("common.close") }
        static var save: String { localizedString("common.save") }
        static var delete: String { localizedString("common.delete") }
        static var copy: String { localizedString("common.copy") }
        static var share: String { localizedString("common.share") }
        static var retry: String { localizedString("common.retry") }
        static var loading: String { localizedString("common.loading") }
        static var error: String { localizedString("common.error") }
        static var success: String { localizedString("common.success") }
        static var copied: String { localizedString("common.copied") }
        static var bitcoin: String { localizedString("common.bitcoin") }
        static var btc: String { localizedString("common.btc") }
        static var sats: String { localizedString("common.sats") }
        static var mainnet: String { localizedString("common.mainnet") }
        static var testnet: String { localizedString("common.testnet") }
    }

    // MARK: - Onboarding

    enum Onboarding {
        static var welcomeTitle: String { localizedString("onboarding.welcome_title") }
        static var welcomeSubtitle: String { localizedString("onboarding.welcome_subtitle") }
        static var createWallet: String { localizedString("onboarding.create_wallet") }
        static var importWallet: String { localizedString("onboarding.import_wallet") }
        static var seedPhraseTitle: String { localizedString("onboarding.seed_phrase_title") }
        static var seedPhraseWarning: String { localizedString("onboarding.seed_phrase_warning") }
        static var seedPhraseInstruction: String { localizedString("onboarding.seed_phrase_instruction") }
        static var seedVerifyTitle: String { localizedString("onboarding.seed_verify_title") }
        static var seedVerifyInstruction: String { localizedString("onboarding.seed_verify_instruction") }
        static var importTitle: String { localizedString("onboarding.import_title") }
        static var importInstruction: String { localizedString("onboarding.import_instruction") }
        static var importPlaceholder: String { localizedString("onboarding.import_placeholder") }
        static var setPasscodeTitle: String { localizedString("onboarding.set_passcode_title") }
        static var setPasscodeSubtitle: String { localizedString("onboarding.set_passcode_subtitle") }
        static var enableBiometrics: String { localizedString("onboarding.enable_biometrics") }
        static var setupComplete: String { localizedString("onboarding.setup_complete") }
        static var iSavedIt: String { localizedString("onboarding.i_saved_it") }
        static var wordNumber: String { localizedString("onboarding.word_number") }
        static var generatingWallet: String { localizedString("onboarding.generating_wallet") }
        static var confirmPasscode: String { localizedString("onboarding.confirm_passcode") }
        static var confirmPasscodeSubtitle: String { localizedString("onboarding.confirm_passcode_subtitle") }
        static var passcodeMismatch: String { localizedString("onboarding.passcode_mismatch") }
        static var pasteFromClipboard: String { localizedString("onboarding.paste_from_clipboard") }
        static var verificationFailed: String { localizedString("onboarding.verification_failed") }
        static var enableBiometricsPrompt: String { localizedString("onboarding.enable_biometrics_prompt") }
        static var skipForNow: String { localizedString("onboarding.skip_for_now") }
        static var walletReady: String { localizedString("onboarding.wallet_ready") }
        static var getStarted: String { localizedString("onboarding.get_started") }
        static var wordCountFormat: String { localizedString("onboarding.word_count_format") }
        static var importButton: String { localizedString("onboarding.import_button") }
        static var securingWallet: String { localizedString("onboarding.securing_wallet") }
    }

    // MARK: - Wallet

    enum Wallet {
        static var mainWallet: String { localizedString("wallet.main_wallet") }
        static var balance: String { localizedString("wallet.balance") }
        static var totalBalance: String { localizedString("wallet.total_balance") }
        static var availableBalance: String { localizedString("wallet.available_balance") }
        static var pendingBalance: String { localizedString("wallet.pending_balance") }
        static var utxoCount: String { localizedString("wallet.utxo_count") }
        static var lastUpdated: String { localizedString("wallet.last_updated") }
        static var refreshing: String { localizedString("wallet.refreshing") }
    }

    // MARK: - Chat

    enum Chat {
        static var inputPlaceholder: String { localizedString("chat.input_placeholder") }
        static var greeting: String { localizedString("chat.greeting") }
        static var walletAI: String { localizedString("chat.wallet_ai") }
        static var thinking: String { localizedString("chat.thinking") }
        static var today: String { localizedString("chat.today") }
        static var yesterday: String { localizedString("chat.yesterday") }
        static var sendConfirmPrompt: String { localizedString("chat.send_confirm_prompt") }
        static var sendSuccess: String { localizedString("chat.send_success") }
        static var sendFailed: String { localizedString("chat.send_failed") }
        static var receivePrompt: String { localizedString("chat.receive_prompt") }
        static var balanceResponse: String { localizedString("chat.balance_response") }
        static var historyResponse: String { localizedString("chat.history_response") }
        static var unknownCommand: String { localizedString("chat.unknown_command") }
        static var insufficientFunds: String { localizedString("chat.insufficient_funds") }
        static var invalidAddress: String { localizedString("chat.invalid_address") }
        static var feeEstimate: String { localizedString("chat.fee_estimate") }
        static var pendingNotice: String { localizedString("chat.pending_notice") }
        static var confirmedNotice: String { localizedString("chat.confirmed_notice") }
        static var taprootNote: String { localizedString("chat.taproot_note") }
        static var newAddressNote: String { localizedString("chat.new_address_note") }
        static var netFlowSummary: String { localizedString("chat.net_flow_summary") }

        // Extended chat strings
        static var priceFetching: String { localizedString("chat.price_fetching") }
        static var newAddressGenerated: String { localizedString("chat.new_address_generated") }
        static var walletHealthTitle: String { localizedString("chat.wallet_health_title") }
        static var walletHealthStatus: String { localizedString("chat.wallet_health_status") }
        static var exportHistoryResponse: String { localizedString("chat.export_history_response") }
        static var bumpFeeResponse: String { localizedString("chat.bump_fee_response") }
        static var networkConnected: String { localizedString("chat.network_connected") }
        static var networkDisconnected: String { localizedString("chat.network_disconnected") }
        static var aboutResponse: String { localizedString("chat.about_response") }
        static var smartFallback: String { localizedString("chat.smart_fallback") }
        static var nothingToConfirm: String { localizedString("chat.nothing_to_confirm") }
        static var helpTitle: String { localizedString("chat.help_title") }
        static var askForAddress: String { localizedString("chat.ask_for_address") }
        static var askForAmount: String { localizedString("chat.ask_for_amount") }
        static var operationCancelled: String { localizedString("chat.operation_cancelled") }
        static var balanceHidden: String { localizedString("chat.balance_hidden") }
        static var balanceShown: String { localizedString("chat.balance_shown") }
        static var walletRefreshing: String { localizedString("chat.wallet_refreshing") }
        static var walletRefreshed: String { localizedString("chat.wallet_refreshed") }
        static var testnetNotSupported: String { localizedString("chat.testnet_not_supported") }

        static func priceResponseTemplate(_ price: String, _ currency: String) -> String {
            localizedFormat("chat.price_response_template", price, currency)
        }
        static func convertResponseTemplate(_ fiatAmount: String, _ currency: String, _ btcAmount: String) -> String {
            localizedFormat("chat.convert_response_template", fiatAmount, currency, btcAmount)
        }
        static func transactionCountLabel(_ count: Int) -> String {
            localizedFormat("chat.transaction_count_label", count)
        }
        static func utxoListResponse(_ count: Int) -> String {
            localizedFormat("chat.utxo_list_response", count)
        }
        static func bumpFeeResponseWithTxid(_ txid: String) -> String {
            localizedFormat("chat.bump_fee_response_with_txid", txid)
        }
    }

    // MARK: - Send

    enum Send {
        static var title: String { localizedString("send.title") }
        static var amount: String { localizedString("send.amount") }
        static var to: String { localizedString("send.to") }
        static var from: String { localizedString("send.from") }
        static var networkFee: String { localizedString("send.network_fee") }
        static var estimatedTime: String { localizedString("send.estimated_time") }
        static var remaining: String { localizedString("send.remaining") }
        static var total: String { localizedString("send.total") }
        static var confirmAndSign: String { localizedString("send.confirm_and_sign") }
        static var changeFee: String { localizedString("send.change_fee") }
        static var review: String { localizedString("send.review") }
        static var signing: String { localizedString("send.signing") }
        static var broadcasting: String { localizedString("send.broadcasting") }
        static var usdEquivalent: String { localizedString("send.usd_equivalent") }
        static var satPerVbyte: String { localizedString("send.sat_per_vbyte") }
        static var minutes: String { localizedString("send.minutes") }
    }

    // MARK: - Receive

    enum Receive {
        static var title: String { localizedString("receive.title") }
        static var yourAddress: String { localizedString("receive.your_address") }
        static var scanQR: String { localizedString("receive.scan_qr") }
        static var addressCopied: String { localizedString("receive.address_copied") }
        static var shareAddress: String { localizedString("receive.share_address") }
        static var newAddress: String { localizedString("receive.new_address") }
        static var addressType: String { localizedString("receive.address_type") }
    }

    // MARK: - History

    enum History {
        static var title: String { localizedString("history.title") }
        static var recentTransactions: String { localizedString("history.recent_transactions") }
        static var sent: String { localizedString("history.sent") }
        static var received: String { localizedString("history.received") }
        static var pending: String { localizedString("history.pending") }
        static var confirmed: String { localizedString("history.confirmed") }
        static var confirmations: String { localizedString("history.confirmations") }
        static var noTransactions: String { localizedString("history.no_transactions") }
        static var viewOnExplorer: String { localizedString("history.view_on_explorer") }
        static var transactionSent: String { localizedString("history.transaction_sent") }
        static var txid: String { localizedString("history.txid") }
    }

    // MARK: - Fee

    enum Fee {
        static var title: String { localizedString("fee.title") }
        static var slow: String { localizedString("fee.slow") }
        static var medium: String { localizedString("fee.medium") }
        static var fast: String { localizedString("fee.fast") }
        static var custom: String { localizedString("fee.custom") }
        static var slowTime: String { localizedString("fee.slow_time") }
        static var mediumTime: String { localizedString("fee.medium_time") }
        static var fastTime: String { localizedString("fee.fast_time") }
        static var satVb: String { localizedString("fee.sat_vb") }
    }

    // MARK: - Quick Action

    enum QuickAction {
        static var send: String { localizedString("quick_action.send") }
        static var receive: String { localizedString("quick_action.receive") }
        static var history: String { localizedString("quick_action.history") }
        static var fees: String { localizedString("quick_action.fees") }
        static var settings: String { localizedString("quick_action.settings") }
    }

    // MARK: - Settings

    enum Settings {
        static var title: String { localizedString("settings.title") }
        static var general: String { localizedString("settings.general") }
        static var security: String { localizedString("settings.security") }
        static var network: String { localizedString("settings.network") }
        static var about: String { localizedString("settings.about") }
        static var currency: String { localizedString("settings.currency") }
        static var theme: String { localizedString("settings.theme") }
        static var darkMode: String { localizedString("settings.dark_mode") }
        static var lightMode: String { localizedString("settings.light_mode") }
        static var systemMode: String { localizedString("settings.system_mode") }
        static var language: String { localizedString("settings.language") }
        static var changePasscode: String { localizedString("settings.change_passcode") }
        static var biometrics: String { localizedString("settings.biometrics") }
        static var backupWallet: String { localizedString("settings.backup_wallet") }
        static var blockbookServer: String { localizedString("settings.blockbook_server") }
        static var ankrEndpoint: String { localizedString("settings.ankr_endpoint") }
        static var networkStatus: String { localizedString("settings.network_status") }
        static var version: String { localizedString("settings.version") }
        static var deleteWallet: String { localizedString("settings.delete_wallet") }
        static var deleteWalletWarning: String { localizedString("settings.delete_wallet_warning") }
        static var connected: String { localizedString("settings.connected") }
        static var disconnected: String { localizedString("settings.disconnected") }
        // Additional settings strings
        static var serverConfiguration: String { localizedString("settings.server_configuration") }
        static var testConnection: String { localizedString("settings.test_connection") }
        static var connectionSuccess: String { localizedString("settings.connection_success") }
        static var invalidUrl: String { localizedString("settings.invalid_url") }
        static var connectionInfo: String { localizedString("settings.connection_info") }
        static var connectionType: String { localizedString("settings.connection_type") }
        static var currentServer: String { localizedString("settings.current_server") }
        static var networkQuality: String { localizedString("settings.network_quality") }
        static var expensiveConnection: String { localizedString("settings.expensive_connection") }
        static var lowDataMode: String { localizedString("settings.low_data_mode") }
        static var active: String { localizedString("settings.active") }
        static var enabled: String { localizedString("settings.enabled") }
        static var unrestrictedConnection: String { localizedString("settings.unrestricted_connection") }
        static var resetToDefault: String { localizedString("settings.reset_to_default") }
        static var defaultServerNote: String { localizedString("settings.default_server_note") }
        static var cellular: String { localizedString("settings.cellular") }
        static var wired: String { localizedString("settings.wired") }
        static var serverError: String { localizedString("settings.server_error") }
        static var autoLock: String { localizedString("settings.auto_lock") }
        static var autoLockFooter: String { localizedString("settings.auto_lock_footer") }
        static var passcode: String { localizedString("settings.passcode") }
        static var currentPasscode: String { localizedString("settings.current_passcode") }
        static var newPasscode: String { localizedString("settings.new_passcode") }
        static var confirmNewPasscode: String { localizedString("settings.confirm_new_passcode") }
        static var passcodeChanged: String { localizedString("settings.passcode_changed") }
        static var passcodeChangedMessage: String { localizedString("settings.passcode_changed_message") }
        static var biometricsUnavailable: String { localizedString("settings.biometrics_unavailable") }
        static var biometricsFooter: String { localizedString("settings.biometrics_footer") }
        static var faceIdDescription: String { localizedString("settings.face_id_description") }
        static var touchIdDescription: String { localizedString("settings.touch_id_description") }
        static var biometricNoneDescription: String { localizedString("settings.biometric_none_description") }
        static var passcodeTooShort: String { localizedString("settings.passcode_too_short") }
        static var currentPasscodeWrong: String { localizedString("settings.current_passcode_wrong") }
        static var chat: String { localizedString("settings.chat") }
        static var tipsEnabled: String { localizedString("settings.tips_enabled") }
        static var tipsEnabledSubtitle: String { localizedString("settings.tips_enabled_subtitle") }
        static var appearance: String { localizedString("settings.appearance") }
        static var colorMode: String { localizedString("settings.color_mode") }
        static var chatFont: String { localizedString("settings.chat_font") }
        static var chatFontPreview: String { localizedString("settings.chat_font.preview") }
        static var typingHaptics: String { localizedString("settings.typing_haptics") }
        static var typingHapticsSubtitle: String { localizedString("settings.typing_haptics_subtitle") }
        static var oneMinute: String { localizedString("settings.one_minute") }
        static var fiveMinutes: String { localizedString("settings.five_minutes") }
        static var fifteenMinutes: String { localizedString("settings.fifteen_minutes") }
        static var thirtyMinutes: String { localizedString("settings.thirty_minutes") }
    }

    // MARK: - Backup

    enum Backup {
        static var authenticateTitle: String { localizedString("backup.authenticate_title") }
        static var authenticateSubtitle: String { localizedString("backup.authenticate_subtitle") }
        static var authenticateButton: String { localizedString("backup.authenticate_button") }
        static var neverShare: String { localizedString("backup.never_share") }
        static var warningTitle: String { localizedString("backup.warning_title") }
        static var warningMessage: String { localizedString("backup.warning_message") }
    }

    // MARK: - Error

    enum Error {
        static var network: String { localizedString("error.network") }
        static var invalidAmount: String { localizedString("error.invalid_amount") }
        static var invalidAddress: String { localizedString("error.invalid_address") }
        static var insufficientFunds: String { localizedString("error.insufficient_funds") }
        static var transactionFailed: String { localizedString("error.transaction_failed") }
        static var broadcastFailed: String { localizedString("error.broadcast_failed") }
        static var keychain: String { localizedString("error.keychain") }
        static var biometricFailed: String { localizedString("error.biometric_failed") }
        static var walletCorrupted: String { localizedString("error.wallet_corrupted") }
        static var api: String { localizedString("error.api") }
        static var unknown: String { localizedString("error.unknown") }
        static var walletNotReady: String { localizedString("error.wallet_not_ready") }
        static var feeEstimationFailed: String { localizedString("error.fee_estimation_failed") }
        static var seedPhraseInvalid: String { localizedString("error.seed_phrase_invalid") }
    }

    // MARK: - Biometric

    enum Biometric {
        static var faceID: String { localizedString("biometric.face_id") }
        static var touchID: String { localizedString("biometric.touch_id") }
        static var reason: String { localizedString("biometric.reason") }
        static var signReason: String { localizedString("biometric.sign_reason") }
    }

    // MARK: - Lock Screen

    enum LockScreen {
        static var subtitle: String { localizedString("lock_screen.subtitle") }
        static var unlockButton: String { localizedString("lock_screen.unlock_button") }
        static var authFailed: String { localizedString("lock_screen.auth_failed") }
    }

    // MARK: - Format

    enum Format {
        static func btcAmount(_ amount: String) -> String {
            localizedFormat("format.btc_amount", amount)
        }

        static func usdAmount(_ amount: String) -> String {
            localizedFormat("format.usd_amount", amount)
        }

        static func feeRate(_ rate: String) -> String {
            localizedFormat("format.fee_rate", rate)
        }

        static func confirmationCount(_ count: Int) -> String {
            localizedFormat("format.confirmation_count", count)
        }

        static func estimatedMinutes(_ minutes: Int) -> String {
            localizedFormat("format.estimated_minutes", minutes)
        }

        static func utxoCount(_ count: Int) -> String {
            localizedFormat("format.utxo_count", count)
        }

        static func greetingWithName(_ name: String) -> String {
            localizedFormat("format.greeting_with_name", name)
        }
    }

    // MARK: - Sidebar

    enum Sidebar {
        static var newChat: String { localizedString("sidebar.new_chat") }
        static var searchPlaceholder: String { localizedString("sidebar.search_placeholder") }
        static var pinned: String { localizedString("sidebar.pinned") }
        static var yesterday: String { localizedString("sidebar.yesterday") }
        static var thisWeek: String { localizedString("sidebar.this_week") }
        static var older: String { localizedString("sidebar.older") }
        static var deleteConversation: String { localizedString("sidebar.delete_conversation") }
        static var deleteConfirmMessage: String { localizedString("sidebar.delete_confirm_message") }
        static var rename: String { localizedString("sidebar.rename") }
        static var conversationName: String { localizedString("sidebar.conversation_name") }
        static var pin: String { localizedString("sidebar.pin") }
        static var unpin: String { localizedString("sidebar.unpin") }
        static var noConversations: String { localizedString("sidebar.no_conversations") }
    }

    // MARK: - Scanner

    enum Scanner {
        static var title: String { localizedString("scanner.title") }
        static var error: String { localizedString("scanner.error") }
    }

    // MARK: - Welcome

    enum Welcome {
        static var morning: String { localizedString("welcome.morning") }
        static var afternoon: String { localizedString("welcome.afternoon") }
        static var evening: String { localizedString("welcome.evening") }
        static var night: String { localizedString("welcome.night") }
        static var subtitle: String { localizedString("welcome.subtitle") }
    }
}
