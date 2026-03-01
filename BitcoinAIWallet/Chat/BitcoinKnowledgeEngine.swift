// MARK: - BitcoinKnowledgeEngine.swift
// Bitcoin AI Wallet
//
// Answers Bitcoin knowledge questions locally on-device.
// Covers core concepts, technical details, wallet & security,
// transactions, culture & history, and network topics from 2009-2026.
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
        let normalized = normalize(input)
        return matchKnowledge(normalized)
    }

    // MARK: - Legacy Public API

    /// Returns a knowledge response if the input is a Bitcoin question, nil otherwise.
    func answer(_ input: String) -> String? {
        let normalized = normalize(input)
        guard isQuestionAboutBitcoin(normalized) else { return nil }
        return matchKnowledge(normalized)
    }

    /// Returns true if the engine can provide an answer for this input.
    func canAnswer(_ input: String) -> Bool {
        let normalized = normalize(input)
        guard isQuestionAboutBitcoin(normalized) else { return false }
        return matchKnowledge(normalized) != nil
    }

    /// Returns a knowledge response for a specific topic string (e.g., from WalletIntent.explain).
    func answer(topic: String) -> String? {
        let normalized = normalize(topic)
        // Try matching directly as a topic keyword first
        if let direct = matchByTopic(normalized) { return direct }
        // Fall back to full knowledge matching
        return matchKnowledge(normalized)
    }

    /// Returns a knowledge response for a SentenceMeaning subject/object pair.
    func answer(for meaning: SentenceMeaning) -> String? {
        // Try to extract a topic from the meaning's object
        if let obj = meaning.object {
            switch obj {
            case .balance:
                return knowledgeResponses["balance"]
            case .fee:
                return knowledgeResponses["fees"]
            case .address:
                return knowledgeResponses["address"]
            case .transaction:
                return knowledgeResponses["confirmation"]
            case .price:
                return knowledgeResponses["value"]
            case .wallet:
                return knowledgeResponses["hd_wallet"]
            case .network:
                return knowledgeResponses["node"]
            case .utxo:
                return knowledgeResponses["utxo"]
            case .history:
                return knowledgeResponses["blockchain"]
            case .specific(let topic):
                return answer(topic: topic)
            case .amount, .lastMentioned:
                return nil
            }
        }
        return nil
    }

    // MARK: - V18 Helpers

    private func isExplainRequest(_ m: SentenceMeaning) -> Bool {
        if case .explain = m.action { return true }
        return false
    }

    private func isNotWalletAction(_ m: SentenceMeaning) -> Bool {
        guard let action = m.action else { return true }
        switch action {
        // Knowledge-friendly actions: always allow through
        case .explain, .help, .about:
            return true
        // Pure wallet commands: never knowledge
        case .send, .receive, .confirm, .cancel, .export, .backup, .bump,
             .refresh, .hide, .show, .generate, .convert, .undo, .repeatLast,
             .settings, .modify, .compare, .select:
            return false
        // Data display actions: allow if it's a "what is" question, block if it's a command
        case .checkBalance, .showFees, .showPrice, .showHistory,
             .showAddress, .showUTXO, .showHealth, .showNetwork:
            return m.type == .question
        }
    }

    // MARK: - Normalization

    private func normalize(_ text: String) -> String {
        text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
    }

    // MARK: - Question Detection

    private func isQuestionAboutBitcoin(_ text: String) -> Bool {
        let questionStarters = [
            "what is", "what's", "what are", "what was",
            "how does", "how do", "how is", "how many", "how long",
            "explain", "tell me about", "teach me", "describe",
            "who is", "who was", "who created", "who invented",
            "when was", "when did", "when is",
            "why is", "why does", "why do", "why are", "why",
            "can you explain", "can you tell me",
            "define", "meaning of",
            "is bitcoin", "is btc", "are bitcoin",
            "do i need", "should i"
        ]
        let hasQuestionStarter = questionStarters.contains { text.contains($0) }
        return hasQuestionStarter && containsBitcoinTopic(text)
    }

    private func containsBitcoinTopic(_ text: String) -> Bool {
        let topics = [
            // Core
            "bitcoin", "btc", "satoshi", "blockchain", "block chain",
            "mining", "miner", "mine",
            // Economics
            "halving", "halvening", "supply", "inflation", "deflation",
            "valuable", "value", "worth", "scarce", "scarcity",
            // Technical
            "utxo", "unspent", "segwit", "segregated witness",
            "taproot", "schnorr",
            "lightning", "layer 2", "layer two", "l2",
            "mempool", "memory pool", "mem pool",
            "hash", "hashrate", "hash rate",
            "proof of work", "pow", "consensus",
            "difficulty", "difficulty adjustment",
            "node", "full node",
            "fork", "soft fork", "hard fork",
            // Wallet & Security
            "seed phrase", "recovery phrase", "mnemonic", "backup phrase",
            "bip39", "bip44", "bip49", "bip84", "bip86",
            "hd wallet", "hierarchical deterministic",
            "private key", "public key", "key pair",
            "address", "address type",
            "cold storage", "hardware wallet",
            "multisig", "multi-sig", "multi sig",
            "2fa", "two factor", "two-factor", "biometric",
            // Transactions
            "transaction", "confirmation", "confirmed",
            "fee", "sat/vb", "sats/vb", "fee rate",
            "block reward", "coinbase",
            "rbf", "replace by fee", "replace-by-fee",
            "change output", "change address",
            "dust", "dust limit",
            // Units
            "sat", "sats", "satoshi", "satoshis",
            // Culture & History
            "genesis block", "whitepaper", "white paper",
            "decentralized", "decentralization",
            "hodl", "holding", "diamond hands",
            "dca", "dollar cost", "dollar-cost",
            "whale", "whales",
            "not your keys", "not your coins",
            "block", "blocks"
        ]
        return topics.contains { text.contains($0) }
    }

    // MARK: - Knowledge Responses Dictionary

    /// All knowledge responses keyed by topic identifier.
    /// Used by both matchKnowledge (trigger-based) and answer(topic:) / answer(for:).
    private let knowledgeResponses: [String: String] = [

        // ── Core Concepts ──

        "bitcoin": """
            **Bitcoin** is a decentralized digital currency created by the pseudonymous \
            **Satoshi Nakamoto** in **2009**. It operates on a peer-to-peer network with no \
            central authority, using proof-of-work mining to secure transactions. With a hard \
            cap of **21 million coins**, it's designed to be scarce — often called "digital gold."
            """,

        "blockchain": """
            The **blockchain** is Bitcoin's public ledger — an immutable chain of blocks \
            where each block references the cryptographic hash of the one before it. Every \
            full **node** on the network stores and validates the entire chain, making it \
            virtually impossible to alter past transactions.
            """,

        "mining": """
            **Mining** is the process of securing the Bitcoin network by solving \
            cryptographic puzzles using **SHA-256 ASICs**. Miners compete to find a valid \
            block hash, and the winner earns the **block reward** — currently **3.125 BTC** \
            after the **April 2024 halving**. Difficulty adjusts every **2,016 blocks** \
            (~2 weeks) to maintain the ~10-minute block target.
            """,

        "block": """
            A **block** is a bundle of transactions grouped together with a header containing \
            the previous block hash, a **nonce**, a **timestamp**, and a Merkle root. Blocks \
            are **1-4 MB** in size and are produced roughly every **10 minutes**. The very \
            first block — the **genesis block** — was mined by Satoshi on **January 3, 2009**.
            """,

        "mempool": """
            The **mempool** (memory pool) is the waiting room for unconfirmed transactions. \
            Miners typically prioritize transactions with the **highest fees**. When the mempool \
            is congested, fees rise as users compete for limited block space. Say **fees** to \
            check current fee rates.
            """,

        // ── Halving & Economics ──

        "halving": """
            The **halving** cuts the block reward in half every **210,000 blocks** (~4 years), \
            enforcing Bitcoin's fixed supply schedule:\n\n\
            - **2009** — 50 BTC\n\
            - **2012** — 25 BTC\n\
            - **2016** — 12.5 BTC\n\
            - **2020** — 6.25 BTC\n\
            - **2024** — 3.125 BTC\n\
            - **~2028** — 1.5625 BTC\n\n\
            The last bitcoin is expected to be mined around **2140**.
            """,

        "value": """
            Bitcoin derives its value from **scarcity** (21 million cap), **decentralization** \
            (no single point of control), **censorship resistance** (no one can block your \
            transactions), and **global accessibility** (anyone with internet can use it). \
            It's often called "digital gold" because of these properties.
            """,

        "supply": """
            Bitcoin has a hard cap of **21,000,000 BTC**. As of early 2026, roughly \
            **19.8 million** have been mined, leaving about **1.2 million** still to be \
            issued through mining rewards. An estimated **3-4 million BTC** are believed \
            to be permanently lost, making the effective supply even more scarce.
            """,

        "inflation": """
            Bitcoin has a **predictable, decreasing inflation rate** — unlike fiat currencies \
            where central banks can print unlimited money. Each halving cuts new supply in half, \
            meaning Bitcoin's inflation rate trends toward zero. After all 21 million are mined \
            (~2140), there will be **zero new issuance**.
            """,

        // ── Technical ──

        "utxo": """
            A **UTXO** (Unspent Transaction Output) is like a discrete coin in your wallet. \
            When you receive Bitcoin, you get a UTXO; when you spend it, the entire UTXO is \
            consumed and any excess is returned to you as **change**. Your wallet balance is \
            simply the sum of all your UTXOs. Say **utxo** to see yours.
            """,

        "segwit": """
            **Segregated Witness (SegWit)** activated in **August 2017**. It separates \
            (segregates) transaction signatures (witness data) from the main transaction, \
            fixing the **transaction malleability** bug and increasing the effective block \
            capacity to roughly **4 MB of weight**. SegWit introduced **bc1q** addresses \
            and delivers **30-40% fee savings** compared to legacy transactions.
            """,

        "taproot": """
            **Taproot** activated in **November 2021** at block **709,632**. It introduces \
            **Schnorr signatures**, which improve privacy by making complex multisig and \
            smart-contract spends look identical to simple single-key transactions on-chain. \
            Taproot uses **bc1p** addresses and opens the door to more sophisticated \
            smart contracts on Bitcoin while keeping fees low.
            """,

        "fees": """
            Transaction **fees** are paid to miners to prioritize your transaction. They're \
            measured in **sats/vB** (satoshis per virtual byte). Higher fee = faster \
            confirmation. During congestion, fees spike; when the network is quiet, you can \
            send for just 1-2 sats/vB. Say **fees** to check current rates.
            """,

        "confirmation": """
            A **confirmation** is each new block added on top of the block that contains \
            your transaction. **6 confirmations** (~60 minutes) is traditionally considered \
            fully confirmed, but **1-3 confirmations** are usually sufficient for everyday \
            amounts. The more confirmations, the harder it becomes to reverse the transaction.
            """,

        "lightning": """
            The **Lightning Network** is a **Layer 2** protocol built on top of Bitcoin. \
            It enables **instant, nearly-free** payments by opening payment channels between \
            participants and settling transactions **off-chain**. Payments route through a \
            network of channels and settle in **milliseconds**, making Bitcoin practical \
            for everyday purchases like coffee.
            """,

        // ── Wallet & Security ──

        "seed_phrase": """
            A **seed phrase** (also called a recovery phrase or mnemonic) is a set of **12 or \
            24 words** that encodes your entire wallet. Every private key and address is \
            mathematically derived from this seed. **NEVER share** your seed phrase with \
            anyone — whoever has it controls all your funds. In this app, your seed is \
            protected by the **Secure Enclave** on your device.
            """,

        "private_key": """
            A **private key** is a **256-bit random number** that proves ownership of \
            Bitcoin and is used to **sign transactions**. It's derived from your seed \
            phrase through the HD wallet derivation path. Never expose your private key — \
            in this app it's stored in the device's **Secure Enclave** and never leaves it.
            """,

        "public_key": """
            A **public key** is mathematically derived from your private key using elliptic \
            curve cryptography (**secp256k1**). It can be shared freely and is used to \
            generate your Bitcoin **addresses**. Anyone can verify a signature was made by \
            the corresponding private key without ever seeing it.
            """,

        "address": """
            A Bitcoin **address** is a string of characters where you receive bitcoin — like \
            a bank account number, but more private. You can generate a fresh address for \
            every transaction to improve privacy. Say **receive** to get your current address.
            """,

        "address_types": """
            Bitcoin has four main address types:\n\n\
            - **Legacy (1...)** — original format, highest fees\n\
            - **P2SH (3...)** — wrapped SegWit, moderate fees\n\
            - **SegWit (bc1q...)** — native SegWit, lower fees\n\
            - **Taproot (bc1p...)** — newest format, lowest fees + best privacy\n\n\
            This wallet supports all four, with SegWit and Taproot as defaults.
            """,

        "hd_wallet": """
            An **HD wallet** (Hierarchical Deterministic) generates an unlimited number of \
            addresses from a single seed phrase. Each address is derived through a specific \
            path (like BIP84 for SegWit or BIP86 for Taproot). This means one backup \
            protects all your current and future addresses.
            """,

        "safety": """
            The Bitcoin **network itself** has never been hacked — it's secured by massive \
            computing power. Risks come from **losing your seed phrase**, falling for \
            **scams**, or using **insecure software**. This wallet protects your keys with \
            biometric authentication and the device's Secure Enclave.
            """,

        "2fa": """
            **Two-factor authentication (2FA)** adds an extra layer of security beyond a \
            password. This wallet uses **biometric authentication** (Face ID or Touch ID) \
            to authorize sensitive actions like sending bitcoin. Your seed never leaves \
            the device's Secure Enclave.
            """,

        "cold_storage": """
            **Cold storage** means keeping your private keys completely **offline**, away \
            from internet-connected devices. Popular hardware wallets include **Ledger**, \
            **Trezor**, and **ColdCard** — they sign transactions inside a secure chip \
            without exposing keys. Note: this app is a **hot wallet** (keys are on your \
            phone), so consider cold storage for large holdings.
            """,

        "multisig": """
            **Multisig** (multi-signature) requires **multiple private keys** to authorize \
            a transaction — common setups are **2-of-3** or **3-of-5**. This protects \
            against a single point of failure: no single lost or stolen key can compromise \
            your funds. With **Taproot**, multisig looks identical to regular single-key \
            transactions on-chain, improving both privacy and efficiency.
            """,

        // ── Transactions ──

        "tx_time": """
            Transaction speed depends on **fees** and **network congestion**. With a fast \
            fee, you'll typically get your first confirmation in about **10 minutes**. With \
            a low fee during congestion, it could take **hours or even days**. Say **fees** \
            to see current estimates.
            """,

        "wrong_address": """
            Bitcoin transactions are **irreversible**. Once confirmed, there's no way to \
            get the funds back unless the recipient voluntarily sends them. Always \
            **double-check the address** before confirming — this wallet shows a \
            confirmation screen for exactly this reason.
            """,

        "rbf": """
            **RBF (Replace-By-Fee)** lets you increase the fee on an **unconfirmed** \
            transaction so miners pick it up faster. You broadcast a new version of the \
            same transaction with a higher fee, and the old one is replaced. This wallet \
            enables RBF by default to give you control over confirmation speed.
            """,

        "change_output": """
            When you spend a UTXO, the **leftover amount** goes back to yourself as a \
            **change output** — like getting change from a $20 bill. Your wallet handles \
            this automatically, sending change to a fresh address in your wallet for \
            better privacy.
            """,

        "dust": """
            **Dust** refers to tiny amounts of bitcoin that are **too small to spend** \
            because the transaction fee would exceed the amount itself. The exact dust \
            limit depends on current fee rates, but it's typically a few hundred satoshis \
            for SegWit outputs.
            """,

        // ── Units ──

        "satoshi": """
            A **satoshi** (sat) is the smallest unit of Bitcoin: **1 BTC = 100,000,000 sats**. \
            Thinking in sats makes small amounts more intuitive — instead of 0.0005 BTC, \
            you can say **50,000 sats**. You can send in sats too: \
            "send 50000 sats to bc1q..."
            """,

        // ── Culture & History ──

        "satoshi_nakamoto": """
            **Satoshi Nakamoto** is the pseudonymous creator of Bitcoin. They published the \
            whitepaper on **October 31, 2008** and mined the **genesis block** on \
            **January 3, 2009**, embedding the headline "Chancellor on brink of second \
            bailout for banks." Satoshi disappeared from public communication in **2011**, \
            and the roughly **1 million BTC** believed to belong to them has never moved.
            """,

        "hodl": """
            **HODL** is crypto slang for holding bitcoin long-term without selling. It \
            originated from a famous typo of "hold" in a **2013 Bitcointalk forum post**. \
            The term has become a rallying cry for long-term believers who weather price \
            volatility rather than panic-selling.
            """,

        "dca": """
            **DCA (Dollar Cost Averaging)** means buying a fixed dollar amount of bitcoin \
            on a regular schedule — weekly, biweekly, or monthly — regardless of price. \
            This strategy reduces the impact of volatility and removes the stress of \
            trying to "time the market."
            """,

        "whale": """
            A **whale** is someone who holds a large amount of bitcoin — typically \
            **1,000+ BTC**. Their buys or sells can move the market noticeably. Whale \
            movements are closely watched by traders, though on-chain data makes large \
            transfers publicly visible.
            """,

        "not_your_keys": """
            **"Not your keys, not your coins"** is a core Bitcoin principle. If you keep \
            bitcoin on an exchange, the exchange controls the private keys — and if they \
            get hacked or go bankrupt, you could lose everything. This wallet gives \
            **you** full control of your keys.
            """,

        // ── Network ──

        "node": """
            A **node** is a computer running Bitcoin software that independently validates \
            and relays every transaction and block. More nodes mean a more **decentralized** \
            and **censorship-resistant** network. Anyone can run a node — it currently \
            requires about **600 GB** of disk space for the full blockchain.
            """,

        "difficulty": """
            **Difficulty** measures how hard it is to mine a new block. It automatically \
            adjusts every **2,016 blocks** (~2 weeks) to ensure blocks are produced roughly \
            every **10 minutes**, regardless of how much mining power joins or leaves \
            the network.
            """,

        "hashrate": """
            **Hashrate** is the total computing power securing the Bitcoin network, measured \
            in **hashes per second**. A higher hashrate means more miners competing, making \
            the network more secure against attacks. As of 2026, the network hashrate \
            exceeds **700 EH/s** (exahashes per second).
            """,

        "fork": """
            A **fork** is a change to the Bitcoin protocol rules. A **soft fork** is \
            backward-compatible (old nodes still work), like SegWit and Taproot. A **hard \
            fork** is not compatible and splits the chain — Bitcoin Cash (2017) is a \
            well-known example of a contentious hard fork.
            """,

        "balance": """
            Your Bitcoin **balance** is the sum of all your **UTXOs** (unspent transaction \
            outputs) across all address types. This wallet tracks Legacy, P2SH, SegWit, and \
            Taproot addresses automatically. Say **balance** to check yours.
            """,

        "whitepaper": """
            The **Bitcoin whitepaper**, titled "Bitcoin: A Peer-to-Peer Electronic Cash System," \
            was published by **Satoshi Nakamoto** on **October 31, 2008**. It's only **9 pages** \
            and elegantly describes how proof-of-work, cryptographic signatures, and a \
            distributed timestamp server solve the double-spending problem.
            """,

        "proof_of_work": """
            **Proof of Work (PoW)** is Bitcoin's consensus mechanism. Miners must expend \
            computational energy to find a valid block hash, proving they did "work." This \
            makes it extremely expensive to attack the network — you'd need more than 50% \
            of all mining power worldwide.
            """,

        "decentralization": """
            **Decentralization** means no single entity controls Bitcoin. Thousands of \
            **nodes** worldwide independently verify every transaction, and no government, \
            company, or individual can censor payments, inflate the supply, or shut it down. \
            This is Bitcoin's most important property.
            """,

        "bip": """
            A **BIP** (Bitcoin Improvement Proposal) is the formal process for suggesting \
            changes to Bitcoin. Important BIPs include **BIP39** (seed phrases), **BIP44** \
            (HD wallet paths), **BIP84** (native SegWit), **BIP86** (Taproot), and \
            **BIP141** (SegWit consensus rules).
            """,

        "double_spend": """
            A **double spend** is the attempt to spend the same bitcoin twice. Bitcoin's \
            proof-of-work and blockchain prevent this — once a transaction has enough \
            **confirmations**, reversing it would require more computing power than the \
            rest of the network combined. This is the core problem Bitcoin solves.
            """,

        "merkle_tree": """
            A **Merkle tree** is a data structure used in each block to efficiently summarize \
            all transactions. The **Merkle root** in the block header lets anyone verify a \
            transaction is included in a block without downloading the entire block — this \
            is how lightweight wallets (SPV) work.
            """,

        "coinbase_tx": """
            The **coinbase transaction** is the first transaction in every block. It's how \
            miners collect their **block reward** plus all transaction **fees**. Unlike \
            regular transactions, it has no inputs — the bitcoin is newly created. Coinbase \
            outputs require **100 confirmations** before they can be spent.
            """,
    ]

    // MARK: - Topic Matching

    /// Match by a bare topic keyword (used by answer(topic:)).
    private func matchByTopic(_ topic: String) -> String? {
        // Direct dictionary lookup
        if let response = knowledgeResponses[topic] { return response }

        // Map common topic strings to dictionary keys
        let topicMap: [String: String] = [
            "bitcoin": "bitcoin", "btc": "bitcoin",
            "blockchain": "blockchain", "block chain": "blockchain",
            "mining": "mining", "miner": "mining", "miners": "mining", "mine": "mining",
            "block": "block", "blocks": "block",
            "mempool": "mempool", "memory pool": "mempool", "mem pool": "mempool",
            "halving": "halving", "halvening": "halving", "the halving": "halving",
            "value": "value", "valuable": "value", "worth": "value",
            "supply": "supply", "21 million": "supply",
            "inflation": "inflation", "deflation": "inflation", "deflationary": "inflation",
            "utxo": "utxo", "utxos": "utxo", "unspent transaction output": "utxo",
            "segwit": "segwit", "segregated witness": "segwit", "seg wit": "segwit",
            "taproot": "taproot", "schnorr": "taproot",
            "fees": "fees", "fee": "fees", "transaction fees": "fees", "tx fees": "fees",
            "fee rate": "fees", "sat/vb": "fees", "sats/vb": "fees",
            "confirmation": "confirmation", "confirmations": "confirmation", "confirmed": "confirmation",
            "lightning": "lightning", "lightning network": "lightning", "layer 2": "lightning", "l2": "lightning",
            "seed phrase": "seed_phrase", "seed": "seed_phrase", "mnemonic": "seed_phrase",
            "recovery phrase": "seed_phrase", "backup phrase": "seed_phrase",
            "bip39": "seed_phrase", "bip 39": "seed_phrase",
            "private key": "private_key", "private keys": "private_key",
            "public key": "public_key", "public keys": "public_key",
            "address": "address", "addresses": "address", "bitcoin address": "address",
            "address types": "address_types", "address type": "address_types",
            "hd wallet": "hd_wallet", "hierarchical deterministic": "hd_wallet",
            "bip44": "hd_wallet", "bip84": "hd_wallet", "bip86": "hd_wallet", "bip49": "hd_wallet",
            "safety": "safety", "safe": "safety", "secure": "safety", "security": "safety",
            "2fa": "2fa", "two factor": "2fa", "biometric": "2fa", "face id": "2fa", "touch id": "2fa",
            "cold storage": "cold_storage", "hardware wallet": "cold_storage",
            "cold wallet": "cold_storage", "ledger": "cold_storage", "trezor": "cold_storage",
            "multisig": "multisig", "multi-sig": "multisig", "multi sig": "multisig",
            "multisignature": "multisig", "multi-signature": "multisig",
            "transaction time": "tx_time", "how long": "tx_time", "confirmation time": "tx_time",
            "wrong address": "wrong_address", "irreversible": "wrong_address",
            "rbf": "rbf", "replace by fee": "rbf", "replace-by-fee": "rbf", "fee bump": "rbf",
            "change output": "change_output", "change address": "change_output", "change": "change_output",
            "dust": "dust", "dust limit": "dust",
            "satoshi": "satoshi", "sat": "satoshi", "sats": "satoshi", "satoshis": "satoshi",
            "smallest unit": "satoshi",
            "satoshi nakamoto": "satoshi_nakamoto", "nakamoto": "satoshi_nakamoto",
            "creator": "satoshi_nakamoto", "who created": "satoshi_nakamoto",
            "hodl": "hodl", "hold": "hodl", "diamond hands": "hodl",
            "dca": "dca", "dollar cost averaging": "dca", "dollar cost": "dca",
            "dollar-cost averaging": "dca",
            "whale": "whale", "whales": "whale",
            "not your keys": "not_your_keys", "not your coins": "not_your_keys",
            "node": "node", "nodes": "node", "full node": "node",
            "difficulty": "difficulty", "difficulty adjustment": "difficulty",
            "hashrate": "hashrate", "hash rate": "hashrate", "hash power": "hashrate",
            "fork": "fork", "forks": "fork", "soft fork": "fork", "hard fork": "fork",
            "bitcoin cash": "fork",
            "balance": "balance",
            "whitepaper": "whitepaper", "white paper": "whitepaper",
            "proof of work": "proof_of_work", "pow": "proof_of_work",
            "decentralization": "decentralization", "decentralized": "decentralization",
            "bip": "bip", "bips": "bip", "bitcoin improvement proposal": "bip",
            "double spend": "double_spend", "double spending": "double_spend",
            "double-spend": "double_spend",
            "merkle tree": "merkle_tree", "merkle root": "merkle_tree", "merkle": "merkle_tree",
            "coinbase": "coinbase_tx", "coinbase transaction": "coinbase_tx",
            "block reward": "coinbase_tx",
        ]

        if let key = topicMap[topic] {
            return knowledgeResponses[key]
        }

        // Substring matching for partial topic strings
        for (keyword, key) in topicMap where topic.contains(keyword) {
            if let response = knowledgeResponses[key] {
                return response
            }
        }

        return nil
    }

    // MARK: - Knowledge Base (Trigger Matching)

    private func matchKnowledge(_ text: String) -> String? {
        // Order matters: more specific matches first to avoid
        // broad triggers like "block" shadowing "blockchain".

        // ── Culture & History ──

        if matches(text, ["who is satoshi", "who was satoshi", "who created bitcoin",
                          "satoshi nakamoto", "who invented bitcoin", "who made bitcoin",
                          "creator of bitcoin", "bitcoin creator"]) {
            return knowledgeResponses["satoshi_nakamoto"]
        }

        if matches(text, ["what is hodl", "what's hodl", "explain hodl",
                          "what does hodl mean", "meaning of hodl"]) {
            return knowledgeResponses["hodl"]
        }

        if matches(text, ["what is dca", "what's dca", "explain dca",
                          "dollar cost averaging", "dollar-cost averaging",
                          "what is dollar cost"]) {
            return knowledgeResponses["dca"]
        }

        if matches(text, ["what is a whale", "what's a whale", "explain whale",
                          "what are whales", "bitcoin whale"]) {
            return knowledgeResponses["whale"]
        }

        if matches(text, ["not your keys", "not your coins",
                          "what does not your keys mean"]) {
            return knowledgeResponses["not_your_keys"]
        }

        if matches(text, ["whitepaper", "white paper", "bitcoin paper",
                          "satoshi's paper", "original paper"]) {
            return knowledgeResponses["whitepaper"]
        }

        // ── Technical (specific first) ──

        if matches(text, ["what is a utxo", "what's a utxo", "what are utxo",
                          "explain utxo", "tell me about utxo", "what are utxos",
                          "unspent transaction output", "explain utxos"]) {
            return knowledgeResponses["utxo"]
        }

        if matches(text, ["what is segwit", "what's segwit", "explain segwit",
                          "segregated witness", "tell me about segwit",
                          "what's segwit about"]) {
            return knowledgeResponses["segwit"]
        }

        if matches(text, ["what is taproot", "what's taproot", "explain taproot",
                          "tell me about taproot", "what's taproot about",
                          "schnorr signature", "schnorr"]) {
            return knowledgeResponses["taproot"]
        }

        if matches(text, ["what is lightning", "what's lightning", "what is the lightning",
                          "what's the lightning", "lightning network",
                          "explain lightning", "explain the lightning",
                          "tell me about lightning", "tell me about the lightning",
                          "what is layer 2", "what's layer 2", "what is l2"]) {
            return knowledgeResponses["lightning"]
        }

        if matches(text, ["what is mining", "what's mining", "how does mining",
                          "explain mining", "tell me about mining",
                          "how do miners", "what do miners do",
                          "how bitcoin mining works"]) {
            return knowledgeResponses["mining"]
        }

        if matches(text, ["what is halving", "what's halving", "what is the halving",
                          "what's the halving", "explain halving", "explain the halving",
                          "bitcoin halving", "tell me about halving",
                          "tell me about the halving",
                          "what is halvening", "when is the halving",
                          "when is the next halving", "halving schedule"]) {
            return knowledgeResponses["halving"]
        }

        if matches(text, ["what is a seed phrase", "what's a seed phrase", "explain seed phrase",
                          "what is mnemonic", "what's mnemonic", "explain mnemonic",
                          "what is bip39", "explain bip39", "tell me about seed phrase",
                          "what is recovery phrase", "what's a recovery phrase",
                          "what is a backup phrase", "what are the 12 words",
                          "what are the 24 words"]) {
            return knowledgeResponses["seed_phrase"]
        }

        if matches(text, ["what is mempool", "what's mempool", "what is the mempool",
                          "what's the mempool", "what is a mempool", "what's a mempool",
                          "explain mempool", "explain the mempool",
                          "tell me about mempool", "tell me about the mempool",
                          "memory pool"]) {
            return knowledgeResponses["mempool"]
        }

        if matches(text, ["what is rbf", "what's rbf", "explain rbf",
                          "replace by fee", "replace-by-fee",
                          "tell me about rbf", "how to speed up transaction",
                          "bump fee", "fee bumping"]) {
            return knowledgeResponses["rbf"]
        }

        if matches(text, ["what is a sat", "what's a sat", "what is a satoshi",
                          "what are sats", "explain sat", "explain sats",
                          "smallest unit", "tell me about sats",
                          "what is satoshi unit", "how many sats in a bitcoin",
                          "how many satoshis"]) {
            return knowledgeResponses["satoshi"]
        }

        if matches(text, ["what is a private key", "what's a private key",
                          "explain private key", "tell me about private key",
                          "what are private keys"]) {
            return knowledgeResponses["private_key"]
        }

        if matches(text, ["what is a public key", "what's a public key",
                          "explain public key", "tell me about public key",
                          "what are public keys"]) {
            return knowledgeResponses["public_key"]
        }

        if matches(text, ["what is an address", "what's an address", "explain address",
                          "tell me about address", "bitcoin address",
                          "what is a bitcoin address"]) {
            return knowledgeResponses["address"]
        }

        if matches(text, ["address type", "what address types", "types of address",
                          "legacy address", "p2sh address", "bech32 address",
                          "what does bc1q mean", "what does bc1p mean",
                          "what do the 1 addresses mean", "what do the 3 addresses mean",
                          "difference between address", "address format"]) {
            return knowledgeResponses["address_types"]
        }

        if matches(text, ["what is hd wallet", "what's hd wallet", "explain hd wallet",
                          "hierarchical deterministic", "tell me about hd wallet",
                          "what is bip44", "what is bip84", "what is bip86",
                          "what is bip49", "explain bip44", "explain bip84"]) {
            return knowledgeResponses["hd_wallet"]
        }

        if matches(text, ["is bitcoin safe", "is btc safe", "is bitcoin secure",
                          "bitcoin security", "how safe is bitcoin",
                          "can bitcoin be hacked", "has bitcoin been hacked"]) {
            return knowledgeResponses["safety"]
        }

        if matches(text, ["what is 2fa", "what's 2fa", "two factor authentication",
                          "two-factor", "explain 2fa", "biometric authentication",
                          "face id bitcoin", "touch id bitcoin"]) {
            return knowledgeResponses["2fa"]
        }

        if matches(text, ["what is cold storage", "what's cold storage", "explain cold storage",
                          "what is a hardware wallet", "what's a hardware wallet",
                          "explain hardware wallet", "tell me about cold storage",
                          "cold wallet", "ledger wallet", "trezor wallet",
                          "what is a cold wallet"]) {
            return knowledgeResponses["cold_storage"]
        }

        if matches(text, ["what is multisig", "what's multisig", "explain multisig",
                          "multi-sig", "multi sig", "tell me about multisig",
                          "multi-signature", "multisignature",
                          "what is multi-signature"]) {
            return knowledgeResponses["multisig"]
        }

        if matches(text, ["what is confirmation", "what are confirmations",
                          "explain confirmations", "what's a confirmation",
                          "how many confirmations", "tell me about confirmations",
                          "what does confirmed mean", "when is a transaction confirmed"]) {
            return knowledgeResponses["confirmation"]
        }

        if matches(text, ["transaction fee", "what are fees", "what is a fee",
                          "explain fees", "tell me about fees",
                          "what are transaction fees", "how much are fees",
                          "what is sat/vb", "what is sats/vb", "fee rate",
                          "how are fees calculated"]) {
            return knowledgeResponses["fees"]
        }

        if matches(text, ["how long does a transaction", "how long to send",
                          "how long to confirm", "how fast is bitcoin",
                          "transaction speed", "transaction time",
                          "how quickly can i send"]) {
            return knowledgeResponses["tx_time"]
        }

        if matches(text, ["wrong address", "sent to wrong", "send to wrong",
                          "irreversible", "can i reverse", "can i undo",
                          "get my bitcoin back", "sent to the wrong"]) {
            return knowledgeResponses["wrong_address"]
        }

        if matches(text, ["what is change output", "what's change output",
                          "explain change output", "what is change address",
                          "change in bitcoin", "where does the change go",
                          "tell me about change", "leftover bitcoin"]) {
            return knowledgeResponses["change_output"]
        }

        if matches(text, ["what is dust", "what's dust", "explain dust",
                          "dust limit", "tell me about dust",
                          "too small to spend", "dust attack"]) {
            return knowledgeResponses["dust"]
        }

        // ── Network ──

        if matches(text, ["what is a node", "what's a node", "explain node",
                          "what are nodes", "tell me about nodes",
                          "what is a full node", "run a node",
                          "bitcoin node"]) {
            return knowledgeResponses["node"]
        }

        if matches(text, ["what is difficulty", "what's difficulty", "explain difficulty",
                          "mining difficulty", "difficulty adjustment",
                          "tell me about difficulty", "how does difficulty work"]) {
            return knowledgeResponses["difficulty"]
        }

        if matches(text, ["what is hashrate", "what's hashrate", "explain hashrate",
                          "hash rate", "hash power", "tell me about hashrate",
                          "network hashrate", "mining power",
                          "computing power"]) {
            return knowledgeResponses["hashrate"]
        }

        if matches(text, ["what is a fork", "what's a fork", "explain fork",
                          "soft fork", "hard fork", "tell me about fork",
                          "what are forks", "bitcoin fork", "bitcoin cash",
                          "protocol upgrade"]) {
            return knowledgeResponses["fork"]
        }

        if matches(text, ["proof of work", "what is pow", "what's pow",
                          "explain proof of work", "how does consensus work",
                          "tell me about proof of work"]) {
            return knowledgeResponses["proof_of_work"]
        }

        if matches(text, ["what is decentralization", "what's decentralization",
                          "explain decentralization", "decentralized",
                          "why is decentralization important",
                          "tell me about decentralization"]) {
            return knowledgeResponses["decentralization"]
        }

        if matches(text, ["what is a bip", "what's a bip", "explain bip",
                          "bitcoin improvement proposal", "tell me about bip"]) {
            return knowledgeResponses["bip"]
        }

        if matches(text, ["double spend", "double-spend", "what is double spending",
                          "explain double spend", "can bitcoin be double spent"]) {
            return knowledgeResponses["double_spend"]
        }

        if matches(text, ["merkle tree", "merkle root", "what is a merkle",
                          "explain merkle"]) {
            return knowledgeResponses["merkle_tree"]
        }

        if matches(text, ["coinbase transaction", "what is the coinbase",
                          "what is a coinbase transaction", "block reward",
                          "how are new bitcoin created", "where do new bitcoin come from"]) {
            return knowledgeResponses["coinbase_tx"]
        }

        // ── Economics (before core to catch "supply" before "bitcoin") ──

        if matches(text, ["why is bitcoin valuable", "why does bitcoin have value",
                          "why is btc valuable", "what gives bitcoin value",
                          "why is bitcoin worth", "is bitcoin worth anything"]) {
            return knowledgeResponses["value"]
        }

        if matches(text, ["how many bitcoin", "total supply", "21 million",
                          "how much bitcoin", "how many btc", "bitcoin supply",
                          "max supply", "maximum supply", "how many bitcoin exist",
                          "bitcoin's supply"]) {
            return knowledgeResponses["supply"]
        }

        if matches(text, ["bitcoin inflation", "inflation rate", "is bitcoin inflationary",
                          "is bitcoin deflationary", "bitcoin deflation",
                          "can they print more bitcoin", "print more bitcoin",
                          "monetary policy"]) {
            return knowledgeResponses["inflation"]
        }

        // ── Core Concepts (broadest matches last) ──

        if matches(text, ["what is the genesis block", "genesis block", "first block",
                          "block number 0", "block 0", "block #0"]) {
            return knowledgeResponses["block"]
        }

        if matches(text, ["what is blockchain", "what's blockchain", "what's a blockchain",
                          "what is a blockchain", "what is the blockchain",
                          "explain blockchain", "explain the blockchain",
                          "tell me about blockchain", "tell me about the blockchain",
                          "how does blockchain work", "how does the blockchain work"]) {
            return knowledgeResponses["blockchain"]
        }

        if matches(text, ["what is a block", "what's a block", "explain block",
                          "tell me about blocks", "how big is a block",
                          "what's in a block"]) {
            return knowledgeResponses["block"]
        }

        if matches(text, ["what is bitcoin", "what's bitcoin", "explain bitcoin",
                          "tell me about bitcoin", "teach me about bitcoin",
                          "what is btc", "what's btc", "explain btc"]) {
            return knowledgeResponses["bitcoin"]
        }

        return nil
    }

    // MARK: - Helpers

    private func matches(_ text: String, _ triggers: [String]) -> Bool {
        // Try exact match first
        if triggers.contains(where: { text.contains($0) }) { return true }
        // Also try with articles stripped so "what is the blockchain" matches "what is blockchain"
        let stripped = text
            .replacingOccurrences(of: " the ", with: " ")
            .replacingOccurrences(of: " a ", with: " ")
            .replacingOccurrences(of: " an ", with: " ")
        if stripped != text {
            return triggers.contains { stripped.contains($0) }
        }
        return false
    }
}
