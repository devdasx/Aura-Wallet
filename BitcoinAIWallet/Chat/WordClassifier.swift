// MARK: - WordClassifier.swift
// Bitcoin AI Wallet
//
// Classifies English words into grammatical and semantic categories.
// ~200-word vocabulary that enables understanding of 10,000+ sentences.
// Each word is mapped to a WordType that carries its grammatical role
// and semantic meaning. Unknown words pass through as unclassified.
//
// Platform: iOS 17.0+
// Framework: Foundation

import Foundation

// MARK: - Sub-Enums

enum QuestionKind: Equatable {
    case what, why, how, when, `where`, which, who
}

enum PronounKind: Equatable {
    case it, that, this, they, one, them, same, last
}

enum ModalKind: Equatable {
    case can, could, should, would, will, might
}

enum WalletAction: Equatable {
    case send, receive, check, show, hide, export, bump
    case refresh, confirm, cancel, convert, detail
}

enum GeneralAction: Equatable {
    case want, need, like, think, know, understand
    case tryAction, afford, wait, helpMe, see, tell, give, have
}

enum ComparisonDirection: Equatable {
    case more, less, faster, slower, cheaper, higher, lower, better, worse
}

enum QuantityKind: Equatable {
    case all, some, none, half, most, few, max, min
}

enum EvaluationKind: Equatable {
    case good, bad, enough, safe, risky, expensive, cheap
    case tooMuch, tooLittle, okay, great
}

enum NavigationDirection: Equatable {
    case back, forward, again, next, previous
}

enum TimeReference: Equatable {
    case now, later, soon, yesterday, today, before, after, recently
}

enum BitcoinConcept: Equatable {
    case balance, fee, address, transaction, utxo, price
    case block, wallet, network, history, amount, money
}

enum WordEmotionType: Equatable {
    case gratitude, frustration, confusion, excitement, humor, concern
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
    case comparative(ComparisonDirection)
    case quantifier(QuantityKind)
    case evaluative(EvaluationKind)
    case directional(NavigationDirection)
    case temporal(TimeReference)

    // Bitcoin domain
    case bitcoinNoun(BitcoinConcept)
    case bitcoinUnit

    // Emotion
    case emotionWord(WordEmotionType)

    // Affirmation / Negation
    case affirmation
    case negation

    // Raw data (extracted at classification time)
    case number(Decimal)
    case bitcoinAddress
    case txid
}

// MARK: - ClassifiedWord

struct ClassifiedWord: Equatable {
    let word: String
    let type: WordType?
    let position: Int
}

// MARK: - WordClassifier

final class WordClassifier {

    // MARK: - Dictionary

