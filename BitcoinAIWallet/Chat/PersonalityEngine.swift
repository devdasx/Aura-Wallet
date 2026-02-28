// MARK: - PersonalityEngine.swift
// Bitcoin AI Wallet
//
// Adapts AI responses based on user behavior:
// - Terse users get shorter responses
// - Emoji users get subtle emoji touches
// - Repeated identical responses get rephrased
//
// Platform: iOS 17.0+
// Framework: Foundation

import Foundation

// MARK: - PersonalityEngine

@MainActor
final class PersonalityEngine {

    // MARK: - Public API

    /// Adapts a response string based on user behavior detected in memory.
    func adapt(_ response: String, memory: ConversationMemory) -> String {
        var result = response

        // Don't shorten card-format responses (they have {{tokens}})
        let isCardFormat = result.contains("{{")

        // 1. Shorten for terse users (skip if formatted)
        if memory.userIsTerse && result.count > 120 && !isCardFormat {
            result = shorten(result)
        }

        // 2. Avoid exact duplicate of last AI response
        if let lastResponse = memory.lastAIResponse, lastResponse == result {
            result = rephrase(result)
        }

        return result
    }

    /// Adapts all text responses in a response array.
    func adaptAll(_ responses: [ResponseType], memory: ConversationMemory) -> [ResponseType] {
        responses.map { response in
            if case .text(let text) = response {
                return .text(adapt(text, memory: memory))
            }
            return response
        }
    }

    // MARK: - Private Helpers

    /// Shortens a response by removing dim/secondary content and trimming.
    private func shorten(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
        var shortened: [String] = []

        for line in lines {
            // Skip dim/footnote lines for terse users
            if line.contains("{{dim:") { continue }
            // Skip empty lines between content
            if line.isEmpty && shortened.last?.isEmpty == true { continue }
            shortened.append(line)
        }

        // Remove trailing empty lines
        while shortened.last?.isEmpty == true { shortened.removeLast() }

        return shortened.joined(separator: "\n")
    }

    /// Slightly rephrases a response to avoid exact repetition.
    private func rephrase(_ text: String) -> String {
        // Simple prefix variations for common patterns
        let swaps: [(String, String)] = [
            ("Your balance is", "You have"),
            ("You have", "Your current balance is"),
            ("Current balance:", "Balance:"),
            ("Here's what I can help you with:", "I can help with:"),
            ("Your balance:", "Currently:"),
        ]

        for (from, to) in swaps {
            if text.contains(from) {
                return text.replacingOccurrences(of: from, with: to)
            }
        }

        return text
    }
}
