// MARK: - PersonalityEngine.swift
// Bitcoin AI Wallet
//
// Adapts AI responses based on user behavior:
// - Terse users get shorter responses (dim/footnote lines stripped)
// - Repeated identical responses get rephrased to avoid staleness
// - Formatting tokens ({{amount:}}, {{address:}}, etc.) are never modified
// - Card-based responses (balanceCard, feeCard, etc.) pass through untouched
// - No emojis are ever added
//
// Platform: iOS 17.0+
// Framework: Foundation

import Foundation

// MARK: - PersonalityEngine

@MainActor
final class PersonalityEngine {

    // MARK: - Public API

    /// Adapts a response string based on user behavior detected in memory.
    ///
    /// Safe for all response text including those with formatting tokens.
    /// Card-format responses (containing `{{`) skip shortening but may
    /// still be rephrased outside of token boundaries.
    func adapt(_ response: String, memory: ConversationMemory) -> String {
        var result = response

        // Detect formatting tokens — these responses need extra care
        let hasTokens = result.contains("{{")

        // 1. Shorten for terse users (skip if response contains formatting tokens)
        if memory.userIsTerse && result.count > 120 && !hasTokens {
            result = shorten(result)
        }

        // 2. Avoid exact duplicate of last AI response
        if let lastResponse = memory.lastAIResponse, lastResponse == result {
            result = rephrase(result)
        }

        return result
    }

    /// Adapts all text responses in a response array.
    ///
    /// Only `.text` responses are modified. All card types (`.balanceCard`,
    /// `.sendConfirmCard`, `.receiveCard`, `.historyCard`, `.successCard`,
    /// `.feeCard`, `.priceCard`, `.tipsCard`, `.actionButtons`) and
    /// `.errorText` pass through unchanged.
    func adaptAll(_ responses: [ResponseType], memory: ConversationMemory) -> [ResponseType] {
        responses.map { response in
            if case .text(let text) = response {
                return .text(adapt(text, memory: memory))
            }
            // Cards and errors are never personality-adapted
            return response
        }
    }

    // MARK: - Private Helpers

    /// Shortens a response by removing dim/secondary content and collapsing
    /// consecutive blank lines. Only called on plain text (no `{{` tokens).
    private func shorten(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
        var shortened: [String] = []

        for line in lines {
            // Skip dim/footnote lines for terse users
            if line.contains("{{dim:") { continue }
            // Collapse consecutive empty lines
            if line.isEmpty && shortened.last?.isEmpty == true { continue }
            shortened.append(line)
        }

        // Remove trailing empty lines
        while shortened.last?.isEmpty == true { shortened.removeLast() }

        return shortened.joined(separator: "\n")
    }

    /// Slightly rephrases a response to avoid exact repetition.
    ///
    /// Only replaces text OUTSIDE of formatting tokens (`{{...}}`).
    /// This prevents corruption of amount, address, or status tokens.
    private func rephrase(_ text: String) -> String {
        // Swap pairs: (original phrase, replacement phrase)
        // These target natural language intros, not token content.
        let swaps: [(String, String)] = [
            ("Your balance is", "You have"),
            ("You have", "Your current balance is"),
            ("Current balance:", "Balance:"),
            ("Here's what I can help you with:", "I can help with:"),
            ("Your balance:", "Currently:"),
            ("Here are your last", "Showing your last"),
            ("Here's your", "Your"),
            ("Here are the current", "Current"),
            ("I can help you", "I'm able to help you"),
        ]

        for (from, to) in swaps {
            if let range = tokenSafeRange(of: from, in: text) {
                var modified = text
                modified.replaceSubrange(range, with: to)
                return modified
            }
        }

        return text
    }

    /// Finds the range of `target` in `text`, but only if it falls entirely
    /// outside of `{{...}}` formatting tokens. Returns `nil` if the match
    /// is inside a token or not found.
    private func tokenSafeRange(of target: String, in text: String) -> Range<String.Index>? {
        guard let matchRange = text.range(of: target) else { return nil }

        // Build a set of ranges that are inside {{ ... }} tokens
        let tokenRanges = formattingTokenRanges(in: text)

        // Check that the match does not overlap any token range
        for tokenRange in tokenRanges {
            if matchRange.overlaps(tokenRange) {
                return nil
            }
        }

        return matchRange
    }

    /// Returns all ranges in the string that are inside `{{...}}` tokens.
    private func formattingTokenRanges(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var searchStart = text.startIndex

        while searchStart < text.endIndex {
            guard let openRange = text.range(of: "{{", range: searchStart..<text.endIndex) else {
                break
            }
            guard let closeRange = text.range(of: "}}", range: openRange.upperBound..<text.endIndex) else {
                break
            }
            ranges.append(openRange.lowerBound..<closeRange.upperBound)
            searchStart = closeRange.upperBound
        }

        return ranges
    }
}
