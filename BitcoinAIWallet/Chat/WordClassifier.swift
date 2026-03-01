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

    /// Maps a leading currency symbol to its ISO code for fiat-prefixed amounts.
    private let currencySymbols: [Character: String] = ["$": "USD", "€": "EUR", "£": "GBP", "¥": "JPY"]

    func classify(_ word: String) -> WordType {
        // Detect fiat-prefixed amounts: "$50", "€100", "£75", "¥1000"
        let raw = word.lowercased()
        if let first = raw.first, let currencyCode = currencySymbols[first] {
            let numPart = String(raw.dropFirst()).trimmingCharacters(in: .punctuationCharacters)
            if let _ = Decimal(string: numPart) {
                // Return as a currency marker; the number is extracted separately by EntityExtractor
                return .unknown("fiat_amount:\(currencyCode)")
            }
        }

        let w = raw.trimmingCharacters(in: .punctuationCharacters)
            .replacingOccurrences(of: "\u{2019}", with: "'")  // iOS smart quote → apostrophe
            .replacingOccurrences(of: "\u{2018}", with: "'")
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
            .replacingOccurrences(of: "\u{2019}", with: "'")  // iOS smart quote → apostrophe
            .replacingOccurrences(of: "\u{2018}", with: "'")
        let phrases: [(String, String)] = [
            // Longer phrases MUST come before shorter substrings
            ("how much to send", "how_much_to_send"),
            ("how much", "how_much"), ("how many", "how_many"),
            ("too much", "too_much"), ("too little", "too_little"),
            ("too expensive", "too_expensive"), ("too cheap", "too_cheap"),
            ("not sure", "not_sure"), ("not enough", "not_enough"),
            ("changed my mind", "changed_mind"), ("never mind", "never_mind"),
            ("go back", "go_back"), ("come on", "come_on"),
            ("right now", "right_now"), ("last time", "last_time"),
            ("do it again", "do_again"), ("same thing", "same_thing"),
            ("let's go", "let's_go"), ("lets go", "let's_go"),
            ("use slow fee", "use_slow_fee"), ("use fast fee", "use_fast_fee"),
            ("use medium fee", "use_medium_fee"),
            ("change amount", "change_amount"),
            ("go ahead", "go_ahead"), ("start over", "start_over"),
            ("i didn't mean", "didn't_mean"), ("i didnt mean", "didn't_mean"),
            ("that's not what", "not_what_asked"), ("thats not what", "not_what_asked"),
            ("health check", "health_check"),
            ("what about", "what_about"), ("how about", "how_about"),
            ("try again", "try_again"), ("copy that", "copy_that"),
            ("good enough", "good_enough"), ("sounds good", "sounds_good"),
            ("the second", "ordinal_2"), ("the third", "ordinal_3"),
            ("the first", "ordinal_1"), ("the last", "ordinal_last"),
            // Greetings
            ("good morning", "good_morning"), ("good afternoon", "good_afternoon"),
            ("good evening", "good_evening"),
            ("what's up", "what's_up"), ("whats up", "what's_up"),
            ("what's good", "what's_good"), ("whats good", "what's_good"),
            ("what's happening", "what's_happening"), ("whats happening", "what's_happening"),
            ("how's it going", "how's_it_going"), ("hows it going", "how's_it_going"),
            ("how ya doing", "how_ya_doing"), ("how you doing", "how_ya_doing"),
            // Social phrases
            ("oh no", "oh_no"), ("not bad", "not_bad"),
            ("thank you", "thank_you"), ("nice one", "nice_one"),
            ("love it", "love_it"), ("that sucks", "that_sucks"),
            ("to the moon", "to_the_moon"), ("am i rich", "am_i_rich"),
            ("lemme see", "lemme_see"), ("gimme my", "gimme_my"),
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
                        ("why", .why), ("how", .how), ("how's", .how), ("hows", .how),
                        ("when", .when), ("when's", .when), ("whens", .when),
                        ("where", .where), ("where's", .where), ("wheres", .where),
                        ("which", .which), ("who", .who), ("who's", .who), ("whos", .who),
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
                        ("check", .check), ("show", .show), ("display", .show), ("hide", .hide), ("reveal", .show),
                        ("export", .export), ("bump", .bump), ("accelerate", .bump), ("speed", .bump),
                        ("refresh", .refresh), ("sync", .sync), ("update", .refresh), ("resync", .refresh), ("reload", .refresh),
                        ("generate", .generate), ("confirm", .confirm), ("cancel", .cancel),
                        ("convert", .convert), ("backup", .backup),
                        ("ارسل", .send), ("أرسل", .send), ("حول", .send), ("ادفع", .send),
                        ("استقبال", .receive), ("أكد", .confirm), ("إلغاء", .cancel),
                        ("ocultar", .hide),
                        ("enviar", .send), ("envía", .send), ("recibir", .receive),
                        ("confirmar", .confirm), ("cancelar", .cancel)] as [(String, WalletAction)] {
            d[w] = .walletVerb(v)
        }

        // ── General Verbs ──
        // ── Common Misspellings ──
        d["hlep"] = .generalVerb(.help)
        d["mean"] = .generalVerb(.explain)
        d["recieve"] = .walletVerb(.receive)
        d["recive"] = .walletVerb(.receive)
        d["ballance"] = .bitcoinNoun(.balance)
        d["adress"] = .bitcoinNoun(.address)
        d["trasaction"] = .bitcoinNoun(.transaction)

        for (w, v) in [("want", GeneralAction.want), ("wanna", .want), ("need", .need), ("like", .like),
                        ("think", .think), ("know", .know), ("understand", .understand),
                        ("go", .go), ("see", .see), ("look", .look), ("get", .get), ("make", .make),
                        ("change", .change), ("set", .set), ("try", .tryIt),
                        ("tell", .tell), ("explain", .explain), ("help", .help), ("teach", .teach),
                        ("repeat", .repeat), ("afford", .afford), ("wait", .wait),
                        ("stop", .stop), ("start", .start), ("undo", .undo), ("redo", .redo),
                        ("go_back", .undo), ("changed_mind", .undo), ("never_mind", .undo),
                        ("start_over", .undo), ("didn't_mean", .undo), ("not_what_asked", .undo),
                        ("try_again", .repeat)] as [(String, GeneralAction)] {
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
        d["good"] = .evaluative(.good); d["great"] = .evaluative(.good); d["nice"] = .emotion(.excitement)
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
                   "absolutely", "definitely", "exactly", "agreed", "proceed", "y", "go_ahead",
                   "let's_go",
                   "نعم", "أكيد", "تمام", "موافق", "يلا",
                   "sí", "si", "dale", "claro", "correcto"] {
            d[w] = .affirmation
        }

        // ── Greetings ──
        for w in ["hi", "hello", "hey", "yo", "sup", "howdy",
                   "good_morning", "good_afternoon", "good_evening",
                   "morning", "afternoon", "evening",
                   "heya", "g'day", "greetings",
                   "what's_up", "what's_good", "what's_happening", "how's_it_going",
                   "how_ya_doing",
                   "مرحبا", "أهلا", "السلام", "hola", "buenos_días"] {
            d[w] = .greeting
        }

        // ── Bitcoin Nouns ──
        d["balance"] = .bitcoinNoun(.balance); d["رصيد"] = .bitcoinNoun(.balance); d["رصيدي"] = .bitcoinNoun(.balance); d["saldo"] = .bitcoinNoun(.balance)
        d["coins"] = .bitcoinNoun(.balance); d["funds"] = .bitcoinNoun(.balance); d["money"] = .bitcoinNoun(.balance)
        d["fee"] = .bitcoinNoun(.fee); d["fees"] = .bitcoinNoun(.fees); d["رسوم"] = .bitcoinNoun(.fees)
        d["address"] = .bitcoinNoun(.address); d["qr"] = .bitcoinNoun(.address); d["عنوان"] = .bitcoinNoun(.address); d["dirección"] = .bitcoinNoun(.address)
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
        d["transfers"] = .bitcoinNoun(.transactions); d["activity"] = .bitcoinNoun(.history)
        d["sent"] = .bitcoinNoun(.history); d["received"] = .bitcoinNoun(.history); d["pending"] = .bitcoinNoun(.history)
        d["recent"] = .temporal(.recently); d["trading"] = .bitcoinNoun(.price)
        d["value"] = .bitcoinNoun(.price); d["worth"] = .bitcoinNoun(.price)
        d["congested"] = .bitcoinNoun(.network)
        d["health_check"] = .bitcoinNoun(.wallet)
        d["settings"] = .unknown("settings_intent")
        d["cheapest"] = .comparative(.cheaper); d["fastest"] = .comparative(.faster)
        d["slowest"] = .comparative(.slower)

        // ── Fee-level & amount phrase tokens ──
        d["how_much_to_send"] = .bitcoinNoun(.fees)
        d["use_slow_fee"] = .unknown("fee_level:slow")
        d["use_fast_fee"] = .unknown("fee_level:fast")
        d["use_medium_fee"] = .unknown("fee_level:medium")
        d["change_amount"] = .unknown("change_amount")

        // ── Word Numbers (common spoken amounts) ──
        let wordNumbers: [(String, Decimal)] = [
            ("one", 1), ("two", 2), ("three", 3), ("four", 4), ("five", 5),
            ("six", 6), ("seven", 7), ("eight", 8), ("nine", 9), ("ten", 10),
            ("eleven", 11), ("twelve", 12), ("thirteen", 13), ("fourteen", 14),
            ("fifteen", 15), ("sixteen", 16), ("seventeen", 17), ("eighteen", 18),
            ("nineteen", 19), ("twenty", 20), ("thirty", 30), ("forty", 40),
            ("fifty", 50), ("hundred", 100), ("thousand", 1000),
        ]
        for (w, n) in wordNumbers { d[w] = .number(n) }

        // ── Bitcoin Units ──
        for w in ["btc", "bitcoin", "بتكوين", "sat", "sats", "satoshi", "satoshis", "ساتوشي"] { d[w] = .bitcoinUnit }

        // ── Emotions ──
        for w in ["thanks", "thank", "thx", "ty", "appreciate", "grateful",
                   "شكرا", "gracias", "merci", "danke", "grazie"] { d[w] = .emotion(.gratitude) }
        for w in ["ugh", "annoyed", "frustrated", "frustrating", "broken", "stupid", "wtf", "useless",
                   "damn", "sucks", "terrible"] { d[w] = .emotion(.frustration) }
        for w in ["confused", "lost", "huh", "idk", "meh", "hmm", "hm", "umm", "um", "🤔"] { d[w] = .emotion(.confusion) }
        for w in ["awesome", "amazing", "cool", "wow", "sweet", "yay",
                   "brilliant", "love", "fantastic", "incredible"] { d[w] = .emotion(.excitement) }
        for w in ["lol", "haha", "hehe", "funny", "😂", "🤣"] { d[w] = .emotion(.humor) }
        for w in ["worried", "scared", "nervous", "concerned", "afraid",
                   "oops", "yikes", "oh_no"] { d[w] = .emotion(.concern) }

        // ── Social phrase tokens ──
        // ── Currency words (for follow-up detection) ──
        for w in ["dollars", "dollar", "bucks", "usd"] { d[w] = .unknown("currency:USD") }
        for w in ["euros", "euro", "eur"] { d[w] = .unknown("currency:EUR") }
        for w in ["pounds", "pound", "gbp", "quid"] { d[w] = .unknown("currency:GBP") }
        for w in ["yen", "jpy"] { d[w] = .unknown("currency:JPY") }
        for w in ["cad", "canadian"] { d[w] = .unknown("currency:CAD") }

        // ── Common words ──
        d["lot"] = .unknown("lot")
        d["sorry"] = .emotion(.concern)
        d["amount"] = .bitcoinNoun(.balance)
        d["copy"] = .affirmation
        d["copy_that"] = .affirmation
        d["what_about"] = .questionWord(.what)
        d["how_about"] = .questionWord(.what)

        d["thank_you"] = .emotion(.gratitude)
        d["not_bad"] = .evaluative(.good)
        d["nice_one"] = .emotion(.excitement)
        d["love_it"] = .emotion(.excitement)
        d["that_sucks"] = .emotion(.frustration)
        d["to_the_moon"] = .emotion(.excitement)
        d["am_i_rich"] = .bitcoinNoun(.balance)
        d["lemme_see"] = .generalVerb(.see)
        d["gimme_my"] = .walletVerb(.show)

        return d
    }()
}
