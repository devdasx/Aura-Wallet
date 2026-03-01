// MARK: - WordClassifier.swift
// Bitcoin AI Wallet
//
// Classifies ~200 English words into grammatical/semantic categories.
// Supports English, Arabic, and Spanish. Enables understanding of
// 10,000+ sentences from a compact vocabulary. Multi-word phrases
// are combined before classification ("too much" → "too_much").
//
// Platform: iOS 17.0+

import Foundation

// MARK: - Sub-Enums

enum QuestionKind: String, Equatable {
    case what, why, how, when, `where`, which, who, howMuch, howMany
}

enum PronounKind: Equatable {
    case it, that, this, those, these, one, them, they, same, last, previous
}

enum ModalKind: Equatable {
    case can, could, should, would, will, might, may
}

enum WalletAction: String, Equatable {
    case send, receive, check, show, hide, export, bump, refresh, sync
    case generate, confirm, cancel, convert, verify, backup
}

enum GeneralAction: String, Equatable {
    case want, need, like, think, know, understand
    case go, see, look, get, make, change, set, tryIt
    case tell, explain, help, teach, `repeat`, afford, wait
    case stop, start, undo, redo
}

enum Direction: Equatable {
    case more, less, bigger, smaller, faster, slower, cheaper
    case higher, lower, up, down, increase, decrease, raise, reduce
}

enum Quantity: Equatable {
    case all, some, none, half, double, triple
    case most, few, every, remaining, rest, maximum, minimum
}

enum Evaluation: Equatable {
    case good, bad, enough, tooMuch, tooLittle
    case safe, risky, correct, wrong, right, fine, ok, perfect
    case expensive, cheap, reasonable, fair, high, low
}

enum NavigationDir: Equatable {
    case back, forward, again, next, previous, last, first
    case latest, newest, oldest
}

enum TimeRef: Equatable {
    case now, later, soon, yesterday, today, tomorrow
    case before, after, already, yet, recently, always
}

enum BitcoinConcept: String, Equatable {
    case balance, fee, fees, address, transaction, transactions
    case utxo, utxos, price, block, wallet, network, mempool
    case mining, halving, segwit, taproot, lightning
    case seed, key, signature, confirmation, confirmations, history
}

enum EmotionType: Equatable {
    case gratitude, frustration, confusion, excitement, humor, concern, impatience
}

// MARK: - WordType

enum WordType: Equatable {

    // Structure words
    case questionWord(QuestionKind)
    case pronoun(PronounKind)
    case conjunction
    case preposition
    case article
    case modal(ModalKind)

    // Meaning words
    case walletVerb(WalletAction)
    case generalVerb(GeneralAction)
    case comparative(Direction)
    case quantifier(Quantity)
    case evaluative(Evaluation)
    case directional(NavigationDir)
    case temporal(TimeRef)
    case negation
    case affirmation

    // Bitcoin domain
    case bitcoinNoun(BitcoinConcept)
    case bitcoinUnit

    // Social
    case greeting

    // Emotion
    case emotion(EmotionType)

    // Raw data
    case number(Decimal)
    case bitcoinAddress
    case txid

    // Unknown
    case unknown(String)
}

// MARK: - WordClassifier

final class WordClassifier {

    // MARK: - Public API

    func classify(_ word: String) -> WordType {
        let w = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
        if let type = dictionary[w] { return type }
        if let num = Decimal(string: w) { return .number(num) }
        if w.hasPrefix("bc1") || w.hasPrefix("tb1") { return .bitcoinAddress }
        if w.count >= 25 && w.count <= 34 && (w.hasPrefix("1") || w.hasPrefix("3")) { return .bitcoinAddress }
        if w.count == 64 && w.allSatisfy({ "0123456789abcdef".contains($0) }) { return .txid }
        return .unknown(w)
    }

    func classifyAll(_ text: String) -> [(word: String, type: WordType)] {
        let processed = preprocessPhrases(text)
        return processed.map { (word: $0, type: classify($0)) }
    }

    // MARK: - Phrase Preprocessing

