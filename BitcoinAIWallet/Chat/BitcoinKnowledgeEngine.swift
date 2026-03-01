// MARK: - BitcoinKnowledgeEngine.swift
// Bitcoin AI Wallet
//
// Answers Bitcoin knowledge questions locally on-device.
// Covers core concepts, technical details, and history from 2009-2026.
// No LLM API calls — all knowledge is baked in.
//
// Platform: iOS 17.0+

import Foundation

final class BitcoinKnowledgeEngine {

    // MARK: - V18 Public API

    /// Returns a knowledge response if the input is a Bitcoin knowledge question, nil otherwise.
    /// Only answers questions/explain requests — NOT wallet action commands.
    func answer(meaning: SentenceMeaning, input: String) -> String? {
        guard meaning.type == .question || isExplainRequest(meaning) else { return nil }
        guard isNotWalletAction(meaning) else { return nil }
        let normalized = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return matchKnowledge(normalized)
    }

    // MARK: - Legacy Public API

    /// Returns a knowledge response if the input is a Bitcoin question, nil otherwise.
    func answer(_ input: String) -> String? {
        let normalized = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard isQuestionAboutBitcoin(normalized) else { return nil }
        return matchKnowledge(normalized)
    }

    // MARK: - V18 Helpers

    private func isExplainRequest(_ m: SentenceMeaning) -> Bool {
        if case .explain = m.action { return true }
        return false
    }

    private func isNotWalletAction(_ m: SentenceMeaning) -> Bool {
        guard let action = m.action else { return true }
        switch action {
        case .send, .receive, .checkBalance, .showFees, .showPrice,
             .showHistory, .showAddress, .showUTXO, .confirm, .cancel,
             .export, .bump, .refresh, .hide, .show, .generate, .convert:
            return false
        default:
            return true
        }
    }

    // MARK: - Question Detection

    private func isQuestionAboutBitcoin(_ text: String) -> Bool {
        let questionStarters = [
            "what is", "what's", "what are",
            "how does", "how do", "how is", "how many",
            "explain", "tell me about", "teach me",
            "who is", "who was", "who created",
            "when was", "when did",
            "why"
        ]
        let hasQuestionStarter = questionStarters.contains { text.contains($0) }
        return hasQuestionStarter && containsBitcoinTopic(text)
    }

    private func containsBitcoinTopic(_ text: String) -> Bool {
        let topics = [
            "bitcoin", "btc", "satoshi", "blockchain", "block",
            "mining", "halving", "utxo", "segwit", "taproot",
            "lightning", "mempool", "hash", "proof of work", "pow",
            "difficulty", "node", "seed phrase", "mnemonic", "bip39",
            "bip44", "hd wallet", "private key", "public key",
            "address", "transaction", "confirmations", "fee",
            "sat/vb", "block reward", "genesis block", "whitepaper",
            "decentralized", "cold storage", "hardware wallet",
            "multisig", "rbf", "sat", "sats", "satoshi"
        ]
        return topics.contains { text.contains($0) }
    }

    // MARK: - Knowledge Base