    /// Core vocabulary: ~200 words mapped to their grammatical/semantic type.
    private let dictionary: [String: WordType] = {
        var d: [String: WordType] = [:]

        // Question words
        for (w, k) in [
            ("what", QuestionKind.what), ("why", .why), ("how", .how),
            ("when", .when), ("where", .`where`), ("which", .which), ("who", .who)
        ] { d[w] = .questionWord(k) }

        // Pronouns
        for (w, k) in [
            ("it", PronounKind.it), ("that", .that), ("this", .this),
            ("they", .they), ("one", .one), ("them", .them),
            ("same", .same), ("last", .last)
        ] { d[w] = .pronoun(k) }

        // Conjunctions
        for w in ["and", "but", "or", "then", "also"] {
            d[w] = .conjunction
        }

        // Prepositions
        for w in ["to", "from", "for", "in", "at", "with", "about", "of", "into", "on"] {
            d[w] = .preposition
        }

        // Articles / Determiners
        for w in ["the", "a", "an", "my", "your", "our", "its"] {
            d[w] = .article
        }

        // Modals
        for (w, k) in [
            ("can", ModalKind.can), ("could", .could), ("should", .should),
            ("would", .would), ("will", .will), ("might", .might), ("may", .might)
        ] { d[w] = .modal(k) }

        // Wallet verbs
        for (w, k) in [
            ("send", WalletAction.send), ("transfer", .send), ("pay", .send),
            ("receive", .receive), ("get", .receive), ("deposit", .receive),
            ("check", .check), ("show", .show), ("display", .show), ("view", .show),
            ("see", .show), ("look", .show),
            ("hide", .hide), ("export", .export), ("bump", .bump),
            ("refresh", .refresh), ("sync", .refresh), ("update", .refresh),
            ("confirm", .confirm), ("approve", .confirm),
            ("cancel", .cancel), ("stop", .cancel), ("abort", .cancel),
            ("convert", .convert), ("swap", .convert),
            ("detail", .detail), ("details", .detail), ("inspect", .detail)
        ] { d[w] = .walletVerb(k) }

        // General verbs
        for (w, k) in [
            ("want", GeneralAction.want), ("wanna", .want),
            ("need", .need), ("like", .like),
            ("think", .think), ("know", .know), ("understand", .understand),
            ("try", .tryAction), ("afford", .afford),
            ("wait", .wait), ("help", .helpMe),
            ("tell", .tell), ("give", .give), ("have", .have),
            ("has", .have), ("got", .have),
            ("is", .have), ("are", .have), ("am", .have), ("was", .have)
        ] { d[w] = .generalVerb(k) }

        // Comparatives
        for (w, k) in [
            ("more", ComparisonDirection.more), ("less", .less),
            ("faster", .faster), ("quicker", .faster),
            ("slower", .slower), ("cheaper", .cheaper),
            ("higher", .higher), ("lower", .lower),
            ("better", .better), ("worse", .worse),
            ("bigger", .more), ("smaller", .less)
        ] { d[w] = .comparative(k) }

        // Quantifiers
        for (w, k) in [
            ("all", QuantityKind.all), ("everything", .all),
            ("some", .some), ("none", .none), ("nothing", .none),
            ("half", .half), ("most", .most), ("few", .few),
            ("max", .max), ("maximum", .max), ("min", .min), ("minimum", .min)
        ] { d[w] = .quantifier(k) }

        // Evaluatives
        for (w, k) in [
            ("good", EvaluationKind.good), ("great", .great), ("nice", .good),
            ("perfect", .great), ("awesome", .great), ("excellent", .great),
            ("bad", .bad), ("terrible", .bad), ("awful", .bad),
            ("enough", .enough), ("sufficient", .enough),
            ("safe", .safe), ("secure", .safe),
            ("risky", .risky), ("dangerous", .risky), ("unsafe", .risky),
            ("expensive", .expensive), ("costly", .expensive),
            ("cheap", .cheap), ("affordable", .cheap),
            ("okay", .okay), ("ok", .okay), ("fine", .okay),
            ("too", .tooMuch), ("much", .tooMuch)
        ] { d[w] = .evaluative(k) }

        // Directional / Navigation
        for (w, k) in [
            ("back", NavigationDirection.back), ("undo", .back),
            ("forward", .forward), ("redo", .forward),
            ("again", .again), ("repeat", .again),
            ("next", .next), ("previous", .previous)
        ] { d[w] = .directional(k) }

        // Temporal
        for (w, k) in [
            ("now", TimeReference.now), ("immediately", .now), ("right", .now),
            ("later", .later), ("soon", .soon),
            ("yesterday", .yesterday), ("today", .today),
            ("before", .before), ("after", .after),
            ("recently", .recently), ("just", .recently), ("ago", .before)
        ] { d[w] = .temporal(k) }

        // Bitcoin nouns
        for (w, k) in [
            ("balance", BitcoinConcept.balance), ("funds", .balance),
            ("fee", .fee), ("fees", .fee), ("cost", .fee), ("rate", .fee),
            ("address", .address),
            ("transaction", .transaction), ("tx", .transaction), ("transactions", .transaction),
            ("utxo", .utxo), ("utxos", .utxo),
            ("price", .price), ("value", .price), ("worth", .price),
            ("block", .block), ("blocks", .block),
            ("wallet", .wallet),
            ("network", .network), ("mempool", .network),
            ("history", .history),
            ("amount", .amount),
            ("money", .money), ("coin", .money), ("coins", .money),
            ("bitcoin", .money), ("btc", .money)
        ] { d[w] = .bitcoinNoun(k) }

        // Bitcoin units (override money for unit context)
        for w in ["sats", "satoshi", "satoshis", "sat"] {
            d[w] = .bitcoinUnit
        }

        // Emotion words
        for (w, k) in [
            ("thanks", WordEmotionType.gratitude), ("thank", .gratitude),
            ("appreciate", .gratitude), ("grateful", .gratitude),
            ("frustrated", .frustration), ("annoying", .frustration),
            ("ugh", .frustration), ("damn", .frustration),
            ("confused", .confusion), ("confusing", .confusion),
            ("huh", .confusion),
            ("wow", .excitement), ("amazing", .excitement),
            ("cool", .excitement), ("sweet", .excitement),
            ("lol", .humor), ("haha", .humor), ("funny", .humor),
            ("worried", .concern), ("nervous", .concern), ("scared", .concern)
        ] { d[w] = .emotionWord(k) }

        // Affirmations
        for w in ["yes", "yeah", "yep", "yup", "sure", "correct",
                   "absolutely", "definitely", "affirmative", "right"] {
            d[w] = .affirmation
        }

        // Negations
        for w in ["no", "nope", "nah", "never", "not", "don't",
                   "doesn't", "can't", "won't", "wrong", "deny"] {
            d[w] = .negation
        }

        // Arabic wallet verbs
        for (w, k) in [("ارسل", WalletAction.send), ("حول", .send),
                        ("استقبل", .receive), ("استلم", .receive)] {
            d[w] = .walletVerb(k)
        }
        // Arabic bitcoin nouns
        for (w, k) in [("رصيد", BitcoinConcept.balance), ("رصيدي", .balance),
                        ("عنوان", .address), ("سعر", .price),
                        ("رسوم", .fee), ("محفظة", .wallet)] {
            d[w] = .bitcoinNoun(k)
        }
        // Arabic affirmation/negation
        for w in ["نعم", "اه", "ايه", "اكيد"] { d[w] = .affirmation }
        for w in ["لا", "الغاء"] { d[w] = .negation }

        // Spanish wallet verbs
        for (w, k) in [("enviar", WalletAction.send), ("mandar", .send),
                        ("recibir", .receive)] {
            d[w] = .walletVerb(k)
        }
        // Spanish bitcoin nouns
        for (w, k) in [("saldo", BitcoinConcept.balance), ("precio", .price),
                        ("comisión", .fee), ("comision", .fee),
                        ("dirección", .address), ("direccion", .address)] {
            d[w] = .bitcoinNoun(k)
        }
        for w in ["sí", "si", "claro"] { d[w] = .affirmation }

        // Greeting words (map to emotion/excitement as a proxy)
        for w in ["hello", "hi", "hey", "howdy", "hola", "مرحبا",
                   "morning", "evening", "afternoon", "yo", "sup"] {
            d[w] = .emotionWord(.excitement)
        }

        return d
    }()