    /// Combine multi-word phrases into single tokens BEFORE splitting.
    private func preprocessPhrases(_ text: String) -> [String] {
        var result = text.lowercased()
        let phrases: [(String, String)] = [
            ("how much", "how_much"), ("how many", "how_many"),
            ("too much", "too_much"), ("too little", "too_little"),
            ("too expensive", "too_expensive"), ("too cheap", "too_cheap"),
            ("not sure", "not_sure"), ("not enough", "not_enough"),
            ("changed my mind", "changed_mind"), ("never mind", "never_mind"),
            ("go back", "go_back"), ("come on", "come_on"),
            ("right now", "right_now"), ("last time", "last_time"),
            ("do it again", "do_again"), ("same thing", "same_thing"),
            ("good enough", "good_enough"), ("sounds good", "sounds_good"),
            ("the second", "ordinal_2"), ("the third", "ordinal_3"),
            ("the first", "ordinal_1"), ("the last", "ordinal_last"),
            // Greetings
            ("good morning", "good_morning"), ("good afternoon", "good_afternoon"),
            ("good evening", "good_evening"),
            // Arabic
            ("كم عندي", "how_much_ar"), ("نفس العنوان", "same_address_ar"),
            ("نفس المبلغ", "same_amount_ar"),
            // Spanish
            ("cuánto tengo", "how_much_es"), ("buenos días", "buenos_días"),
        ]
        for (phrase, token) in phrases {
            result = result.replacingOccurrences(of: phrase, with: token)
        }
        return result.split(separator: " ").map { String($0) }.filter { !$0.isEmpty }
    }

    // MARK: - Dictionary (~200 words)

