import Foundation

// MARK: - Constants
// App-wide constant values used across the Bitcoin AI Wallet.
// Centralizes magic numbers and configuration defaults so they
// can be reviewed, audited, and updated in a single location.

enum Constants {

    // MARK: - Bitcoin

    /// Number of satoshis in one BTC (10^8).
    static let satoshisPerBTC: Decimal = 100_000_000

    /// Minimum output value in satoshis below which nodes reject a transaction as dust.
    static let dustLimitSats: UInt64 = 546

    /// Maximum total supply of Bitcoin that will ever exist.
    static let maxBTCSupply: Decimal = 21_000_000

    /// Default fee rate in sat/vByte when the fee estimator is unavailable.
    static let defaultFeeRateSatVB: Decimal = 10

    // MARK: - Network

    /// Default Blockbook REST API server URL (Ankr premium).
    static let defaultBlockbookURL = "https://rpc.ankr.com/premium-http/btc_blockbook/42cb7796858fdf001f82278d929e8b61c865af79cd4efffbe574f344312e6ab2"

    /// Default Bitcoin RPC endpoint (Ankr premium).
    static let defaultBtcRpcURL = "https://rpc.ankr.com/btc/42cb7796858fdf001f82278d929e8b61c865af79cd4efffbe574f344312e6ab2"

    /// Default Blockbook WebSocket server URL (disabled for Ankr).
    static let defaultBlockbookWSURL = ""

    /// Base URL for the block explorer transaction viewer.
    static let blockExplorerURL = "https://mempool.space/tx/"

    /// Maximum time in seconds to wait for an HTTP response.
    static let requestTimeoutSeconds: TimeInterval = 30

    /// Maximum number of automatic retry attempts for transient failures.
    static let maxRetryAttempts = 3

    // MARK: - Wallet

    /// BIP-44 gap limit: number of consecutive unused addresses to check before
    /// concluding that the wallet has no more activity on that derivation path.
    static let defaultGapLimit = 20

    /// Number of words in the mnemonic recovery phrase.
    static let mnemonicWordCount = 12

    /// Number of confirmations required to consider a transaction fully confirmed.
    static let confirmationsRequired = 6

    /// Maximum number of addresses to synchronize in a single batch request.
    static let maxAddressesPerSync = 100

    // MARK: - UI

    /// Default duration for standard view animations.
    static let animationDuration: TimeInterval = 0.3

    /// Delay before showing a typing indicator in the chat interface.
    static let typingDelay: TimeInterval = 0.5

    /// Interval in seconds between automatic balance refresh requests.
    static let balanceRefreshInterval: TimeInterval = 60

    /// Maximum character count allowed in a single chat message.
    static let maxChatMessageLength = 500

    // MARK: - Security

    /// Default auto-lock timeout in seconds (5 minutes).
    static let autoLockTimeoutSeconds: TimeInterval = 300

    /// Maximum consecutive failed passcode attempts before lockout.
    static let maxPasscodeAttempts = 5

    /// Number of PBKDF2 iterations for key derivation.
    static let pbkdf2Iterations = 600_000
}