    private func matchKnowledge(_ text: String) -> String? {
        // Order matters: more specific matches first to avoid
        // broad triggers like "block" shadowing "blockchain".

        if matches(text, ["who is satoshi", "who was satoshi", "who created bitcoin", "satoshi nakamoto"]) {
            return """
            **Satoshi Nakamoto** is the pseudonymous creator of Bitcoin. \
            They published the Bitcoin whitepaper on **October 31, 2008** and mined the \
            **genesis block** on **January 3, 2009**, embedding the headline \
            "Chancellor on brink of second bailout for banks." Satoshi gradually \
            disappeared from public communication in **2011**, and the roughly \
            **1 million BTC** believed to belong to them has never moved. \
            Their true identity remains one of the greatest mysteries in technology.
            """
        }

        if matches(text, ["what is a utxo", "what's a utxo", "what are utxo", "explain utxo"]) {
            return """
            A **UTXO** (Unspent Transaction Output) is like a discrete coin in your wallet. \
            When you receive Bitcoin, you get a UTXO; when you spend it, the entire UTXO is \
            consumed and any excess is returned to you as **change**. Your wallet balance is \
            simply the sum of all your UTXOs. This model is what makes Bitcoin's accounting \
            transparent and auditable — say **utxo** to see yours.
            """
        }

        if matches(text, ["what is segwit", "what's segwit", "explain segwit", "segregated witness"]) {
            return """
            **Segregated Witness (SegWit)** activated in **August 2017**. It separates \
            (segregates) transaction signatures (witness data) from the main transaction, \
            fixing the **transaction malleability** bug and increasing the effective block \
            capacity to roughly **4 MB of weight**. SegWit introduced **bc1q** addresses \
            and delivers **30-40% fee savings** compared to legacy transactions.
            """
        }

        if matches(text, ["what is taproot", "what's taproot", "explain taproot"]) {
            return """
            **Taproot** activated in **November 2021** at block **709,632**. It introduces \
            **Schnorr signatures**, which improve privacy by making complex multisig and \
            smart-contract spends look identical to simple single-key transactions on-chain. \
            Taproot uses **bc1p** addresses and opens the door to more sophisticated \
            smart contracts on Bitcoin while keeping fees low.
            """
        }

        if matches(text, ["what is lightning", "what's lightning", "lightning network", "explain lightning"]) {
            return """
            The **Lightning Network** is a **Layer 2** protocol built on top of Bitcoin. \
            It enables **instant, nearly-free** payments by opening payment channels between \
            participants and settling transactions **off-chain**. Payments route through a \
            network of channels and settle in **milliseconds**, making Bitcoin practical \
            for everyday purchases like coffee.
            """
        }

        if matches(text, ["what is mining", "what's mining", "how does mining", "explain mining"]) {
            return """
            **Mining** is the process of securing the Bitcoin network by solving \
            cryptographic puzzles using **SHA-256 ASICs**. Miners compete to find a valid \
            block hash, and the winner earns the **block reward** — currently **3.125 BTC** \
            after the **April 2024 halving**. The network automatically adjusts mining \
            **difficulty** every **2,016 blocks** (~2 weeks) to maintain the ~10-minute \
            block target.
            """
        }

        if matches(text, ["what is halving", "what's halving", "what is the halving", "explain halving", "bitcoin halving"]) {
            return """
            The **halving** cuts the block reward in half every **210,000 blocks** (~4 years), \
            enforcing Bitcoin's fixed supply schedule:\n\n\
            - **2009** — 50 BTC\n\
            - **2012** — 25 BTC\n\
            - **2016** — 12.5 BTC\n\
            - **2020** — 6.25 BTC\n\
            - **2024** — 3.125 BTC\n\
            - **~2028** — 1.5625 BTC\n\n\
            The last Bitcoin is expected to be mined around **2140**.
            """
        }

        if matches(text, ["what is a seed phrase", "what's a seed phrase", "explain seed phrase",
                          "what is mnemonic", "what's mnemonic", "explain mnemonic",
                          "what is bip39", "explain bip39"]) {
            return """
            A **seed phrase** (also called a mnemonic) is a set of **12 or 24 words** that \
            encodes your entire wallet. Every private key and address is mathematically \
            derived from this seed. You should **NEVER share** your seed phrase with anyone — \
            whoever has it controls all your funds. In this app, your seed is protected by \
            the **Secure Enclave** on your device.
            """
        }

        if matches(text, ["what is mempool", "what's mempool", "what is the mempool", "explain mempool"]) {
            return """
            The **mempool** (memory pool) is a waiting area where unconfirmed transactions \
            sit until miners include them in a block. Miners typically prioritize transactions \
            with the **highest fees**. When the mempool is full, fees rise as users compete \
            for limited block space. Say **fees** to check current fee rates.
            """
        }

        if matches(text, ["what is rbf", "what's rbf", "explain rbf", "replace by fee", "replace-by-fee"]) {
            return """
            **RBF (Replace-By-Fee)** lets you increase the fee on an **unconfirmed** \
            transaction so miners pick it up faster. You broadcast a new version of the \
            same transaction with a higher fee, and the old one is replaced. This wallet \
            enables RBF by default to give you control over confirmation speed.
            """
        }

        if matches(text, ["what is a sat", "what's a sat", "what is a satoshi",
                          "what are sats", "explain sat", "explain sats",
                          "smallest unit"]) {
            return """
            A **satoshi** (sat) is the smallest unit of Bitcoin: **1 BTC = 100,000,000 sats**. \
            Thinking in sats makes small amounts more intuitive — instead of 0.0005 BTC, \
            you can say **50,000 sats**. You can send in sats too: \
            "send 50000 sats to bc1q..."
            """
        }

        if matches(text, ["what is a private key", "what's a private key", "explain private key"]) {
            return """
            A **private key** is a **256-bit random number** that proves ownership of \
            Bitcoin and is used to **sign transactions**. It is derived from your seed \
            phrase through the HD wallet derivation path. Never expose your private key — \
            in this app it is stored in the device's **Secure Enclave** and never leaves it.
            """
        }

        if matches(text, ["what is a public key", "what's a public key", "explain public key"]) {
            return """
            A **public key** is mathematically derived from your private key using elliptic \
            curve cryptography (**secp256k1**). It can be shared freely and is used to \
            generate your Bitcoin **addresses**. Anyone can verify a signature was made by \
            the corresponding private key without ever seeing it.
            """
        }

        if matches(text, ["what is a block", "what's a block", "explain block",
                          "what is the genesis block", "genesis block"]) {
            return """
            A **block** is a bundle of transactions grouped together with a header containing \
            the previous block hash, a **nonce**, a **timestamp**, and a Merkle root. Blocks \
            are **1-4 MB** in size and are produced roughly every **10 minutes**. The very \
            first block — the **genesis block** — was mined by Satoshi Nakamoto on \
            **January 3, 2009**.
            """
        }

        if matches(text, ["what is blockchain", "what's blockchain", "what's a blockchain",
                          "what is a blockchain", "explain blockchain"]) {
            return """
            The **blockchain** is Bitcoin's public ledger — an immutable chain of blocks \
            where each block references the cryptographic hash of the one before it. A new \
            block is added roughly every **10 minutes**, and every full **node** on the \
            network stores and validates the entire chain, making it virtually impossible \
            to alter past transactions.
            """
        }

        if matches(text, ["how many bitcoin", "total supply", "21 million", "how much bitcoin",
                          "how many btc", "bitcoin supply"]) {
            return """
            Bitcoin has a hard cap of **21,000,000 BTC**. As of early 2026, roughly \
            **19.8 million** have been mined, leaving about **1.2 million** still to be \
            issued through mining rewards. An estimated **3-4 million BTC** are believed \
            to be permanently lost (including Satoshi's coins), making Bitcoin even more \
            scarce and **deflationary** by nature.
            """
        }

        if matches(text, ["what is confirmation", "what are confirmations", "explain confirmations",
                          "what's a confirmation", "how many confirmations"]) {
            return """
            A **confirmation** is each new block added on top of the block that contains \
            your transaction. **6 confirmations** (~60 minutes) is traditionally considered \
            fully confirmed, but **1-3 confirmations** are usually sufficient for smaller \
            amounts. The more confirmations, the harder it becomes to reverse the transaction.
            """
        }

        if matches(text, ["what is cold storage", "what's cold storage", "explain cold storage",
                          "what is a hardware wallet", "what's a hardware wallet",
                          "explain hardware wallet"]) {
            return """
            **Cold storage** means keeping your private keys completely **offline**, away \
            from internet-connected devices. Popular hardware wallets include **Ledger**, \
            **Trezor**, and **ColdCard** — they sign transactions inside a secure chip \
            without exposing keys. Note: this app is a **hot wallet** (keys are on your \
            phone), so consider cold storage for large holdings.
            """
        }

        if matches(text, ["what is multisig", "what's multisig", "explain multisig",
                          "multi-sig", "multi sig"]) {
            return """
            **Multisig** (multi-signature) requires **multiple private keys** to authorize \
            a transaction — common setups are **2-of-3** or **3-of-5**. This protects \
            against a single point of failure: no single lost or stolen key can compromise \
            your funds. With **Taproot**, multisig transactions look identical to regular \
            single-key transactions on-chain, improving both privacy and efficiency.
            """
        }

        if matches(text, ["what is bitcoin", "what's bitcoin", "explain bitcoin", "tell me about bitcoin",
                          "teach me about bitcoin"]) {
            return """
            **Bitcoin** is a **decentralized digital currency** created by the pseudonymous \
            **Satoshi Nakamoto** in **2009**. It operates on a peer-to-peer network with no \
            central authority, using proof-of-work mining to secure transactions. Bitcoin has \
            a hard cap of **21 million coins**, making it scarce by design — often called \
            "digital gold."
            """
        }

        return nil
    }

    // MARK: - Helpers

    private func matches(_ text: String, _ triggers: [String]) -> Bool {
        triggers.contains { text.contains($0) }
    }
}