    // MARK: - Classification

    /// Classifies each word in the input into its grammatical/semantic category.
    func classify(_ text: String) -> [ClassifiedWord] {
        let tokens = tokenize(text)
        return tokens.enumerated().map { index, token in
            let lower = token.lowercased()

            // Check dictionary first
            if let type = dictionary[lower] {
                return ClassifiedWord(word: token, type: type, position: index)
            }

            // Check for Bitcoin address patterns
            if isBitcoinAddress(token) {
                return ClassifiedWord(word: token, type: .bitcoinAddress, position: index)
            }

            // Check for txid (64-char hex)
            if isTxid(token) {
                return ClassifiedWord(word: token, type: .txid, position: index)
            }

            // Check for numbers (strip currency symbols)
            if let decimal = parseNumber(token) {
                return ClassifiedWord(word: token, type: .number(decimal), position: index)
            }

            // Check for "what's", "how's", "where's" contractions
            if lower.hasSuffix("'s") || lower.hasSuffix("'s") {
                let stem = String(lower.dropLast(2))
                if let type = dictionary[stem] {
                    return ClassifiedWord(word: token, type: type, position: index)
                }
            }

            // Check for "-ing", "-ed" verb forms
            if lower.hasSuffix("ing"), lower.count > 4 {
                let stem = String(lower.dropLast(3))
                if let type = dictionary[stem] { return ClassifiedWord(word: token, type: type, position: index) }
                let stemE = stem + "e"
                if let type = dictionary[stemE] { return ClassifiedWord(word: token, type: type, position: index) }
            }

            // Unknown word
            return ClassifiedWord(word: token, type: nil, position: index)
        }
    }

    // MARK: - Tokenization

    /// Splits text into tokens, preserving Bitcoin addresses and numbers.
    private func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""

        let chars = Array(text)
        var i = 0

        while i < chars.count {
            let ch = chars[i]

            if ch == " " || ch == "\t" || ch == "\n" {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else if "?!,;:".contains(ch) {
                // Punctuation as separate tokens (but keep in addresses)
                if current.hasPrefix("bc1") || current.hasPrefix("1") || current.hasPrefix("3") {
                    // Likely an address — don't split
                    current.append(ch)
                } else {
                    if !current.isEmpty {
                        tokens.append(current)
                        current = ""
                    }
                    tokens.append(String(ch))
                }
            } else {
                current.append(ch)
            }

            i += 1
        }

        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens
    }

    // MARK: - Pattern Detection

    private func isBitcoinAddress(_ token: String) -> Bool {
        let t = token.trimmingCharacters(in: .punctuationCharacters)
        if t.hasPrefix("bc1q") && t.count >= 42 && t.count <= 62 { return true }
        if t.hasPrefix("bc1p") && t.count >= 42 && t.count <= 62 { return true }
        if t.hasPrefix("1") && t.count >= 25 && t.count <= 34 { return true }
        if t.hasPrefix("3") && t.count >= 25 && t.count <= 34 { return true }
        return false
    }

    private func isTxid(_ token: String) -> Bool {
        let t = token.trimmingCharacters(in: .punctuationCharacters)
        return t.count == 64 && t.allSatisfy { $0.isHexDigit }
    }

    private func parseNumber(_ token: String) -> Decimal? {
        var cleaned = token
        // Strip currency prefixes
        if let first = cleaned.first, "$€£¥".contains(first) {
            cleaned = String(cleaned.dropFirst())
        }
        // Strip commas
        cleaned = cleaned.replacingOccurrences(of: ",", with: "")
        return Decimal(string: cleaned)
    }
}
