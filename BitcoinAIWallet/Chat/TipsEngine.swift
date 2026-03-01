// MARK: - TipsEngine.swift
// Bitcoin AI Wallet
//
// Manages a rotating pool of command-discovery tips.
// Every tip teaches the user a command they can type — never Bitcoin education.
// Tips are contextual: related to what the user just did, but show a different command.
//
// Platform: iOS 17.0+
// Framework: Foundation

import Foundation

// MARK: - TipsEngine

/// Manages rotating command-discovery tips that appear below AI responses.
///
/// Tips help the user discover what they can SAY to the AI.
/// Never teaches Bitcoin concepts — only shows commands.
///
/// ```swift
/// let engine = TipsEngine()
/// let tip = engine.nextTip(for: .send)
/// ```
final class TipsEngine {

    // MARK: - State

    /// Tips that haven't been shown in the current cycle.
    private var remainingTips: [TipItem] = []

    /// The ID of the last tip shown, used to prevent consecutive repeats.
    private var lastTipID: String?

    /// All available tips.
    private let allTips: [TipItem]

    // MARK: - Initialization

    init() {
        self.allTips = Self.buildAllTips()
        self.remainingTips = allTips.shuffled()
    }

    // MARK: - Public API

    /// Returns the next tip, guaranteed not to repeat the previous one.
    func nextTip() -> TipItem {
        if remainingTips.isEmpty {
            remainingTips = allTips.shuffled()
        }

        if let index = remainingTips.firstIndex(where: { $0.id != lastTipID }) {
            let tip = remainingTips.remove(at: index)
            lastTipID = tip.id
            return tip
        }

        let tip = remainingTips.removeFirst()
        lastTipID = tip.id
        return tip
    }

    /// Returns a contextual tip from the given category, falling back to any tip.
    func nextTip(category: TipCategory) -> TipItem {
        let filtered = allTips.filter { $0.category == category && $0.id != lastTipID }
        if let tip = filtered.randomElement() {
            lastTipID = tip.id
            return tip
        }
        return nextTip()
    }

    /// Maps a wallet intent to the best tip category for contextual relevance.
    /// Returns a tip from a DIFFERENT feature area so the user discovers new commands.
    func contextualTip(for intent: WalletIntent) -> TipItem {
        let category = suggestedCategory(for: intent)
        return nextTip(category: category)
    }

    // MARK: - Intent → Category Mapping

    /// Maps what the user just did to a related-but-different tip category.
    private func suggestedCategory(for intent: WalletIntent) -> TipCategory {
        switch intent {
        case .send:             return .history   // just sent → "track transaction"
        case .receive:          return .sharing   // just received → "request amount"
        case .balance:          return .balance    // checked balance → "hide balance", "show UTXOs"
        case .history:          return .analytics  // viewed history → "export", "spent this month"
        case .feeEstimate:      return .fee        // checked fees → "alert when fees drop"
        case .price:            return .calculator // checked price → "convert 500 EUR to BTC"
        case .convertAmount:    return .price      // converted → "BTC price"
        case .hideBalance,
             .showBalance:      return .settings   // toggled balance → "dark mode", "language"
        case .refreshWallet:    return .balance    // refreshed → "show UTXOs", "balance in sats"
        case .newAddress:       return .address    // new address → "validate address"
        case .walletHealth:     return .security   // health check → "backup seed", "enable Face ID"
        case .networkStatus:    return .network    // network → "change server", "test connection"
        case .exportHistory:    return .analytics  // exported → "spent this month"
        case .bumpFee:          return .fee        // bumped fee → "mempool status"
        case .settings:         return .settings   // opened settings → more settings tips
        case .help:             return .general    // asked help → general discovery tips
        case .about:            return .general    // about → general tips
        case .utxoList:         return .send       // viewed UTXOs → "consolidate UTXOs"
        case .transactionDetail: return .history   // tx detail → "export history"
        case .greeting:         return .general    // greeting → general discovery
        case .explain:          return .education  // explain → education tips
        case .unknown:          return .general    // unknown → help them discover commands
        case .confirmAction,
             .cancelAction:     return .general
        }
    }

    // MARK: - Tip Definitions

