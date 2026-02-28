// MARK: - ResponseTemplates.swift
// Bitcoin AI Wallet
//
// Pre-defined response templates for the AI chat assistant.
// All user-facing strings are routed through L10n for localization.
// Templates embed formatting tokens ({{amount:}}, **bold**, etc.)
// that MessageFormatter parses at display time.
//
// Platform: iOS 17.0+
// Framework: Foundation

import Foundation

// MARK: - ResponseTemplates

struct ResponseTemplates {

    // MARK: - Greeting

    static func greeting(walletName: String?) -> String {
        if let name = walletName {
            return L10n.Format.greetingWithName(name)
        }
        return L10n.Chat.greeting
    }

    // MARK: - Balance

    static func balanceResponse(btcAmount: String, fiatAmount: String, pendingAmount: String?, utxoCount: Int) -> String {
        var lines: [String] = []
        lines.append("{{amount:\(btcAmount) BTC}}  {{fiat:\(fiatAmount)}}")
        lines.append("")
        lines.append("• \(L10n.Wallet.availableBalance): **\(btcAmount) BTC**")
        if let pending = pendingAmount {
            lines.append("• \(L10n.Wallet.pendingBalance): **\(pending) BTC**")
        }
        lines.append("• \(L10n.Wallet.utxoCount): **\(utxoCount)**")
        lines.append("")
        lines.append("{{dim:\(L10n.Wallet.lastUpdated): \(localizedString("chat.just_now"))}}")
        return lines.joined(separator: "\n")
    }

    // MARK: - Send

    static func sendConfirmation() -> String {
        L10n.Chat.sendConfirmPrompt
    }

    static func sendSuccess(txid: String) -> String {
        var lines: [String] = []
        lines.append("{{green:\(L10n.Chat.sendSuccess)}}")
        lines.append("")
        lines.append("• \(L10n.History.txid): {{address:\(txid)}}")
        return lines.joined(separator: "\n")
    }

    static func sendFailed(reason: String) -> String {
        var lines: [String] = []
        lines.append("{{red:\(L10n.Chat.sendFailed)}}")
        lines.append("")
        lines.append(reason)
        return lines.joined(separator: "\n")
    }

    static func insufficientFunds(available: String) -> String {
        var lines: [String] = []
        lines.append("{{red:\(L10n.Chat.insufficientFunds)}}")
        lines.append("")
        lines.append("• \(L10n.Wallet.availableBalance): **\(available) BTC**")
        return lines.joined(separator: "\n")
    }

    static func invalidAddress() -> String {
        "{{red:\(L10n.Chat.invalidAddress)}}"
    }

    // MARK: - Receive