    private let dictionary: [String: WordType] = {
        var d: [String: WordType] = [:]

        // ── Question Words ──
        for (w, k) in [("what", QuestionKind.what), ("what's", .what), ("whats", .what),
                        ("why", .why), ("how", .how), ("when", .when), ("where", .where),
                        ("which", .which), ("who", .who),
                        ("how_much", .howMuch), ("how_many", .howMany),
                        ("ما", .what), ("ماذا", .what), ("لماذا", .why), ("كيف", .how),
                        ("متى", .when), ("أين", .where), ("كم", .howMuch), ("how_much_ar", .howMuch),
                        ("qué", .what), ("que", .what), ("cómo", .how), ("cuándo", .when),
                        ("dónde", .where), ("how_much_es", .howMuch)] as [(String, QuestionKind)] {
            d[w] = .questionWord(k)
        }

        // ── Pronouns ──
        for (w, p) in [("it", PronounKind.it), ("that", .that), ("this", .this),
                        ("those", .those), ("these", .these), ("one", .one),
                        ("them", .them), ("they", .they), ("same", .same),
                        ("same_thing", .same), ("same_address_ar", .same),
                        ("same_amount_ar", .same)] as [(String, PronounKind)] {
            d[w] = .pronoun(p)
        }

        // ── Conjunctions ──
        for w in ["and", "but", "or", "then", "also", "plus", "yet", "so",
                   "و", "لكن", "أو", "ثم", "y", "pero", "o", "entonces"] {
            d[w] = .conjunction
        }

        // ── Prepositions ──
        for w in ["to", "from", "for", "in", "at", "with", "about", "of", "on", "into", "by",
                   "إلى", "من", "في", "عن", "على", "a", "de", "para", "en", "con", "sobre"] {
            d[w] = .preposition
        }

        // ── Articles ──
        for w in ["the", "a", "an", "my", "your", "his", "her", "its", "our", "their",
                   "ال", "mi", "tu", "su", "el", "la", "un", "una"] {
            d[w] = .article
        }

        // ── Modals ──
        for (w, m) in [("can", ModalKind.can), ("can't", .can), ("could", .could), ("couldn't", .could),
                        ("should", .should), ("shouldn't", .should), ("would", .would), ("wouldn't", .would),
                        ("will", .will), ("won't", .will), ("might", .might), ("may", .may)] as [(String, ModalKind)] {
            d[w] = .modal(m)
        }

        // ── Wallet Verbs ──
        for (w, v) in [("send", WalletAction.send), ("transfer", .send), ("pay", .send), ("move", .send), ("withdraw", .send),
                        ("receive", .receive), ("deposit", .receive),
                        ("check", .check), ("show", .show), ("display", .show), ("hide", .hide),
                        ("export", .export), ("bump", .bump), ("accelerate", .bump), ("speed", .bump),
                        ("refresh", .refresh), ("sync", .sync), ("update", .refresh),
                        ("generate", .generate), ("confirm", .confirm), ("cancel", .cancel),
                        ("convert", .convert), ("backup", .backup),
                        ("ارسل", .send), ("أرسل", .send), ("حول", .send), ("ادفع", .send),
                        ("استقبال", .receive), ("أكد", .confirm), ("إلغاء", .cancel),
                        ("enviar", .send), ("envía", .send), ("recibir", .receive),
                        ("confirmar", .confirm), ("cancelar", .cancel)] as [(String, WalletAction)] {
            d[w] = .walletVerb(v)
        }

        // ── General Verbs ──
        for (w, v) in [("want", GeneralAction.want), ("wanna", .want), ("need", .need), ("like", .like),
                        ("think", .think), ("know", .know), ("understand", .understand),
                        ("go", .go), ("see", .see), ("look", .look), ("get", .get), ("make", .make),
                        ("change", .change), ("set", .set), ("try", .tryIt),
                        ("tell", .tell), ("explain", .explain), ("help", .help), ("teach", .teach),
                        ("repeat", .repeat), ("afford", .afford), ("wait", .wait),
                        ("stop", .stop), ("start", .start), ("undo", .undo), ("redo", .redo),
                        ("go_back", .undo), ("changed_mind", .undo), ("never_mind", .undo)] as [(String, GeneralAction)] {
            d[w] = .generalVerb(v)
        }

        // ── Comparatives ──
        for (w, dir) in [("more", Direction.more), ("less", .less), ("bigger", .bigger), ("smaller", .smaller),
                          ("faster", .faster), ("slower", .slower), ("cheaper", .cheaper),
                          ("higher", .higher), ("lower", .lower),
                          ("up", .up), ("down", .down), ("increase", .increase), ("decrease", .decrease),
                          ("raise", .raise), ("reduce", .reduce)] as [(String, Direction)] {
            d[w] = .comparative(dir)
        }

        // ── Quantifiers ──
        for (w, q) in [("all", Quantity.all), ("everything", .all), ("max", .maximum), ("maximum", .maximum),
                        ("some", .some), ("none", .none), ("half", .half), ("double", .double),
                        ("triple", .triple), ("most", .most), ("few", .few),
                        ("remaining", .remaining), ("rest", .rest)] as [(String, Quantity)] {
            d[w] = .quantifier(q)
        }

        // ── Evaluatives ──
        d["good"] = .evaluative(.good); d["great"] = .evaluative(.good); d["nice"] = .evaluative(.good)
        d["bad"] = .evaluative(.bad); d["terrible"] = .evaluative(.bad)
        d["enough"] = .evaluative(.enough); d["good_enough"] = .evaluative(.enough)
        d["not_enough"] = .evaluative(.tooLittle)
        d["too_much"] = .evaluative(.tooMuch); d["too_expensive"] = .evaluative(.expensive)
        d["too_cheap"] = .evaluative(.cheap); d["not_sure"] = .evaluative(.bad)
        d["safe"] = .evaluative(.safe); d["risky"] = .evaluative(.risky); d["dangerous"] = .evaluative(.risky)
        d["expensive"] = .evaluative(.expensive); d["cheap"] = .evaluative(.cheap)
        d["correct"] = .evaluative(.correct); d["wrong"] = .evaluative(.wrong)
        d["right"] = .evaluative(.right); d["perfect"] = .evaluative(.perfect)
        d["fine"] = .evaluative(.fine); d["sounds_good"] = .evaluative(.good)
        d["reasonable"] = .evaluative(.reasonable); d["fair"] = .evaluative(.fair)

        // ── Directionals ──
        d["back"] = .directional(.back); d["forward"] = .directional(.forward)
        d["again"] = .directional(.again); d["do_again"] = .directional(.again)
        d["next"] = .directional(.next); d["previous"] = .directional(.previous)
        d["last"] = .directional(.last); d["first"] = .directional(.first)
        d["latest"] = .directional(.latest); d["newest"] = .directional(.newest)
        d["oldest"] = .directional(.oldest)
        d["ordinal_1"] = .directional(.first); d["ordinal_2"] = .directional(.next)
        d["ordinal_3"] = .directional(.next); d["ordinal_last"] = .directional(.last)

        // ── Temporal ──
        d["now"] = .temporal(.now); d["right_now"] = .temporal(.now); d["come_on"] = .temporal(.now)
        d["later"] = .temporal(.later); d["soon"] = .temporal(.soon)
        d["yesterday"] = .temporal(.yesterday); d["today"] = .temporal(.today)
        d["recently"] = .temporal(.recently); d["already"] = .temporal(.already)

        // ── Negation ──
        for w in ["not", "no", "don't", "dont", "won't", "wont", "can't", "cant",
                   "never", "nothing", "neither", "nope", "nah",
                   "لا", "مش", "nunca", "nada"] {
            d[w] = .negation
        }

        // ── Affirmation ──
        for w in ["yes", "yeah", "yep", "yea", "ya", "ok", "okay", "sure",
                   "absolutely", "definitely", "exactly", "agreed", "proceed", "y",
                   "نعم", "أكيد", "تمام", "موافق", "يلا",
                   "sí", "si", "dale", "claro", "correcto"] {
            d[w] = .affirmation
        }

        // ── Greetings ──
        for w in ["hi", "hello", "hey", "yo", "sup", "howdy",
                   "good_morning", "good_afternoon", "good_evening",
                   "morning", "afternoon", "evening",
                   "مرحبا", "أهلا", "السلام", "hola", "buenos_días"] {
            d[w] = .greeting
        }

        // ── Bitcoin Nouns ──
        d["balance"] = .bitcoinNoun(.balance); d["رصيد"] = .bitcoinNoun(.balance); d["رصيدي"] = .bitcoinNoun(.balance); d["saldo"] = .bitcoinNoun(.balance)
        d["fee"] = .bitcoinNoun(.fee); d["fees"] = .bitcoinNoun(.fees); d["رسوم"] = .bitcoinNoun(.fees)
        d["address"] = .bitcoinNoun(.address); d["عنوان"] = .bitcoinNoun(.address); d["dirección"] = .bitcoinNoun(.address)
        d["transaction"] = .bitcoinNoun(.transaction); d["tx"] = .bitcoinNoun(.transaction); d["transactions"] = .bitcoinNoun(.transactions)
        d["utxo"] = .bitcoinNoun(.utxo); d["utxos"] = .bitcoinNoun(.utxos)
        d["price"] = .bitcoinNoun(.price); d["سعر"] = .bitcoinNoun(.price); d["precio"] = .bitcoinNoun(.price)
        d["block"] = .bitcoinNoun(.block); d["wallet"] = .bitcoinNoun(.wallet); d["محفظة"] = .bitcoinNoun(.wallet); d["cartera"] = .bitcoinNoun(.wallet)
        d["network"] = .bitcoinNoun(.network); d["شبكة"] = .bitcoinNoun(.network)
        d["mempool"] = .bitcoinNoun(.mempool); d["mining"] = .bitcoinNoun(.mining); d["تعدين"] = .bitcoinNoun(.mining)
        d["halving"] = .bitcoinNoun(.halving); d["segwit"] = .bitcoinNoun(.segwit); d["taproot"] = .bitcoinNoun(.taproot)
        d["lightning"] = .bitcoinNoun(.lightning); d["seed"] = .bitcoinNoun(.seed); d["key"] = .bitcoinNoun(.key)
        d["confirmation"] = .bitcoinNoun(.confirmation); d["confirmations"] = .bitcoinNoun(.confirmations)
        d["history"] = .bitcoinNoun(.history); d["سجل"] = .bitcoinNoun(.history); d["historial"] = .bitcoinNoun(.history)

        // ── Bitcoin Units ──
        for w in ["btc", "bitcoin", "بتكوين", "sat", "sats", "satoshi", "satoshis", "ساتوشي"] { d[w] = .bitcoinUnit }

        // ── Emotions ──
        for w in ["thanks", "thank", "thx", "ty", "appreciate", "grateful", "شكرا", "gracias"] { d[w] = .emotion(.gratitude) }
        for w in ["ugh", "annoyed", "frustrated", "broken", "stupid", "wtf", "useless"] { d[w] = .emotion(.frustration) }
        for w in ["confused", "lost", "huh", "idk"] { d[w] = .emotion(.confusion) }
        for w in ["awesome", "amazing", "cool", "wow", "sweet", "yay"] { d[w] = .emotion(.excitement) }
        for w in ["lol", "haha", "hehe", "funny", "😂", "🤣"] { d[w] = .emotion(.humor) }
        for w in ["worried", "scared", "nervous", "concerned", "afraid"] { d[w] = .emotion(.concern) }

        return d
    }()
}
