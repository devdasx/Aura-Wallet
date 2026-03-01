// MARK: - WordClassifier.swift
// Bitcoin AI Wallet
//
// Classifies ~800+ English words into grammatical/semantic categories.
// Supports English, Arabic, Spanish, and French. Enables understanding of
// 50,000+ sentences from a comprehensive vocabulary. Multi-word phrases
// are combined before classification ("too much" -> "too_much").
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
    private let currencySymbols: [Character: String] = [
        "$": "USD", "\u{20AC}": "EUR", "\u{00A3}": "GBP", "\u{00A5}": "JPY",
        "\u{20B9}": "INR", "\u{20A9}": "KRW", "\u{20BD}": "RUB", "\u{20BA}": "TRY"
    ]

    func classify(_ word: String) -> WordType {
        let raw = word.lowercased()
        if let first = raw.first, let currencyCode = currencySymbols[first] {
            let numPart = String(raw.dropFirst()).trimmingCharacters(in: .punctuationCharacters)
            if let _ = Decimal(string: numPart) {
                return .unknown("fiat_amount:\(currencyCode)")
            }
        }

        // Detect negative numbers BEFORE punctuation trimming strips the minus sign.
        // "-1", "-0.5" etc. → flag as invalid_negative_amount so upstream can reject.
        if raw.hasPrefix("-"), raw.count > 1 {
            let afterMinus = String(raw.dropFirst()).trimmingCharacters(in: .punctuationCharacters)
            if let _ = Decimal(string: afterMinus), !afterMinus.isEmpty {
                return .unknown("invalid_negative_amount")
            }
        }

        let w = raw.trimmingCharacters(in: .punctuationCharacters)
            .replacingOccurrences(of: "\u{2019}", with: "'")
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
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")

        // Normalize all whitespace (newlines, tabs, etc.) to single spaces
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        // Longer phrases MUST come before shorter substrings to avoid partial matching.
        let phrases: [(String, String)] = [

            // ── Multi-word cost/send questions (longest first) ──
            ("how much will it cost to send", "how_much_to_send"),
            ("how much does it cost to send", "how_much_to_send"),
            ("how much will it cost", "how_much_to_send"),
            ("how much does it cost", "how_much_cost"),
            ("how much to send", "how_much_to_send"),
            ("how long does it take", "how_long_take"),
            ("how long will it take", "how_long_take"),
            ("how much bitcoin do i have", "howmuch_ownership_btc"),
            ("how much btc do i have", "howmuch_ownership_btc"),
            ("how much do i have", "howmuch_ownership"),

            // ── Multi-word question phrases ──
            ("how do i", "how_do_i"), ("how can i", "how_can_i"),
            ("can i", "can_i"), ("could i", "could_i"), ("should i", "should_i"),
            ("do i have", "do_i_have"), ("do i need", "do_i_need"),
            ("is it possible", "is_it_possible"), ("is it safe", "is_it_safe"),
            ("is there a way", "is_there_way"), ("are there any", "are_there_any"),
            ("will it", "will_it"), ("would it", "would_it"),
            ("what is", "what_is"), ("what are", "what_are"),
            ("where is", "where_is"), ("where are", "where_are"),
            ("how much is", "how_much_is"),
            ("how much", "how_much"), ("how many", "how_many"),
            ("how fast", "how_fast"), ("how long", "how_long"),

            // ── Multi-word evaluative phrases (longest first) ──
            ("that's too much", "thats_too_much"), ("thats too much", "thats_too_much"),
            ("that's too expensive", "thats_too_expensive"), ("thats too expensive", "thats_too_expensive"),
            ("that's too little", "thats_too_little"), ("thats too little", "thats_too_little"),
            ("that's too cheap", "thats_too_cheap"), ("thats too cheap", "thats_too_cheap"),
            ("that's too high", "thats_too_high"), ("thats too high", "thats_too_high"),
            ("that's too low", "thats_too_low"), ("thats too low", "thats_too_low"),
            ("that's too slow", "thats_too_slow"), ("thats too slow", "thats_too_slow"),
            ("that's fine", "thats_fine"), ("thats fine", "thats_fine"),
            ("that's great", "thats_great"), ("thats great", "thats_great"),
            ("that's perfect", "thats_perfect"), ("thats perfect", "thats_perfect"),
            ("that's okay", "thats_ok"), ("thats okay", "thats_ok"),
            ("that's ok", "thats_ok"), ("thats ok", "thats_ok"),
            ("too high", "too_high"), ("too low", "too_low"),
            ("too much", "too_much"), ("too little", "too_little"),
            ("too expensive", "too_expensive"), ("too cheap", "too_cheap"),
            ("too slow", "too_slow"), ("too fast", "too_fast"),
            ("not sure", "not_sure"), ("not enough", "not_enough"), ("not bad", "not_bad"),
            ("good enough", "good_enough"), ("sounds good", "sounds_good"),
            ("looks good", "looks_good"), ("all good", "all_good"),

            // ── Multi-word cancel/undo phrases ──
            ("scratch that", "scratch_that"), ("forget about it", "forget_it"),
            ("forget it", "forget_it"), ("back out", "back_out"),
            ("changed my mind", "changed_mind"), ("change my mind", "changed_mind"),
            ("never mind", "never_mind"), ("nevermind", "never_mind"),
            ("i didn't mean", "didn't_mean"), ("i didnt mean", "didn't_mean"),
            ("that's not what", "not_what_asked"), ("thats not what", "not_what_asked"),

            // ── Multi-word negation phrases ──
            ("no way", "no_way"), ("of course not", "of_course_not"),
            ("not at all", "not_at_all"), ("hell no", "hell_no"),

            // ── Multi-word affirmation phrases ──
            ("of course", "of_course"), ("for sure", "for_sure"),
            ("why not", "why_not"), ("you bet", "you_bet"),
            ("hell yeah", "hell_yeah"), ("hell yes", "hell_yes"),
            ("go for it", "go_for_it"), ("send it", "send_it"),
            ("do it", "do_it"), ("let's do it", "lets_do_it"), ("lets do it", "lets_do_it"),
            ("i'm in", "im_in"), ("im in", "im_in"),

            // ── Multi-word action phrases ──
            ("tell me", "tell_me"), ("show me", "show_me"),
            ("what's my", "whats_my"), ("whats my", "whats_my"),
            ("figure out", "figure_out"),

            // ── Multi-word navigation/control ──
            ("go back", "go_back"), ("go ahead", "go_ahead"), ("come on", "come_on"),
            ("right now", "right_now"), ("right away", "right_away"),
            ("last time", "last_time"), ("do it again", "do_again"), ("same thing", "same_thing"),
            ("let's go", "let's_go"), ("lets go", "let's_go"),
            ("start over", "start_over"), ("try again", "try_again"), ("copy that", "copy_that"),
            ("got it", "got_it"), ("i see", "i_see"), ("makes sense", "makes_sense"),
            ("as soon as possible", "asap_phrase"),
            ("in a bit", "in_a_bit"), ("a while ago", "a_while_ago"),

            // ── Multi-word fee phrases ──
            ("use normal fee", "use_medium_fee"), ("use standard fee", "use_medium_fee"),
            ("use regular fee", "use_medium_fee"), ("use default fee", "use_medium_fee"),
            ("use slow fee", "use_slow_fee"), ("use fast fee", "use_fast_fee"),
            ("use medium fee", "use_medium_fee"),
            ("use economy", "use_slow_fee"), ("use priority", "use_fast_fee"),
            ("economy fee", "use_slow_fee"), ("priority fee", "use_fast_fee"),
            ("normal fee", "use_medium_fee"), ("standard fee", "use_medium_fee"),
            ("slow fee", "use_slow_fee"), ("fast fee", "use_fast_fee"),
            ("medium fee", "use_medium_fee"),
            ("change amount", "change_amount"),
            ("sats per byte", "sats_per_byte"), ("sat per byte", "sats_per_byte"),
            ("sat/vb", "sats_per_byte"), ("sats/vb", "sats_per_byte"),

            // ── Multi-word bitcoin concepts ──
            ("health check", "health_check"),
            ("private key", "private_key"), ("public key", "public_key"),
            ("seed phrase", "seed_phrase"), ("recovery phrase", "recovery_phrase"),
            ("hash rate", "hash_rate"), ("block height", "block_height"),

            // ── Multi-word conversational phrases ──
            ("i'd like to", "want_to"), ("id like to", "want_to"),
            ("i want to", "want_to"), ("i need to", "want_to"), ("i wanna", "want_to"),
            ("let me see", "lemme_see"), ("let me", "want_to"), ("lemme", "want_to"),
            ("can you", "can_you"), ("could you", "can_you"),
            ("will you", "can_you"), ("would you", "can_you"),
            ("i have", "i_have"), ("i own", "i_own"), ("i got", "i_got"),
            ("i've got", "i_got"), ("ive got", "i_got"),
            ("in my wallet", "in_my_wallet"), ("give me my", "gimme_my"),

            // ── Multi-word crypto slang ──
            ("stacking sats", "stacking_sats"), ("stack sats", "stack_sats"),
            ("diamond hands", "diamond_hands"), ("paper hands", "paper_hands"),
            ("to the moon", "to_the_moon"), ("am i rich", "am_i_rich"),

            // ── Ordinals ──
            ("the second", "ordinal_2"), ("the third", "ordinal_3"),
            ("the first", "ordinal_1"), ("the last", "ordinal_last"),

            // ── Multi-word question follow-ups ──
            ("what about", "what_about"), ("how about", "how_about"),

            // ── Multi-word greetings ──
            ("good morning", "good_morning"), ("good afternoon", "good_afternoon"),
            ("good evening", "good_evening"), ("good night", "good_night"),
            ("what's up", "what's_up"), ("whats up", "what's_up"),
            ("what's good", "what's_good"), ("whats good", "what's_good"),
            ("what's happening", "what's_happening"), ("whats happening", "what's_happening"),
            ("how's it going", "how's_it_going"), ("hows it going", "how's_it_going"),
            ("how ya doing", "how_ya_doing"), ("how you doing", "how_ya_doing"),

            // ── Multi-word emotion/social phrases ──
            ("oh no", "oh_no"), ("for real", "for_real"), ("no idea", "no_idea"),
            ("much appreciated", "much_appreciated"),
            ("thank you so much", "thank_you_so_much"), ("thanks a lot", "thanks_a_lot"),
            ("thank you", "thank_you"), ("nice one", "nice_one"),
            ("love it", "love_it"), ("that sucks", "that_sucks"),
            ("lemme see", "lemme_see"), ("gimme my", "gimme_my"),
            ("hurry up", "hurry_up"), ("speed up", "speed_up"),

            // ── Multi-word farewell phrases ──
            ("good bye", "goodbye"), ("see you later", "see_you_later"),
            ("see you", "see_you"), ("see ya", "see_ya"),
            ("take care", "take_care"), ("catch you later", "catch_you_later"),

            // ── Arabic phrases ──
            ("\u{0643}\u{0645} \u{0639}\u{0646}\u{062F}\u{064A}", "how_much_ar"),
            ("\u{0646}\u{0641}\u{0633} \u{0627}\u{0644}\u{0639}\u{0646}\u{0648}\u{0627}\u{0646}", "same_address_ar"),
            ("\u{0646}\u{0641}\u{0633} \u{0627}\u{0644}\u{0645}\u{0628}\u{0644}\u{063A}", "same_amount_ar"),
            ("\u{0645}\u{0627} \u{0647}\u{0648} \u{0627}\u{0644}\u{0628}\u{064A}\u{062A}\u{0643}\u{0648}\u{064A}\u{0646}", "what_is_bitcoin_ar"), // ما هو البيتكوين
            ("\u{0645}\u{0627} \u{0627}\u{0644}\u{0633}\u{0639}\u{0631}", "what_price_ar"), // ما السعر

            // ── Spanish phrases ──
            ("cu\u{00E1}nto tengo", "how_much_es"), ("cuanto tengo", "how_much_es"),
            ("buenos d\u{00ED}as", "buenos_dias"),
            ("buenas tardes", "buenas_tardes"), ("buenas noches", "buenas_noches"),
            ("por favor", "por_favor"),

            // ── French phrases ──
            ("s'il vous pla\u{00EE}t", "sil_vous_plait"),
            ("s'il te pla\u{00EE}t", "sil_te_plait"),
        ]

        for (phrase, token) in phrases {
            result = result.replacingOccurrences(of: phrase, with: token)
        }
        return result.split(separator: " ").map { String($0) }.filter { !$0.isEmpty }
    }

    // MARK: - Dictionary (~800+ words)

    // swiftlint:disable:next function_body_length
    private let dictionary: [String: WordType] = {
        var d: [String: WordType] = [:]

        // =================================================================
        // QUESTION WORDS
        // =================================================================
        for (w, k) in [
            ("what", QuestionKind.what), ("what's", .what), ("whats", .what),
            ("what_is", .what), ("what_are", .what),
            ("why", .why), ("why's", .why), ("whys", .why),
            ("how", .how), ("how's", .how), ("hows", .how),
            ("when", .when), ("when's", .when), ("whens", .when),
            ("where", .where), ("where's", .where), ("wheres", .where),
            ("where_is", .where), ("where_are", .where),
            ("which", .which),
            ("who", .who), ("who's", .who), ("whos", .who), ("whose", .who), ("whom", .who),
            ("how_much", .howMuch), ("how_many", .howMany),
            ("how_much_cost", .howMuch), ("how_much_is", .howMuch),
            ("how_fast", .how), ("how_long", .how), ("how_long_take", .how),
            ("how_do_i", .how), ("how_can_i", .how),
            ("can_i", .how), ("could_i", .how), ("should_i", .how),
            ("do_i_have", .howMuch), ("do_i_need", .howMuch),
            ("is_it_possible", .how), ("is_it_safe", .how),
            ("is_there_way", .how), ("are_there_any", .howMany),
            ("will_it", .how), ("would_it", .how),
            ("what_about", .what), ("how_about", .what), ("whats_my", .what),
            // Arabic
            ("\u{0645}\u{0627}", .what), ("\u{0645}\u{0627}\u{0630}\u{0627}", .what),
            ("\u{0644}\u{0645}\u{0627}\u{0630}\u{0627}", .why), ("\u{0643}\u{064A}\u{0641}", .how),
            ("\u{0645}\u{062A}\u{0649}", .when), ("\u{0623}\u{064A}\u{0646}", .where),
            ("\u{0643}\u{0645}", .howMuch), ("how_much_ar", .howMuch),
            ("what_is_bitcoin_ar", .what), ("what_price_ar", .what),
            // Spanish
            ("qu\u{00E9}", .what), ("que", .what), ("c\u{00F3}mo", .how), ("como", .how),
            ("cu\u{00E1}ndo", .when), ("cuando", .when), ("d\u{00F3}nde", .where), ("donde", .where),
            ("cu\u{00E1}l", .which), ("cual", .which), ("qui\u{00E9}n", .who), ("quien", .who),
            ("cu\u{00E1}nto", .howMuch), ("cuanto", .howMuch),
            ("cu\u{00E1}ntos", .howMany), ("cuantos", .howMany), ("how_much_es", .howMuch),
            // French
            ("quoi", .what), ("pourquoi", .why), ("comment", .how),
            ("quand", .when), ("o\u{00F9}", .where), ("ou", .where),
            ("combien", .howMuch), ("quel", .which), ("quelle", .which),
        ] as [(String, QuestionKind)] {
            d[w] = .questionWord(k)
        }

        // =================================================================
        // PRONOUNS
        // =================================================================
        for (w, p) in [
            ("it", PronounKind.it), ("it's", .it), ("its", .it),
            ("that", .that), ("that's", .that), ("thats", .that),
            ("this", .this), ("those", .those), ("these", .these), ("one", .one),
            ("them", .them), ("they", .they), ("they're", .they), ("theyre", .they),
            ("same", .same), ("same_thing", .same),
            ("same_address_ar", .same), ("same_amount_ar", .same),
        ] as [(String, PronounKind)] {
            d[w] = .pronoun(p)
        }

        // =================================================================
        // CONJUNCTIONS
        // =================================================================
        for w in ["and", "but", "or", "then", "also", "plus", "yet", "so",
                   "too", "nor", "either", "both", "whether", "although", "though",
                   "however", "therefore", "furthermore", "moreover", "meanwhile",
                   "otherwise", "instead", "besides", "hence",
                   "actually", "basically", "literally", "honestly",
                   "anyway", "anyways", "even",
                   "btw", "tbh", "imo", "imho", "fyi", "aka", "etc",
                   "\u{0648}", "\u{0644}\u{0643}\u{0646}", "\u{0623}\u{0648}", "\u{062B}\u{0645}",
                   "y", "pero", "o", "entonces", "tambi\u{00E9}n", "tambien",
                   "adem\u{00E1}s", "ademas", "sin embargo",
                   // French
                   "et", "mais", "donc", "aussi", "cependant",
                   "pourtant", "toutefois"] {
            d[w] = .conjunction
        }

        // =================================================================
        // PREPOSITIONS
        // =================================================================
        for w in ["to", "from", "for", "in", "at", "with", "about", "of", "on",
                   "into", "by", "through", "between", "during", "above", "below",
                   "under", "over", "without", "within", "upon", "toward", "towards",
                   "against", "near", "across", "along", "around", "behind", "beside",
                   "among", "via", "per", "until", "since", "than",
                   "there", "there's", "theres", "here", "here's", "heres",
                   "approximately", "roughly", "nearly", "almost", "vs", "versus",
                   "\u{0625}\u{0644}\u{0649}", "\u{0645}\u{0646}", "\u{0641}\u{064A}",
                   "\u{0639}\u{0646}", "\u{0639}\u{0644}\u{0649}",
                   "a", "de", "para", "en", "con", "sobre", "entre",
                   "hacia", "hasta", "desde", "sin",
                   // French
                   "\u{00E0}", "dans", "avec", "pour", "sur", "sous",
                   "entre", "vers", "chez", "sans", "apr\u{00E8}s", "avant"] {
            d[w] = .preposition
        }

        // =================================================================
        // ARTICLES & POSSESSIVES
        // =================================================================
        for w in ["the", "a", "an", "my", "your", "his", "her", "our", "their",
                   "mine", "yours", "ours", "theirs",
                   "i", "me", "we", "us", "he", "she",
                   "i'm", "im", "i've", "ive", "you're", "youre", "we're", "were",
                   "he's", "hes", "she's", "shes",
                   "\u{0627}\u{0644}",
                   "mi", "tu", "su", "el", "la", "un", "una", "los", "las",
                   "unos", "unas", "mis", "tus", "sus", "nuestro", "nuestra",
                   // French
                   "le", "les", "du", "des", "mon", "ma", "mes",
                   "ton", "ta", "tes", "son", "sa", "ses",
                   "notre", "nos", "votre", "vos", "leur", "leurs",
                   "je", "tu", "il", "elle", "nous", "vous", "ils", "elles",
                   "ce", "cette", "ces"] {
            d[w] = .article
        }

        // =================================================================
        // MODALS
        // =================================================================
        for (w, m) in [
            ("can", ModalKind.can), ("can't", .can), ("cant", .can), ("cannot", .can),
            ("could", .could), ("couldn't", .could), ("couldnt", .could),
            ("should", .should), ("shouldn't", .should), ("shouldnt", .should),
            ("would", .would), ("wouldn't", .would), ("wouldnt", .would),
            ("will", .will), ("won't", .will), ("wont", .will),
            ("might", .might), ("may", .may),
            ("shall", .will), ("shan't", .will), ("shant", .will),
            ("gotta", .should), ("gonna", .will),
            ("i'll", .will), ("ill", .will), ("you'll", .will), ("youll", .will),
            ("we'll", .will), ("it'll", .will), ("itll", .will),
            ("let", .can), ("lets", .can), ("let's", .can), ("lemme", .can),
            ("can_you", .can), ("can_i", .can), ("could_i", .could), ("should_i", .should),
            ("will_it", .will), ("would_it", .would),
            ("puede", .can), ("puedo", .can),
            ("podr\u{00ED}a", .could), ("podria", .could),
            ("deber\u{00ED}a", .should), ("deberia", .should),
            // French
            ("pouvoir", .can), ("peux", .can), ("peut", .can),
            ("devoir", .should), ("dois", .should), ("doit", .should),
            ("vouloir", .will), ("veux", .will), ("veut", .will),
        ] as [(String, ModalKind)] {
            d[w] = .modal(m)
        }

        // =================================================================
        // WALLET VERBS
        // =================================================================
        for (w, v) in [
            // Send
            ("send", WalletAction.send), ("transfer", .send), ("pay", .send),
            ("move", .send), ("withdraw", .send), ("push", .send), ("wire", .send),
            ("forward", .send), ("ship", .send), ("dispatch", .send), ("remit", .send),
            ("zap", .send), ("broadcast", .send), ("transmit", .send), ("deliver", .send),
            ("spend", .send), ("gift", .send), ("donate", .send), ("tip", .send),
            ("sending", .send), ("paying", .send), ("transferring", .send), ("sent", .send),
            // Receive
            ("receive", .receive), ("deposit", .receive), ("accept", .receive),
            ("request", .receive), ("collect", .receive), ("claim", .receive),
            ("receiving", .receive), ("incoming", .receive),
            // Check / Show
            ("check", .check), ("show", .show), ("display", .show), ("reveal", .show),
            ("unhide", .show), ("view", .show), ("peek", .show), ("preview", .show),
            ("inspect", .check), ("examine", .check), ("review", .check),
            ("monitor", .check), ("lookup", .check),
            ("show_me", .show), ("tell_me", .show), ("whats_my", .show),
            // Hide
            ("hide", .hide), ("conceal", .hide), ("mask", .hide),
            // Export
            ("export", .export), ("download", .export), ("save", .export),
            // Bump
            ("bump", .bump), ("accelerate", .bump), ("speed", .bump),
            ("rbf", .bump), ("prioritize", .bump), ("boost", .bump),
            // Refresh / Sync
            ("refresh", .refresh), ("sync", .sync), ("update", .refresh),
            ("resync", .refresh), ("reload", .refresh), ("fetch", .refresh),
            ("synchronize", .sync), ("recheck", .refresh),
            // Generate
            ("generate", .generate), ("create", .generate), ("new", .generate),
            // Confirm
            ("confirm", .confirm), ("approve", .confirm), ("authorize", .confirm),
            ("validate", .confirm), ("finalize", .confirm), ("finalise", .confirm),
            // Cancel
            ("cancel", .cancel), ("abort", .cancel), ("discard", .cancel),
            ("disregard", .cancel), ("dismiss", .cancel), ("reject", .cancel),
            ("decline", .cancel), ("deny", .cancel), ("revoke", .cancel),
            // Convert
            ("convert", .convert), ("calculate", .convert), ("compute", .convert),
            ("figure_out", .convert), ("swap", .convert), ("exchange", .convert),
            // Verify / Backup
            ("verify", .verify),
            ("backup", .backup), ("restore", .backup), ("recover", .backup), ("import", .backup),
            // Arabic
            ("\u{0627}\u{0631}\u{0633}\u{0644}", .send), ("\u{0623}\u{0631}\u{0633}\u{0644}", .send),
            ("\u{062D}\u{0648}\u{0644}", .send), ("\u{0627}\u{062F}\u{0641}\u{0639}", .send),
            ("\u{0627}\u{0633}\u{062A}\u{0642}\u{0628}\u{0627}\u{0644}", .receive),
            ("\u{0623}\u{0643}\u{062F}", .confirm), ("\u{0625}\u{0644}\u{063A}\u{0627}\u{0621}", .cancel),
            ("\u{0627}\u{0638}\u{0647}\u{0631}", .show), ("\u{0623}\u{0638}\u{0647}\u{0631}", .show),
            ("\u{0627}\u{062E}\u{0641}\u{064A}", .hide),
            ("\u{062A}\u{0623}\u{0643}\u{064A}\u{062F}", .confirm), // تأكيد
            // Spanish
            ("enviar", .send), ("env\u{00ED}a", .send), ("envia", .send),
            ("recibir", .receive), ("mostrar", .show), ("ocultar", .hide),
            ("confirmar", .confirm), ("cancelar", .cancel),
            ("verificar", .verify), ("exportar", .export),
            // French
            ("envoyer", .send), ("recevoir", .receive),
            ("confirmer", .confirm), ("annuler", .cancel),
            ("exporter", .export), ("v\u{00E9}rifier", .verify),
        ] as [(String, WalletAction)] {
            d[w] = .walletVerb(v)
        }

        // =================================================================
        // GENERAL VERBS
        // =================================================================
        for (w, v) in [
            ("want", GeneralAction.want), ("wanna", .want), ("need", .need),
            ("prefer", .like), ("wish", .want),
            ("think", .think), ("believe", .think), ("guess", .think),
            ("know", .know), ("realize", .know), ("recognise", .know), ("recognize", .know),
            ("understand", .understand), ("comprehend", .understand),
            ("go", .go), ("see", .see), ("look", .look), ("get", .get),
            ("make", .make), ("put", .make), ("place", .make),
            ("change", .change), ("modify", .change), ("adjust", .change),
            ("alter", .change), ("switch", .change), ("edit", .change), ("tweak", .change),
            ("set", .set), ("configure", .set), ("setup", .set),
            ("try", .tryIt), ("attempt", .tryIt), ("test", .tryIt),
            ("tell", .tell), ("explain", .explain), ("describe", .explain),
            ("elaborate", .explain), ("clarify", .explain), ("define", .explain),
            ("help", .help), ("assist", .help), ("support", .help), ("guide", .help),
            ("commands", .help), ("menu", .help), ("instructions", .help), ("tutorial", .help),
            ("teach", .teach), ("learn", .teach), ("educate", .teach),
            ("repeat", .repeat), ("afford", .afford),
            ("wait", .wait), ("hold", .wait), ("pause", .wait),
            ("stop", .stop), ("quit", .stop), ("exit", .stop), ("end", .stop), ("close", .stop),
            ("start", .start), ("begin", .start), ("open", .start),
            ("launch", .start), ("initiate", .start),
            ("undo", .undo), ("revert", .undo), ("rollback", .undo),
            // Phrase tokens
            ("go_back", .undo), ("changed_mind", .undo), ("never_mind", .undo),
            ("start_over", .undo), ("didn't_mean", .undo), ("not_what_asked", .undo),
            ("scratch_that", .undo), ("forget_it", .undo), ("back_out", .undo),
            ("try_again", .repeat), ("want_to", .want),
            ("lemme_see", .see), ("i_see", .understand), ("makes_sense", .understand),
            ("tell_me", .tell),
            // Arabic
            ("\u{0645}\u{0633}\u{0627}\u{0639}\u{062F}\u{0629}", .help), // مساعدة
            ("\u{0633}\u{0627}\u{0639}\u{062F}\u{0646}\u{064A}", .help), // ساعدني
            ("\u{0627}\u{0634}\u{0631}\u{062D}", .explain), // اشرح
            ("\u{0639}\u{0644}\u{0645}\u{0646}\u{064A}", .teach), // علمني
            // Spanish
            ("ayuda", .help), ("ayudar", .help),
            ("explicar", .explain), ("ense\u{00F1}ar", .teach),
            // French
            ("aide", .help), ("aider", .help),
            ("expliquer", .explain), ("montrer", .see),
        ] as [(String, GeneralAction)] {
            d[w] = .generalVerb(v)
        }

        // =================================================================
        // MISSPELLINGS & TYPOS
        // =================================================================
        d["hlep"] = .generalVerb(.help); d["halp"] = .generalVerb(.help)
        d["plz"] = .generalVerb(.help); d["pls"] = .generalVerb(.help)
        d["please"] = .generalVerb(.help); d["por_favor"] = .generalVerb(.help)
        d["mean"] = .generalVerb(.explain); d["means"] = .generalVerb(.explain)
        d["meaning"] = .generalVerb(.explain)
        d["recieve"] = .walletVerb(.receive); d["recive"] = .walletVerb(.receive)
        d["receieve"] = .walletVerb(.receive); d["receve"] = .walletVerb(.receive)
        d["ballance"] = .bitcoinNoun(.balance); d["balanse"] = .bitcoinNoun(.balance)
        d["balanc"] = .bitcoinNoun(.balance); d["blance"] = .bitcoinNoun(.balance)
        d["balane"] = .bitcoinNoun(.balance); d["balnce"] = .bitcoinNoun(.balance)
        d["adress"] = .bitcoinNoun(.address); d["addres"] = .bitcoinNoun(.address)
        d["adres"] = .bitcoinNoun(.address); d["adrress"] = .bitcoinNoun(.address)
        d["trasaction"] = .bitcoinNoun(.transaction); d["transction"] = .bitcoinNoun(.transaction)
        d["transacton"] = .bitcoinNoun(.transaction); d["trnsaction"] = .bitcoinNoun(.transaction)
        d["trasnsaction"] = .bitcoinNoun(.transaction); d["transation"] = .bitcoinNoun(.transaction)
        d["transaciton"] = .bitcoinNoun(.transaction); d["tansaction"] = .bitcoinNoun(.transaction)
        d["transacion"] = .bitcoinNoun(.transaction)
        d["satoshie"] = .bitcoinUnit; d["satoshies"] = .bitcoinUnit; d["satoshe"] = .bitcoinUnit
        d["bitcion"] = .bitcoinUnit; d["bitconi"] = .bitcoinUnit
        d["bitocin"] = .bitcoinUnit; d["bicoin"] = .bitcoinUnit; d["biticoin"] = .bitcoinUnit
        d["walet"] = .bitcoinNoun(.wallet); d["wallett"] = .bitcoinNoun(.wallet)
        d["walett"] = .bitcoinNoun(.wallet); d["walllet"] = .bitcoinNoun(.wallet)
        d["sendd"] = .walletVerb(.send); d["sned"] = .walletVerb(.send)
        d["sedn"] = .walletVerb(.send); d["snde"] = .walletVerb(.send)
        d["trasfer"] = .walletVerb(.send); d["trasnfer"] = .walletVerb(.send)
        d["tranfer"] = .walletVerb(.send); d["tansfer"] = .walletVerb(.send)
        d["feee"] = .bitcoinNoun(.fee); d["fess"] = .bitcoinNoun(.fees)
        d["histroy"] = .bitcoinNoun(.history); d["histry"] = .bitcoinNoun(.history)
        d["pirce"] = .bitcoinNoun(.price); d["prise"] = .bitcoinNoun(.price)
        d["pric"] = .bitcoinNoun(.price)

        // =================================================================
        // COMPARATIVES / DIRECTION
        // =================================================================
        for (w, dir) in [
            ("more", Direction.more), ("less", .less),
            ("bigger", .bigger), ("larger", .bigger), ("greater", .bigger),
            ("smaller", .smaller), ("tinier", .smaller),
            ("faster", .faster), ("quicker", .faster), ("speedier", .faster),
            ("slower", .slower), ("cheaper", .cheaper), ("pricier", .more),
            ("higher", .higher), ("lower", .lower),
            ("up", .up), ("down", .down),
            ("increase", .increase), ("decrease", .decrease),
            ("raise", .raise), ("reduce", .reduce),
            ("grow", .increase), ("shrink", .decrease),
            ("climb", .increase), ("fall", .decrease),
            ("rise", .increase), ("sink", .decrease),
            ("expand", .increase), ("contract", .decrease), ("drop", .decrease),
        ] as [(String, Direction)] {
            d[w] = .comparative(dir)
        }
        d["cheapest"] = .comparative(.cheaper); d["fastest"] = .comparative(.faster)
        d["slowest"] = .comparative(.slower); d["highest"] = .comparative(.higher)
        d["lowest"] = .comparative(.lower); d["biggest"] = .comparative(.bigger)
        d["smallest"] = .comparative(.smaller)

        // =================================================================
        // QUANTIFIERS
        // =================================================================
        for (w, q) in [
            ("all", Quantity.all), ("everything", .all), ("entire", .all),
            ("whole", .all), ("full", .all), ("total", .all), ("complete", .all),
            ("completely", .all), ("entirely", .all),
            ("max", .maximum), ("maximum", .maximum), ("min", .minimum), ("minimum", .minimum),
            ("some", .some), ("none", .none),
            ("half", .half), ("double", .double), ("triple", .triple),
            ("most", .most), ("few", .few), ("several", .few),
            ("every", .every), ("each", .every),
            ("remaining", .remaining), ("rest", .rest), ("leftover", .remaining),
            ("bunch", .some), ("lot", .some), ("lots", .some), ("plenty", .some),
            ("many", .most), ("much", .most),
            ("little", .few), ("bit", .few), ("tiny", .few),
            ("only", .few), ("just", .few),
        ] as [(String, Quantity)] {
            d[w] = .quantifier(q)
        }

        // =================================================================
        // EVALUATIVES
        // =================================================================
        // Good
        d["good"] = .evaluative(.good); d["great"] = .evaluative(.good)
        d["nice"] = .evaluative(.good); d["excellent"] = .evaluative(.good)
        d["wonderful"] = .evaluative(.good); d["superb"] = .evaluative(.good)
        d["outstanding"] = .evaluative(.good); d["marvelous"] = .evaluative(.good)
        d["marvellous"] = .evaluative(.good); d["splendid"] = .evaluative(.good)
        d["stellar"] = .evaluative(.good); d["exceptional"] = .evaluative(.good)
        d["terrific"] = .evaluative(.good); d["fabulous"] = .evaluative(.good)
        d["magnificent"] = .evaluative(.good); d["solid"] = .evaluative(.good)
        d["sounds_good"] = .evaluative(.good); d["not_bad"] = .evaluative(.good)
        d["looks_good"] = .evaluative(.good); d["all_good"] = .evaluative(.good)
        d["thats_great"] = .evaluative(.good)
        d["well"] = .evaluative(.good); d["really"] = .evaluative(.good)
        d["very"] = .evaluative(.good); d["quite"] = .evaluative(.good)
        d["pretty"] = .evaluative(.good); d["super"] = .evaluative(.good)
        d["extremely"] = .evaluative(.good)
        // Bad
        d["bad"] = .evaluative(.bad); d["terrible"] = .evaluative(.bad)
        d["awful"] = .evaluative(.bad); d["horrible"] = .evaluative(.bad)
        d["poor"] = .evaluative(.bad); d["weak"] = .evaluative(.bad)
        d["trash"] = .evaluative(.bad); d["garbage"] = .evaluative(.bad)
        d["gross"] = .evaluative(.bad); d["disgusting"] = .evaluative(.bad)
        d["dreadful"] = .evaluative(.bad); d["atrocious"] = .evaluative(.bad)
        d["pathetic"] = .evaluative(.bad); d["lousy"] = .evaluative(.bad)
        d["crappy"] = .evaluative(.bad); d["rubbish"] = .evaluative(.bad)
        d["not_sure"] = .evaluative(.bad)
        // Enough / Too Much / Too Little
        d["enough"] = .evaluative(.enough); d["good_enough"] = .evaluative(.enough)
        d["sufficient"] = .evaluative(.enough); d["adequate"] = .evaluative(.enough)
        d["not_enough"] = .evaluative(.tooLittle); d["insufficient"] = .evaluative(.tooLittle)
        d["too_little"] = .evaluative(.tooLittle); d["too_low"] = .evaluative(.tooLittle)
        d["pittance"] = .evaluative(.tooLittle); d["meager"] = .evaluative(.tooLittle)
        d["thats_too_little"] = .evaluative(.tooLittle); d["thats_too_low"] = .evaluative(.tooLittle)
        d["too_much"] = .evaluative(.tooMuch); d["excessive"] = .evaluative(.tooMuch)
        d["overkill"] = .evaluative(.tooMuch); d["too_high"] = .evaluative(.tooMuch)
        d["overpriced"] = .evaluative(.tooMuch)
        d["thats_too_much"] = .evaluative(.tooMuch); d["thats_too_high"] = .evaluative(.tooMuch)
        // Expensive / Cheap
        d["expensive"] = .evaluative(.expensive); d["costly"] = .evaluative(.expensive)
        d["pricey"] = .evaluative(.expensive); d["steep"] = .evaluative(.expensive)
        d["exorbitant"] = .evaluative(.expensive); d["extortionate"] = .evaluative(.expensive)
        d["too_expensive"] = .evaluative(.expensive); d["thats_too_expensive"] = .evaluative(.expensive)
        d["cheap"] = .evaluative(.cheap); d["affordable"] = .evaluative(.cheap)
        d["inexpensive"] = .evaluative(.cheap); d["budget"] = .evaluative(.cheap)
        d["bargain"] = .evaluative(.cheap); d["economical"] = .evaluative(.cheap)
        d["too_cheap"] = .evaluative(.cheap); d["thats_too_cheap"] = .evaluative(.cheap)
        // Safe / Risky
        d["safe"] = .evaluative(.safe); d["secure"] = .evaluative(.safe)
        d["trusted"] = .evaluative(.safe); d["reliable"] = .evaluative(.safe)
        d["protected"] = .evaluative(.safe); d["is_it_safe"] = .evaluative(.safe)
        d["risky"] = .evaluative(.risky); d["dangerous"] = .evaluative(.risky)
        d["sketchy"] = .evaluative(.risky); d["shady"] = .evaluative(.risky)
        d["suspicious"] = .evaluative(.risky); d["dodgy"] = .evaluative(.risky)
        d["unsafe"] = .evaluative(.risky); d["insecure"] = .evaluative(.risky)
        d["vulnerable"] = .evaluative(.risky)
        // Correct / Wrong / Right / Fine / OK / Perfect
        d["correct"] = .evaluative(.correct); d["accurate"] = .evaluative(.correct)
        d["proper"] = .evaluative(.correct); d["valid"] = .evaluative(.correct)
        d["wrong"] = .evaluative(.wrong); d["incorrect"] = .evaluative(.wrong)
        d["invalid"] = .evaluative(.wrong); d["inaccurate"] = .evaluative(.wrong)
        d["right"] = .evaluative(.right)
        d["fine"] = .evaluative(.fine); d["thats_fine"] = .evaluative(.fine)
        d["ok"] = .evaluative(.ok); d["alright"] = .evaluative(.ok)
        d["acceptable"] = .evaluative(.ok); d["decent"] = .evaluative(.ok)
        d["thats_ok"] = .evaluative(.ok)
        d["normal"] = .evaluative(.fine); d["standard"] = .evaluative(.fine)
        d["regular"] = .evaluative(.fine); d["default"] = .evaluative(.fine)
        d["moderate"] = .evaluative(.fine); d["average"] = .evaluative(.fine)
        d["typical"] = .evaluative(.fine); d["ordinary"] = .evaluative(.fine)
        d["perfect"] = .evaluative(.perfect); d["ideal"] = .evaluative(.perfect)
        d["flawless"] = .evaluative(.perfect); d["thats_perfect"] = .evaluative(.perfect)
        d["reasonable"] = .evaluative(.reasonable); d["fair"] = .evaluative(.fair)
        d["high"] = .evaluative(.high); d["low"] = .evaluative(.low)
        d["too_slow"] = .evaluative(.bad); d["too_fast"] = .evaluative(.bad)
        d["thats_too_slow"] = .evaluative(.bad)
        d["fast"] = .evaluative(.good); d["slow"] = .evaluative(.bad)
        d["quick"] = .evaluative(.good)

        // =================================================================
        // DIRECTIONALS / NAVIGATION
        // =================================================================
        d["back"] = .directional(.back); d["forward"] = .directional(.forward)
        d["again"] = .directional(.again); d["do_again"] = .directional(.again)
        d["next"] = .directional(.next); d["previous"] = .directional(.previous)
        d["prev"] = .directional(.previous)
        d["last"] = .directional(.last); d["first"] = .directional(.first)
        d["latest"] = .directional(.latest); d["newest"] = .directional(.newest)
        d["oldest"] = .directional(.oldest); d["recent"] = .directional(.latest)
        d["top"] = .directional(.first); d["bottom"] = .directional(.last)
        d["ordinal_1"] = .directional(.first); d["ordinal_2"] = .directional(.next)
        d["ordinal_3"] = .directional(.next); d["ordinal_last"] = .directional(.last)

        // =================================================================
        // TEMPORAL
        // =================================================================
        d["now"] = .temporal(.now); d["right_now"] = .temporal(.now)
        d["come_on"] = .temporal(.now); d["right_away"] = .temporal(.now)
        d["immediately"] = .temporal(.now); d["asap_phrase"] = .temporal(.now)
        d["instantly"] = .temporal(.now); d["currently"] = .temporal(.now)
        d["presently"] = .temporal(.now)
        d["later"] = .temporal(.later); d["eventually"] = .temporal(.later)
        d["someday"] = .temporal(.later); d["in_a_bit"] = .temporal(.later)
        d["soon"] = .temporal(.soon); d["shortly"] = .temporal(.soon)
        d["momentarily"] = .temporal(.soon); d["upcoming"] = .temporal(.soon)
        d["yesterday"] = .temporal(.yesterday); d["a_while_ago"] = .temporal(.yesterday)
        d["today"] = .temporal(.today); d["tonight"] = .temporal(.today)
        d["tomorrow"] = .temporal(.tomorrow)
        d["recently"] = .temporal(.recently); d["lately"] = .temporal(.recently)
        d["last_time"] = .temporal(.recently)
        d["already"] = .temporal(.already); d["yet"] = .temporal(.yet)
        d["before"] = .temporal(.before); d["after"] = .temporal(.after)
        d["always"] = .temporal(.always)
        d["still"] = .temporal(.already); d["ago"] = .temporal(.before)
        d["past"] = .temporal(.before); d["once"] = .temporal(.before)

        // =================================================================
        // NEGATION
        // =================================================================
        for w in ["not", "no", "don't", "dont", "doesn't", "doesnt",
                   "won't", "wont", "can't", "cant", "cannot",
                   "never", "nothing", "nobody", "nowhere", "neither", "nor",
                   "nope", "nah", "naw", "negative", "denied",
                   "isn't", "isnt", "aren't", "arent",
                   "wasn't", "wasnt", "weren't", "werent",
                   "hasn't", "hasnt", "haven't", "havent", "hadn't", "hadnt",
                   "wouldn't", "wouldnt", "couldn't", "couldnt",
                   "shouldn't", "shouldnt", "mustn't", "mustnt",
                   "no_way", "of_course_not", "not_at_all", "hell_no",
                   "\u{0644}\u{0627}", "\u{0645}\u{0634}", "\u{0644}\u{064A}\u{0633}",
                   "nunca", "nada", "nadie", "ninguno", "tampoco",
                   "jam\u{00E1}s", "jamas",
                   // French
                   "non", "pas", "jamais", "rien", "personne", "aucun"] {
            d[w] = .negation
        }

        // =================================================================
        // AFFIRMATION
        // =================================================================
        for w in ["yes", "yeah", "yep", "yup", "yea", "ya", "ye", "yah",
                   "ok", "okay", "k", "kk",
                   "sure", "surely", "certainly",
                   "absolutely", "definitely", "exactly", "precisely",
                   "agreed", "proceed", "approved",
                   "affirmative", "roger", "aye", "indeed",
                   "obviously", "naturally", "undoubtedly",
                   "y", "go_ahead", "let's_go",
                   "go_for_it", "send_it", "do_it", "lets_do_it", "im_in",
                   "bet", "lfg", "lgtm", "aight", "ight",
                   "yessir", "yass", "yasss", "leggo", "lesgo", "word",
                   "copy", "copy_that", "got_it",
                   "of_course", "for_sure", "why_not", "you_bet",
                   "hell_yeah", "hell_yes", "totally",
                   "\u{0646}\u{0639}\u{0645}", "\u{0623}\u{0643}\u{064A}\u{062F}",
                   "\u{062A}\u{0645}\u{0627}\u{0645}", "\u{0645}\u{0648}\u{0627}\u{0641}\u{0642}",
                   "\u{064A}\u{0644}\u{0627}", "\u{0627}\u{0647}", "\u{0627}\u{064A}\u{0648}\u{0627}",
                   "s\u{00ED}", "si", "dale", "claro", "correcto", "bueno",
                   "exacto", "vale", "venga",
                   // French
                   "oui", "ouais", "bien s\u{00FB}r", "d'accord", "exactement",
                   "absolument", "parfait", "entendu"] {
            d[w] = .affirmation
        }

        // =================================================================
        // GREETINGS
        // =================================================================
        for w in ["hi", "hello", "hey", "yo", "sup", "howdy", "hiya", "heya",
                   "g'day", "gday", "greetings", "aloha", "ahoy",
                   "good_morning", "good_afternoon", "good_evening", "good_night",
                   "morning", "afternoon", "evening", "gm", "gn",
                   "what's_up", "what's_good", "what's_happening",
                   "how's_it_going", "how_ya_doing",
                   "wassup", "wazzup", "whaddup", "waddup",
                   "\u{0645}\u{0631}\u{062D}\u{0628}\u{0627}", "\u{0623}\u{0647}\u{0644}\u{0627}",
                   "\u{0627}\u{0644}\u{0633}\u{0644}\u{0627}\u{0645}",
                   "hola", "buenos_dias", "buenas_tardes", "buenas_noches",
                   // French
                   "bonjour", "bonsoir", "salut", "coucou"] {
            d[w] = .greeting
        }

        // =================================================================
        // FAREWELLS (classified as greeting — AIThinkingRules differentiates)
        // =================================================================
        for w in ["goodbye", "bye", "farewell", "cya", "laterz",
                   "see_you", "see_ya", "see_you_later", "take_care",
                   "catch_you_later", "peace", "adios", "ciao",
                   "au_revoir", "hasta_luego"] {
            d[w] = .greeting
        }

        // =================================================================
        // BITCOIN NOUNS
        // =================================================================
        // Balance
        d["balance"] = .bitcoinNoun(.balance); d["funds"] = .bitcoinNoun(.balance)
        d["money"] = .bitcoinNoun(.balance); d["coins"] = .bitcoinNoun(.balance)
        d["holdings"] = .bitcoinNoun(.balance); d["portfolio"] = .bitcoinNoun(.balance)
        d["stash"] = .bitcoinNoun(.balance); d["stack"] = .bitcoinNoun(.balance)
        d["bag"] = .bitcoinNoun(.balance); d["amount"] = .bitcoinNoun(.balance)
        d["savings"] = .bitcoinNoun(.balance); d["wealth"] = .bitcoinNoun(.balance)
        d["assets"] = .bitcoinNoun(.balance); d["reserves"] = .bitcoinNoun(.balance)
        d["bankroll"] = .bitcoinNoun(.balance); d["available"] = .bitcoinNoun(.balance)
        d["spendable"] = .bitcoinNoun(.balance); d["am_i_rich"] = .bitcoinNoun(.balance)
        d["\u{0631}\u{0635}\u{064A}\u{062F}"] = .bitcoinNoun(.balance)
        d["\u{0631}\u{0635}\u{064A}\u{062F}\u{064A}"] = .bitcoinNoun(.balance)
        d["saldo"] = .bitcoinNoun(.balance)
        d["solde"] = .bitcoinNoun(.balance) // French
        // Fee / Fees
        d["fee"] = .bitcoinNoun(.fee); d["fees"] = .bitcoinNoun(.fees)
        d["gas"] = .bitcoinNoun(.fees); d["cost"] = .bitcoinNoun(.fees)
        d["charge"] = .bitcoinNoun(.fees); d["charges"] = .bitcoinNoun(.fees)
        d["rate"] = .bitcoinNoun(.fees); d["rates"] = .bitcoinNoun(.fees)
        d["priority"] = .bitcoinNoun(.fees); d["commission"] = .bitcoinNoun(.fees)
        d["sats_per_byte"] = .bitcoinNoun(.fees)
        d["how_much_to_send"] = .bitcoinNoun(.fees); d["how_much_cost"] = .bitcoinNoun(.fees)
        d["\u{0631}\u{0633}\u{0648}\u{0645}"] = .bitcoinNoun(.fees)
        d["\u{0627}\u{0644}\u{0631}\u{0633}\u{0648}\u{0645}"] = .bitcoinNoun(.fees) // الرسوم
        d["comisiones"] = .bitcoinNoun(.fees) // Spanish
        d["frais"] = .bitcoinNoun(.fees) // French
        // Address
        d["address"] = .bitcoinNoun(.address); d["addr"] = .bitcoinNoun(.address)
        d["destination"] = .bitcoinNoun(.address); d["recipient"] = .bitcoinNoun(.address)
        d["receiver"] = .bitcoinNoun(.address); d["qr"] = .bitcoinNoun(.address)
        d["qrcode"] = .bitcoinNoun(.address)
        d["\u{0639}\u{0646}\u{0648}\u{0627}\u{0646}"] = .bitcoinNoun(.address)
        d["direcci\u{00F3}n"] = .bitcoinNoun(.address); d["direccion"] = .bitcoinNoun(.address)
        d["adresse"] = .bitcoinNoun(.address) // French
        // Transaction / Transactions
        d["transaction"] = .bitcoinNoun(.transaction); d["tx"] = .bitcoinNoun(.transaction)
        d["txid"] = .bitcoinNoun(.transaction); d["txn"] = .bitcoinNoun(.transaction)
        d["payment"] = .bitcoinNoun(.transaction); d["receipt"] = .bitcoinNoun(.transaction)
        d["transactions"] = .bitcoinNoun(.transactions); d["transfers"] = .bitcoinNoun(.transactions)
        d["payments"] = .bitcoinNoun(.transactions); d["receipts"] = .bitcoinNoun(.transactions)
        d["txns"] = .bitcoinNoun(.transactions); d["txs"] = .bitcoinNoun(.transactions)
        // Confirmation / Confirmations
        d["confirmation"] = .bitcoinNoun(.confirmation); d["conf"] = .bitcoinNoun(.confirmation)
        d["confirmations"] = .bitcoinNoun(.confirmations); d["confs"] = .bitcoinNoun(.confirmations)
        d["confirmed"] = .bitcoinNoun(.confirmations); d["unconfirmed"] = .bitcoinNoun(.confirmations)
        // UTXO
        d["utxo"] = .bitcoinNoun(.utxo); d["utxos"] = .bitcoinNoun(.utxos)
        d["coin"] = .bitcoinNoun(.utxo)
        d["input"] = .bitcoinNoun(.utxo); d["inputs"] = .bitcoinNoun(.utxos)
        d["output"] = .bitcoinNoun(.utxo); d["outputs"] = .bitcoinNoun(.utxos)
        d["unspent"] = .bitcoinNoun(.utxos)
        // Price
        d["price"] = .bitcoinNoun(.price); d["value"] = .bitcoinNoun(.price)
        d["worth"] = .bitcoinNoun(.price); d["trading"] = .bitcoinNoun(.price)
        d["market"] = .bitcoinNoun(.price); d["quote"] = .bitcoinNoun(.price)
        d["ticker"] = .bitcoinNoun(.price); d["spot"] = .bitcoinNoun(.price)
        d["\u{0633}\u{0639}\u{0631}"] = .bitcoinNoun(.price); d["precio"] = .bitcoinNoun(.price)
        d["\u{0627}\u{0644}\u{0633}\u{0639}\u{0631}"] = .bitcoinNoun(.price) // السعر
        d["prix"] = .bitcoinNoun(.price) // French
        // Block
        d["block"] = .bitcoinNoun(.block); d["blocks"] = .bitcoinNoun(.block)
        d["blockheight"] = .bitcoinNoun(.block); d["block_height"] = .bitcoinNoun(.block)
        // Wallet
        d["wallet"] = .bitcoinNoun(.wallet); d["purse"] = .bitcoinNoun(.wallet)
        d["account"] = .bitcoinNoun(.wallet); d["vault"] = .bitcoinNoun(.wallet)
        d["health_check"] = .bitcoinNoun(.wallet)
        d["\u{0645}\u{062D}\u{0641}\u{0638}\u{0629}"] = .bitcoinNoun(.wallet)
        d["cartera"] = .bitcoinNoun(.wallet); d["billetera"] = .bitcoinNoun(.wallet)
        d["portefeuille"] = .bitcoinNoun(.wallet) // French
        // Network
        d["network"] = .bitcoinNoun(.network); d["status"] = .bitcoinNoun(.network)
        d["blockchain"] = .bitcoinNoun(.network); d["chain"] = .bitcoinNoun(.network)
        d["node"] = .bitcoinNoun(.network); d["nodes"] = .bitcoinNoun(.network)
        d["congested"] = .bitcoinNoun(.network); d["congestion"] = .bitcoinNoun(.network)
        d["connected"] = .bitcoinNoun(.network); d["disconnected"] = .bitcoinNoun(.network)
        d["online"] = .bitcoinNoun(.network); d["offline"] = .bitcoinNoun(.network)
        d["connectivity"] = .bitcoinNoun(.network)
        d["decentralized"] = .bitcoinNoun(.network); d["decentralised"] = .bitcoinNoun(.network)
        d["mainnet"] = .bitcoinNoun(.network); d["testnet"] = .bitcoinNoun(.network)
        d["difficulty"] = .bitcoinNoun(.network)
        d["\u{0634}\u{0628}\u{0643}\u{0629}"] = .bitcoinNoun(.network)
        // Mempool
        d["mempool"] = .bitcoinNoun(.mempool); d["backlog"] = .bitcoinNoun(.mempool)
        // Mining
        d["mining"] = .bitcoinNoun(.mining); d["miner"] = .bitcoinNoun(.mining)
        d["miners"] = .bitcoinNoun(.mining); d["hashrate"] = .bitcoinNoun(.mining)
        d["hash_rate"] = .bitcoinNoun(.mining); d["hashing"] = .bitcoinNoun(.mining)
        d["nonce"] = .bitcoinNoun(.mining); d["pow"] = .bitcoinNoun(.mining)
        d["\u{062A}\u{0639}\u{062F}\u{064A}\u{0646}"] = .bitcoinNoun(.mining)
        // Halving / Segwit / Taproot / Lightning
        d["halving"] = .bitcoinNoun(.halving); d["halvening"] = .bitcoinNoun(.halving)
        d["segwit"] = .bitcoinNoun(.segwit); d["bech32"] = .bitcoinNoun(.segwit)
        d["taproot"] = .bitcoinNoun(.taproot); d["schnorr"] = .bitcoinNoun(.taproot)
        d["lightning"] = .bitcoinNoun(.lightning); d["ln"] = .bitcoinNoun(.lightning)
        d["lnurl"] = .bitcoinNoun(.lightning); d["bolt11"] = .bitcoinNoun(.lightning)
        // Seed / Key
        d["seed"] = .bitcoinNoun(.seed); d["mnemonic"] = .bitcoinNoun(.seed)
        d["seed_phrase"] = .bitcoinNoun(.seed); d["recovery_phrase"] = .bitcoinNoun(.seed)
        d["passphrase"] = .bitcoinNoun(.seed)
        d["key"] = .bitcoinNoun(.key); d["keys"] = .bitcoinNoun(.key)
        d["private_key"] = .bitcoinNoun(.key); d["public_key"] = .bitcoinNoun(.key)
        d["privkey"] = .bitcoinNoun(.key); d["pubkey"] = .bitcoinNoun(.key)
        d["xpub"] = .bitcoinNoun(.key); d["xprv"] = .bitcoinNoun(.key)
        d["zpub"] = .bitcoinNoun(.key); d["ypub"] = .bitcoinNoun(.key)
        // Signature
        d["signature"] = .bitcoinNoun(.signature); d["sig"] = .bitcoinNoun(.signature)
        d["signed"] = .bitcoinNoun(.signature); d["signing"] = .bitcoinNoun(.signature)
        d["multisig"] = .bitcoinNoun(.signature)
        // History
        d["history"] = .bitcoinNoun(.history); d["activity"] = .bitcoinNoun(.history)
        d["log"] = .bitcoinNoun(.history); d["record"] = .bitcoinNoun(.history)
        d["records"] = .bitcoinNoun(.history); d["ledger"] = .bitcoinNoun(.history)
        d["received"] = .bitcoinNoun(.history); d["pending"] = .bitcoinNoun(.history)
        d["outgoing"] = .bitcoinNoun(.history); d["inbound"] = .bitcoinNoun(.history)
        d["outbound"] = .bitcoinNoun(.history)
        d["\u{0633}\u{062C}\u{0644}"] = .bitcoinNoun(.history); d["historial"] = .bitcoinNoun(.history)
        d["historique"] = .bitcoinNoun(.history) // French
        // Settings
        d["settings"] = .unknown("settings_intent"); d["preferences"] = .unknown("settings_intent")
        d["options"] = .unknown("settings_intent"); d["config"] = .unknown("settings_intent")
        d["configuration"] = .unknown("settings_intent")

        // =================================================================
        // FEE-LEVEL TOKENS
        // =================================================================
        d["use_slow_fee"] = .unknown("fee_level:slow")
        d["use_fast_fee"] = .unknown("fee_level:fast")
        d["use_medium_fee"] = .unknown("fee_level:medium")
        d["change_amount"] = .unknown("change_amount")
        // Bare fee-level words: override earlier bitcoinNoun mappings so that
        // standalone "priority" / "economy" select a fee level instead of
        // merely showing fee estimates.
        d["priority"] = .unknown("fee_level:fast")
        d["economy"] = .unknown("fee_level:slow")
        d["economical"] = .unknown("fee_level:slow")

        // =================================================================
        // WORD NUMBERS
        // =================================================================
        let wordNumbers: [(String, Decimal)] = [
            ("zero", 0), ("one", 1), ("two", 2), ("three", 3), ("four", 4), ("five", 5),
            ("six", 6), ("seven", 7), ("eight", 8), ("nine", 9), ("ten", 10),
            ("eleven", 11), ("twelve", 12), ("thirteen", 13), ("fourteen", 14),
            ("fifteen", 15), ("sixteen", 16), ("seventeen", 17), ("eighteen", 18),
            ("nineteen", 19), ("twenty", 20), ("thirty", 30), ("forty", 40),
            ("fifty", 50), ("sixty", 60), ("seventy", 70), ("eighty", 80),
            ("ninety", 90), ("hundred", 100), ("thousand", 1000),
            ("million", 1_000_000), ("billion", 1_000_000_000),
            ("k", 1000), ("mil", 1_000_000),
        ]
        for (w, n) in wordNumbers { d[w] = .number(n) }

        // =================================================================
        // BITCOIN UNITS
        // =================================================================
        for w in ["btc", "bitcoin", "bitcoins", "sat", "sats", "satoshi", "satoshis",
                   "bits", "mbtc", "millibitcoin", "microbitcoin",
                   "\u{0628}\u{062A}\u{0643}\u{0648}\u{064A}\u{0646}",
                   "\u{0633}\u{0627}\u{062A}\u{0648}\u{0634}\u{064A}",
                   "bitcoines"] {
            d[w] = .bitcoinUnit
        }

        // =================================================================
        // EMOTIONS
        // =================================================================
        // Gratitude
        for w in ["thanks", "thank", "thx", "ty", "appreciate", "grateful",
                   "thankful", "cheers", "ta", "much_appreciated",
                   "thank_you", "thanks_a_lot", "thank_you_so_much",
                   "bless", "blessed", "kudos", "props",
                   "\u{0634}\u{0643}\u{0631}\u{0627}", "\u{0645}\u{0645}\u{0646}\u{0648}\u{0646}",
                   "gracias", "merci", "danke", "grazie", "obrigado",
                   "arigatou", "arigato", "por_favor"] {
            d[w] = .emotion(.gratitude)
        }
        // Frustration
        for w in ["ugh", "annoyed", "frustrated", "frustrating", "broken",
                   "stupid", "wtf", "useless", "damn", "dammit", "damnit",
                   "sucks", "crap", "shit", "fml",
                   "seriously", "smh", "bruh", "ffs", "jfc",
                   "ridiculous", "unbelievable", "absurd",
                   "infuriating", "maddening", "aggravating",
                   "rage", "furious", "angry", "pissed", "livid",
                   "that_sucks", "for_real"] {
            d[w] = .emotion(.frustration)
        }
        // Confusion
        for w in ["confused", "lost", "huh", "idk", "meh", "hmm", "hm",
                   "umm", "um", "dunno", "wdym", "wym", "eh",
                   "puzzled", "baffled", "bewildered", "perplexed",
                   "clueless", "stumped", "unclear", "unsure", "no_idea",
                   "\u{1F914}"] {
            d[w] = .emotion(.confusion)
        }
        // Excitement
        for w in ["awesome", "amazing", "cool", "wow", "sweet", "yay",
                   "brilliant", "love", "fantastic", "incredible",
                   "dope", "sick", "fire", "lit", "epic",
                   "woohoo", "woo", "omg", "holy",
                   "unreal", "legendary", "goat", "phenomenal", "mindblowing",
                   "stoked", "hyped", "pumped", "thrilled", "ecstatic",
                   "nice_one", "love_it", "to_the_moon",
                   "stacking_sats", "stack_sats", "diamond_hands"] {
            d[w] = .emotion(.excitement)
        }
        // Humor
        for w in ["lol", "lmao", "lmfao", "rofl", "haha", "hahaha",
                   "hehe", "hehehe", "funny", "joke", "joking",
                   "kidding", "jk", "jest", "hilarious",
                   "\u{1F602}", "\u{1F923}"] {
            d[w] = .emotion(.humor)
        }
        // Concern
        for w in ["worried", "scared", "nervous", "concerned", "afraid",
                   "oops", "yikes", "oh_no", "sorry",
                   "anxious", "uneasy", "apprehensive", "fearful",
                   "cautious", "careful", "beware",
                   "warning", "caution", "alert",
                   "worrying", "alarming", "troubling",
                   "paranoid", "terrified", "panicking", "freaking",
                   "paper_hands"] {
            d[w] = .emotion(.concern)
        }
        // Impatience
        for w in ["hurry", "hurry_up", "speed_up", "cmon", "c'mon", "asap", "asap_phrase",
                   "waiting", "waited", "forever", "ages",
                   "taking", "sluggish", "laggy", "stuck",
                   "eta", "progress", "rush", "urgent"] {
            d[w] = .emotion(.impatience)
        }

        // =================================================================
        // CURRENCY WORDS
        // =================================================================
        for w in ["dollars", "dollar", "bucks", "usd", "greenbacks", "buck"] {
            d[w] = .unknown("currency:USD")
        }
        for w in ["euros", "euro", "eur"] { d[w] = .unknown("currency:EUR") }
        for w in ["pounds", "pound", "gbp", "quid", "sterling"] { d[w] = .unknown("currency:GBP") }
        for w in ["yen", "jpy"] { d[w] = .unknown("currency:JPY") }
        for w in ["cad", "canadian", "loonie"] { d[w] = .unknown("currency:CAD") }
        for w in ["aud", "australian"] { d[w] = .unknown("currency:AUD") }
        for w in ["chf", "franc", "francs", "swiss"] { d[w] = .unknown("currency:CHF") }
        for w in ["yuan", "cny", "renminbi", "rmb"] { d[w] = .unknown("currency:CNY") }
        for w in ["rupee", "rupees", "inr"] { d[w] = .unknown("currency:INR") }
        for w in ["real", "reais", "brl", "brazilian"] { d[w] = .unknown("currency:BRL") }
        for w in ["peso", "pesos", "mxn", "mexican"] { d[w] = .unknown("currency:MXN") }
        for w in ["won", "krw", "korean"] { d[w] = .unknown("currency:KRW") }
        for w in ["sek", "swedish", "krona", "kronor"] { d[w] = .unknown("currency:SEK") }
        for w in ["nok", "norwegian", "krone", "kroner"] { d[w] = .unknown("currency:NOK") }
        for w in ["dkk", "danish"] { d[w] = .unknown("currency:DKK") }
        for w in ["sgd", "singapore"] { d[w] = .unknown("currency:SGD") }
        for w in ["nzd", "kiwi"] { d[w] = .unknown("currency:NZD") }
        for w in ["lira", "turkish"] { d[w] = .unknown("currency:TRY") }
        for w in ["ruble", "rubles", "rub", "russian"] { d[w] = .unknown("currency:RUB") }
        for w in ["rand", "zar"] { d[w] = .unknown("currency:ZAR") }
        for w in ["zloty", "pln", "polish"] { d[w] = .unknown("currency:PLN") }
        for w in ["baht", "thb", "thai"] { d[w] = .unknown("currency:THB") }
        for w in ["dirham", "dirhams", "aed", "emirati"] { d[w] = .unknown("currency:AED") }
        for w in ["riyal", "riyals", "sar", "saudi"] { d[w] = .unknown("currency:SAR") }
        for w in ["php", "philippine"] { d[w] = .unknown("currency:PHP") }
        for w in ["twd", "taiwan"] { d[w] = .unknown("currency:TWD") }
        for w in ["fiat", "cash", "currency", "currencies"] { d[w] = .unknown("currency:USD") }

        // =================================================================
        // CRYPTO SLANG
        // =================================================================
        d["hodl"] = .walletVerb(.backup); d["hodling"] = .walletVerb(.backup)
        d["hodler"] = .walletVerb(.backup)
        d["moon"] = .emotion(.excitement); d["mooning"] = .emotion(.excitement)
        d["rekt"] = .emotion(.frustration)
        d["whale"] = .bitcoinNoun(.balance)
        d["fomo"] = .emotion(.concern); d["fud"] = .emotion(.frustration)
        d["ath"] = .bitcoinNoun(.price); d["atl"] = .bitcoinNoun(.price)
        d["dip"] = .comparative(.lower); d["pump"] = .comparative(.higher)
        d["dump"] = .comparative(.lower)
        d["bull"] = .evaluative(.good); d["bullish"] = .evaluative(.good)
        d["bear"] = .evaluative(.bad); d["bearish"] = .evaluative(.bad)
        d["ngmi"] = .evaluative(.bad); d["wagmi"] = .evaluative(.good)
        d["gwei"] = .bitcoinNoun(.fees)
        d["dca"] = .walletVerb(.receive)
        d["kyc"] = .bitcoinNoun(.wallet); d["defi"] = .bitcoinNoun(.network)
        d["web3"] = .bitcoinNoun(.network)
        d["nft"] = .bitcoinNoun(.transaction); d["ordinal"] = .bitcoinNoun(.transaction)
        d["ordinals"] = .bitcoinNoun(.transactions)
        d["inscription"] = .bitcoinNoun(.transaction); d["inscriptions"] = .bitcoinNoun(.transactions)
        d["saylor"] = .emotion(.excitement); d["nakamoto"] = .emotion(.excitement)
        d["whitepaper"] = .bitcoinNoun(.network); d["genesis"] = .bitcoinNoun(.block)
        d["merkle"] = .bitcoinNoun(.block)
        d["p2p"] = .bitcoinNoun(.network); d["peer"] = .bitcoinNoun(.network)
        d["peers"] = .bitcoinNoun(.network); d["consensus"] = .bitcoinNoun(.network)
        d["fork"] = .bitcoinNoun(.network); d["softfork"] = .bitcoinNoun(.network)
        d["hardfork"] = .bitcoinNoun(.network); d["bip"] = .bitcoinNoun(.network)
        d["psbt"] = .bitcoinNoun(.transaction); d["opreturn"] = .bitcoinNoun(.transaction)
        d["timelock"] = .bitcoinNoun(.transaction); d["locktime"] = .bitcoinNoun(.transaction)
        d["dustlimit"] = .bitcoinNoun(.fees); d["dust"] = .bitcoinNoun(.fees)
        d["lambo"] = .emotion(.excitement)

        // =================================================================
        // CONVERSATIONAL PHRASE TOKENS
        // =================================================================
        d["can_you"] = .modal(.can)
        d["do_i_have"] = .unknown("ownership"); d["i_have"] = .unknown("ownership")
        d["i_own"] = .unknown("ownership"); d["i_got"] = .unknown("ownership")
        d["in_my_wallet"] = .unknown("ownership"); d["do_i_need"] = .unknown("ownership")
        d["howmuch_ownership_btc"] = .unknown("howmuch_ownership_btc")
        d["howmuch_ownership"] = .unknown("howmuch_ownership")
        d["thats_too"] = .unknown("thats_too")
        d["gimme"] = .walletVerb(.show); d["gimme_my"] = .walletVerb(.show)
        d["show_me"] = .walletVerb(.show)
        d["i_see"] = .affirmation; d["makes_sense"] = .affirmation

        return d
    }()
}