    static func receiveAddress(address: String, type: String) -> String {
        var lines: [String] = []
        lines.append(L10n.Chat.receivePrompt)
        lines.append("")
        lines.append("{{address:\(address)}}")
        lines.append("")
        lines.append("• \(L10n.Receive.addressType): **\(type)**")
        if type.lowercased().contains("taproot") {
            lines.append("")
            lines.append("{{dim:\(L10n.Chat.taprootNote)}}")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - History

    static func historyResponse(count: Int) -> String {
        if count == 0 { return noTransactions() }
        return "\(L10n.Chat.historyResponse) (**\(count)**)"
    }

    static func noTransactions() -> String {
        L10n.History.noTransactions
    }

    // MARK: - Fee

    static func feeEstimateResponse(slow: String, medium: String, fast: String) -> String {
        var lines: [String] = []
        lines.append(L10n.Chat.feeEstimate)
        lines.append("")
        lines.append("• \(L10n.Fee.fast): **\(fast)**")
        lines.append("• \(L10n.Fee.medium): **\(medium)**")
        lines.append("• \(L10n.Fee.slow): **\(slow)**")
        return lines.joined(separator: "\n")
    }

    // MARK: - Price

    static func priceResponse(formattedPrice: String, currency: String) -> String {
        var lines: [String] = []
        lines.append("{{amount:\(formattedPrice) \(currency)}}")
        lines.append("")
        lines.append(localizedFormat("chat.price_response_template", formattedPrice, currency))
        return lines.joined(separator: "\n")
    }

    static func priceFetching() -> String {
        "{{dim:\(localizedString("chat.price_fetching"))}}"
    }

    // MARK: - Convert

    static func convertResponse(fiatAmount: String, currency: String, btcAmount: String) -> String {
        var lines: [String] = []
        lines.append("**\(fiatAmount)** \(currency) = {{amount:\(btcAmount) BTC}}")
        lines.append("")
        lines.append("{{dim:\(localizedFormat("chat.convert_response_template", fiatAmount, currency, btcAmount))}}")
        return lines.joined(separator: "\n")
    }

    // MARK: - New Address

    static func newAddressGenerated() -> String {
        "{{green:\(localizedString("chat.new_address_generated"))}}"
    }

    // MARK: - Wallet Health

    static func walletHealthResponse(balance: String, utxoCount: Int, pendingBalance: String, transactionCount: Int) -> String {
        var lines: [String] = []
        lines.append("**\(localizedString("chat.wallet_health_title"))**")
        lines.append("")
        lines.append("• \(L10n.Wallet.totalBalance): **\(balance) BTC**")
        lines.append("• \(L10n.Wallet.utxoCount): **\(utxoCount)**")
        if Decimal(string: pendingBalance) ?? 0 > 0 {
            lines.append("• \(L10n.Wallet.pendingBalance): **\(pendingBalance) BTC**")
        }
        lines.append("• \(localizedFormat("chat.transaction_count_label", transactionCount))")
        lines.append("")
        lines.append("{{green:\(localizedString("chat.wallet_health_status"))}}")
        return lines.joined(separator: "\n")
    }

    // MARK: - Export

    static func exportHistoryResponse() -> String {
        localizedString("chat.export_history_response")
    }

    // MARK: - UTXO

    static func utxoListResponse(count: Int) -> String {
        localizedFormat("chat.utxo_list_response", count)
    }

    // MARK: - Bump Fee

    static func bumpFeeResponse(txid: String?) -> String {
        if let txid = txid {
            var lines: [String] = []
            lines.append(localizedString("chat.bump_fee_intro"))
            lines.append("")
            lines.append("• \(L10n.History.txid): {{address:\(txid)}}")
            return lines.joined(separator: "\n")
        }
        return localizedString("chat.bump_fee_response")
    }

    // MARK: - Network Status

    static func networkStatusResponse(isConnected: Bool) -> String {
        if isConnected {
            return "{{green:\(localizedString("chat.network_connected"))}}"
        }
        return "{{red:\(localizedString("chat.network_disconnected"))}}"
    }

    // MARK: - About

    static func aboutResponse() -> String {
        localizedString("chat.about_response")
    }

    // MARK: - Smart Fallback

    static func smartFallback() -> String {
        localizedString("chat.smart_fallback")
    }

    // MARK: - Nothing to Confirm

    static func nothingToConfirm() -> String {
        localizedString("chat.nothing_to_confirm")
    }

    // MARK: - Transaction Status

    static func pendingTransaction(confirmations: Int) -> String {
        "{{status:pending}} \(L10n.Chat.pendingNotice) {{dim:(\(L10n.Format.confirmationCount(confirmations)))}}"
    }

    static func confirmedTransaction() -> String {
        "{{status:success}} \(L10n.Chat.confirmedNotice)"
    }

    // MARK: - Errors

    static func networkError() -> String {
        "{{red:\(L10n.Error.network)}}"
    }

    static func walletNotReady() -> String {
        "{{red:\(L10n.Error.walletNotReady)}}"
    }

    static func unknownCommand() -> String { L10n.Chat.unknownCommand }

    static func genericError(_ message: String) -> String {
        "{{red:\(L10n.Common.error):}} \(message)"
    }

    // MARK: - Help

    static func helpResponse() -> String {
        var lines: [String] = []
        lines.append("**\(localizedString("chat.help_title"))**")
        lines.append("")
        lines.append("• \(L10n.QuickAction.send): **\"send 0.005 to bc1q...\"**")
        lines.append("• \(L10n.QuickAction.receive): **\"receive\"** or **\"my address\"**")
        lines.append("• \(L10n.Wallet.balance): **\"balance\"** or **\"how much do I have\"**")
        lines.append("• \(L10n.QuickAction.history): **\"history\"** or **\"last 5 transactions\"**")
        lines.append("• \(L10n.QuickAction.fees): **\"fees\"** or **\"fee estimate\"**")
        lines.append("• Price: **\"price\"** or **\"btc price in EUR\"**")
        lines.append("• Convert: **\"$50\"** or **\"100 EUR\"**")
        lines.append("• Wallet Health: **\"wallet health\"**")
        lines.append("• New Address: **\"new address\"**")
        lines.append("• UTXOs: **\"utxo\"** or **\"unspent outputs\"**")
        lines.append("• Network: **\"network status\"**")
        lines.append("• \(L10n.QuickAction.settings): **\"settings\"**")
        return lines.joined(separator: "\n")
    }

    // MARK: - Prompts

    static func askForAddress() -> String {
        localizedString("chat.ask_for_address")
    }

    static func askForAmount() -> String {
        localizedString("chat.ask_for_amount")
    }

    static func askToConfirm() -> String { L10n.Chat.sendConfirmPrompt }

    static func askForFeeLevel() -> String {
        "• \(L10n.Fee.slow)\n• \(L10n.Fee.medium)\n• \(L10n.Fee.fast)"
    }

    // MARK: - Transaction Detail

    static func transactionDetail(txid: String, type: String, amount: String, address: String, confirmations: Int, date: String) -> String {
        let isSent = type == "sent"
        let status: StatusType = confirmations >= 6 ? .success : .pending
        let statusLabel = status == .success ? L10n.History.confirmed : L10n.History.pending
        let amountPrefix = isSent ? "-" : "+"
        let colorToken = isSent ? "red" : "green"

        var lines: [String] = []
        lines.append("{{status:\(status.rawValue)}} **\(statusLabel)** {{dim:(\(L10n.Format.confirmationCount(confirmations)))}}")
        lines.append("")
        lines.append("• \(L10n.Send.amount): {{\(colorToken):\(amountPrefix)\(amount) BTC}}")
        lines.append("• \(isSent ? L10n.Send.to : L10n.Send.from): {{address:\(address)}}")
        lines.append("• \(L10n.History.txid): {{address:\(txid)}}")
        lines.append("• \(L10n.Chat.today): **\(date)**")
        return lines.joined(separator: "\n")
    }

    // MARK: - Cancellation

    static func operationCancelled() -> String {
        "{{dim:\(localizedString("chat.operation_cancelled"))}}"
    }

    // MARK: - Processing

    static func processingTransaction() -> String { L10n.Send.signing }

    // MARK: - Hide / Show Balance

    static func balanceHidden() -> String {
        "{{green:\(localizedString("chat.balance_hidden"))}}"
    }

    static func balanceShown() -> String {
        "{{green:\(localizedString("chat.balance_shown"))}}"
    }

    // MARK: - Refresh

    static func walletRefreshing() -> String {
        "{{dim:\(localizedString("chat.wallet_refreshing"))}}"
    }

    static func walletRefreshed() -> String {
        "{{green:\(localizedString("chat.wallet_refreshed"))}}"
    }

    // MARK: - Settings

    static func openingSettings() -> String {
        "{{green:\(L10n.Settings.title)...}}"
    }
}