    private static func buildAllTips() -> [TipItem] {
        var tips: [TipItem] = []

        // MARK: Send Tips
        tips.append(TipItem(id: "snd_1", icon: "dollarsign.arrow.circlepath", titleKey: "tip.snd_1.title", bodyKey: "tip.snd_1.body", category: .send))
        tips.append(TipItem(id: "snd_2", icon: "arrow.up.circle", titleKey: "tip.snd_2.title", bodyKey: "tip.snd_2.body", category: .send))
        tips.append(TipItem(id: "snd_3", icon: "minus.circle", titleKey: "tip.snd_3.title", bodyKey: "tip.snd_3.body", category: .send))
        tips.append(TipItem(id: "snd_4", icon: "number", titleKey: "tip.snd_4.title", bodyKey: "tip.snd_4.body", category: .send))
        tips.append(TipItem(id: "snd_5", icon: "bolt", titleKey: "tip.snd_5.title", bodyKey: "tip.snd_5.body", category: .send))
        tips.append(TipItem(id: "snd_6", icon: "arrow.counterclockwise", titleKey: "tip.snd_6.title", bodyKey: "tip.snd_6.body", category: .send))

        // MARK: Receive Tips
        tips.append(TipItem(id: "rcv_1", icon: "arrow.down.circle", titleKey: "tip.rcv_1.title", bodyKey: "tip.rcv_1.body", category: .receive))
        tips.append(TipItem(id: "rcv_2", icon: "qrcode", titleKey: "tip.rcv_2.title", bodyKey: "tip.rcv_2.body", category: .receive))
        tips.append(TipItem(id: "rcv_3", icon: "square.and.arrow.up", titleKey: "tip.rcv_3.title", bodyKey: "tip.rcv_3.body", category: .receive))
        tips.append(TipItem(id: "rcv_4", icon: "plus.circle", titleKey: "tip.rcv_4.title", bodyKey: "tip.rcv_4.body", category: .receive))
        tips.append(TipItem(id: "rcv_5", icon: "banknote", titleKey: "tip.rcv_5.title", bodyKey: "tip.rcv_5.body", category: .receive))

        // MARK: Balance Tips
        tips.append(TipItem(id: "bal_1", icon: "eye.slash", titleKey: "tip.bal_1.title", bodyKey: "tip.bal_1.body", category: .balance))
        tips.append(TipItem(id: "bal_2", icon: "rectangle.stack", titleKey: "tip.bal_2.title", bodyKey: "tip.bal_2.body", category: .balance))
        tips.append(TipItem(id: "bal_3", icon: "number", titleKey: "tip.bal_3.title", bodyKey: "tip.bal_3.body", category: .balance))
        tips.append(TipItem(id: "bal_4", icon: "eurosign.circle", titleKey: "tip.bal_4.title", bodyKey: "tip.bal_4.body", category: .balance))
        tips.append(TipItem(id: "bal_5", icon: "arrow.clockwise", titleKey: "tip.bal_5.title", bodyKey: "tip.bal_5.body", category: .balance))
        tips.append(TipItem(id: "bal_6", icon: "arrow.triangle.merge", titleKey: "tip.bal_6.title", bodyKey: "tip.bal_6.body", category: .balance))

        // MARK: History Tips
        tips.append(TipItem(id: "hst_1", icon: "line.3.horizontal.decrease", titleKey: "tip.hst_1.title", bodyKey: "tip.hst_1.body", category: .history))
        tips.append(TipItem(id: "hst_2", icon: "list.number", titleKey: "tip.hst_2.title", bodyKey: "tip.hst_2.body", category: .history))
        tips.append(TipItem(id: "hst_3", icon: "clock", titleKey: "tip.hst_3.title", bodyKey: "tip.hst_3.body", category: .history))
        tips.append(TipItem(id: "hst_4", icon: "magnifyingglass", titleKey: "tip.hst_4.title", bodyKey: "tip.hst_4.body", category: .history))
        tips.append(TipItem(id: "hst_5", icon: "square.and.arrow.up", titleKey: "tip.hst_5.title", bodyKey: "tip.hst_5.body", category: .history))
        tips.append(TipItem(id: "hst_6", icon: "doc.text", titleKey: "tip.hst_6.title", bodyKey: "tip.hst_6.body", category: .history))

        // MARK: Fee Tips
        tips.append(TipItem(id: "fee_1", icon: "gauge.medium", titleKey: "tip.fee_1.title", bodyKey: "tip.fee_1.body", category: .fee))
        tips.append(TipItem(id: "fee_2", icon: "bell", titleKey: "tip.fee_2.title", bodyKey: "tip.fee_2.body", category: .fee))
        tips.append(TipItem(id: "fee_3", icon: "arrow.up.right", titleKey: "tip.fee_3.title", bodyKey: "tip.fee_3.body", category: .fee))
        tips.append(TipItem(id: "fee_4", icon: "slider.horizontal.3", titleKey: "tip.fee_4.title", bodyKey: "tip.fee_4.body", category: .fee))
        tips.append(TipItem(id: "fee_5", icon: "waveform.path", titleKey: "tip.fee_5.title", bodyKey: "tip.fee_5.body", category: .fee))

        // MARK: Settings Tips
        tips.append(TipItem(id: "set_1", icon: "moon.fill", titleKey: "tip.set_1.title", bodyKey: "tip.set_1.body", category: .settings))
        tips.append(TipItem(id: "set_2", icon: "globe", titleKey: "tip.set_2.title", bodyKey: "tip.set_2.body", category: .settings))
        tips.append(TipItem(id: "set_3", icon: "eurosign.circle", titleKey: "tip.set_3.title", bodyKey: "tip.set_3.body", category: .settings))
        tips.append(TipItem(id: "set_4", icon: "number", titleKey: "tip.set_4.title", bodyKey: "tip.set_4.body", category: .settings))
        tips.append(TipItem(id: "set_5", icon: "gearshape", titleKey: "tip.set_5.title", bodyKey: "tip.set_5.body", category: .settings))

        // MARK: Security Tips
        tips.append(TipItem(id: "sec_1", icon: "heart.text.square", titleKey: "tip.sec_1.title", bodyKey: "tip.sec_1.body", category: .security))
        tips.append(TipItem(id: "sec_2", icon: "doc.on.doc", titleKey: "tip.sec_2.title", bodyKey: "tip.sec_2.body", category: .security))
        tips.append(TipItem(id: "sec_3", icon: "faceid", titleKey: "tip.sec_3.title", bodyKey: "tip.sec_3.body", category: .security))
        tips.append(TipItem(id: "sec_4", icon: "lock", titleKey: "tip.sec_4.title", bodyKey: "tip.sec_4.body", category: .security))
        tips.append(TipItem(id: "sec_5", icon: "lock.rotation", titleKey: "tip.sec_5.title", bodyKey: "tip.sec_5.body", category: .security))
        tips.append(TipItem(id: "sec_6", icon: "signature", titleKey: "tip.sec_6.title", bodyKey: "tip.sec_6.body", category: .security))

        // MARK: Analytics Tips
        tips.append(TipItem(id: "anl_1", icon: "chart.bar", titleKey: "tip.anl_1.title", bodyKey: "tip.anl_1.body", category: .analytics))
        tips.append(TipItem(id: "anl_2", icon: "arrow.down.circle", titleKey: "tip.anl_2.title", bodyKey: "tip.anl_2.body", category: .analytics))
        tips.append(TipItem(id: "anl_3", icon: "arrow.up.arrow.down", titleKey: "tip.anl_3.title", bodyKey: "tip.anl_3.body", category: .analytics))
        tips.append(TipItem(id: "anl_4", icon: "flame", titleKey: "tip.anl_4.title", bodyKey: "tip.anl_4.body", category: .analytics))
        tips.append(TipItem(id: "anl_5", icon: "gauge.medium", titleKey: "tip.anl_5.title", bodyKey: "tip.anl_5.body", category: .analytics))

        // MARK: Calculator Tips
        tips.append(TipItem(id: "cal_1", icon: "equal.circle", titleKey: "tip.cal_1.title", bodyKey: "tip.cal_1.body", category: .calculator))
        tips.append(TipItem(id: "cal_2", icon: "dollarsign.arrow.circlepath", titleKey: "tip.cal_2.title", bodyKey: "tip.cal_2.body", category: .calculator))
        tips.append(TipItem(id: "cal_3", icon: "exclamationmark.circle", titleKey: "tip.cal_3.title", bodyKey: "tip.cal_3.body", category: .calculator))
        tips.append(TipItem(id: "cal_4", icon: "scalemass", titleKey: "tip.cal_4.title", bodyKey: "tip.cal_4.body", category: .calculator))

        // MARK: Price Tips
        tips.append(TipItem(id: "prc_1", icon: "chart.line.uptrend.xyaxis", titleKey: "tip.prc_1.title", bodyKey: "tip.prc_1.body", category: .price))
        tips.append(TipItem(id: "prc_2", icon: "dollarsign.arrow.circlepath", titleKey: "tip.prc_2.title", bodyKey: "tip.prc_2.body", category: .price))
        tips.append(TipItem(id: "prc_3", icon: "eurosign.circle", titleKey: "tip.prc_3.title", bodyKey: "tip.prc_3.body", category: .price))
        tips.append(TipItem(id: "prc_4", icon: "bitcoinsign.circle", titleKey: "tip.prc_4.title", bodyKey: "tip.prc_4.body", category: .price))

        // MARK: Network Tips
        tips.append(TipItem(id: "net_1", icon: "server.rack", titleKey: "tip.net_1.title", bodyKey: "tip.net_1.body", category: .network))
        tips.append(TipItem(id: "net_2", icon: "antenna.radiowaves.left.and.right", titleKey: "tip.net_2.title", bodyKey: "tip.net_2.body", category: .network))
        tips.append(TipItem(id: "net_3", icon: "info.circle", titleKey: "tip.net_3.title", bodyKey: "tip.net_3.body", category: .network))

        // MARK: Address Tips
        tips.append(TipItem(id: "adr_1", icon: "doc.text.magnifyingglass", titleKey: "tip.adr_1.title", bodyKey: "tip.adr_1.body", category: .address))
        tips.append(TipItem(id: "adr_2", icon: "questionmark.circle", titleKey: "tip.adr_2.title", bodyKey: "tip.adr_2.body", category: .address))
        tips.append(TipItem(id: "adr_3", icon: "doc.on.clipboard", titleKey: "tip.adr_3.title", bodyKey: "tip.adr_3.body", category: .address))

        // MARK: Sharing Tips
        tips.append(TipItem(id: "shr_1", icon: "qrcode", titleKey: "tip.shr_1.title", bodyKey: "tip.shr_1.body", category: .sharing))
        tips.append(TipItem(id: "shr_2", icon: "square.and.arrow.up", titleKey: "tip.shr_2.title", bodyKey: "tip.shr_2.body", category: .sharing))
        tips.append(TipItem(id: "shr_3", icon: "doc.on.doc", titleKey: "tip.shr_3.title", bodyKey: "tip.shr_3.body", category: .sharing))

        // MARK: General Tips
        tips.append(TipItem(id: "gen_1", icon: "text.bubble", titleKey: "tip.gen_1.title", bodyKey: "tip.gen_1.body", category: .general))
        tips.append(TipItem(id: "gen_2", icon: "globe", titleKey: "tip.gen_2.title", bodyKey: "tip.gen_2.body", category: .general))
        tips.append(TipItem(id: "gen_3", icon: "questionmark.circle", titleKey: "tip.gen_3.title", bodyKey: "tip.gen_3.body", category: .general))
        tips.append(TipItem(id: "gen_4", icon: "doc.text", titleKey: "tip.gen_4.title", bodyKey: "tip.gen_4.body", category: .general))
        tips.append(TipItem(id: "gen_5", icon: "hand.wave", titleKey: "tip.gen_5.title", bodyKey: "tip.gen_5.body", category: .general))

        // MARK: Education Tips (only shown after education commands)
        tips.append(TipItem(id: "edu_1", icon: "book", titleKey: "tip.edu_1.title", bodyKey: "tip.edu_1.body", category: .education))
        tips.append(TipItem(id: "edu_2", icon: "book", titleKey: "tip.edu_2.title", bodyKey: "tip.edu_2.body", category: .education))
        tips.append(TipItem(id: "edu_3", icon: "book", titleKey: "tip.edu_3.title", bodyKey: "tip.edu_3.body", category: .education))
        tips.append(TipItem(id: "edu_4", icon: "book", titleKey: "tip.edu_4.title", bodyKey: "tip.edu_4.body", category: .education))
        tips.append(TipItem(id: "edu_5", icon: "book", titleKey: "tip.edu_5.title", bodyKey: "tip.edu_5.body", category: .education))

        return tips
    }
}
