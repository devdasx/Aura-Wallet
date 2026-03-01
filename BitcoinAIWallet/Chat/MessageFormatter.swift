// MARK: - MessageFormatter.swift
// Bitcoin AI Wallet
//
// Token-based formatting system for AI response strings.
// Parses markdown-like tokens into structured blocks that
// SwiftUI views can render with rich visual hierarchy.
//
// Supported tokens:
//   **text**           → Bold
//   `text`             → Monospace
//   • text             → Bullet point
//   {{amount:text}}    → Hero BTC amount (large, accent)
//   {{fiat:text}}      → Fiat amount (smaller, secondary)
//   {{address:text}}   → Monospace pill with copy button
//   {{status:success}} → Green dot + "Confirmed"
//   {{status:pending}} → Orange dot + "Pending"
//   {{status:failed}}  → Red dot + "Failed"
//   {{green:text}}     → Green colored text
//   {{red:text}}       → Red colored text
//   {{dim:text}}       → Dimmed tertiary text
//
// Platform: iOS 17.0+
// Framework: Foundation

import Foundation

// MARK: - StatusType

enum StatusType: String {
    case success
    case pending
    case failed
}

// MARK: - TextSegment

/// An inline styled text fragment within a line.
enum TextSegment: Equatable {
    case plain(String)
    case bold(String)
    case code(String)
    case dim(String)
    case green(String)
    case red(String)
    case fiat(String)
}

// MARK: - InlineElement

/// An element within a line — either a styled text run or an interactive view.
enum InlineElement: Identifiable, Equatable {
    case textRun(id: String, segments: [TextSegment])
    case addressPill(id: String, value: String)

    var id: String {
        switch self {
        case .textRun(let id, _): return id
        case .addressPill(let id, _): return id
        }
    }
}

// MARK: - FormattedBlock

/// A parsed block representing one visual row in a formatted message.
enum FormattedBlock: Identifiable, Equatable {
    case richText(id: String, elements: [InlineElement])
    case heroAmount(id: String, btcText: String, fiatText: String?)
    case statusLine(id: String, status: StatusType, elements: [InlineElement])
    case bulletPoint(id: String, elements: [InlineElement])
    case spacer(id: String)

    var id: String {
        switch self {
        case .richText(let id, _): return id
        case .heroAmount(let id, _, _): return id
        case .statusLine(let id, _, _): return id
        case .bulletPoint(let id, _): return id
        case .spacer(let id): return id
        }
    }
}

// MARK: - MessageFormatter

struct MessageFormatter {

    // MARK: - Public API

    /// Parse a token-embedded string into structured blocks for rendering.
    static func parse(_ input: String) -> [FormattedBlock] {
        // Empty or whitespace-only input produces no blocks (avoids orphan spacers).
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        let lines = input.components(separatedBy: "\n")
        var blocks: [FormattedBlock] = []
        var blockIndex = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                blocks.append(.spacer(id: "b\(blockIndex)"))
                blockIndex += 1
                continue
            }

            // Hero amount: line is {{amount:...}} optionally followed by {{fiat:...}}
            if let heroBlock = parseHeroAmountLine(trimmed, index: blockIndex) {
                blocks.append(heroBlock)
                blockIndex += 1
                continue
            }

            // Status line: starts with {{status:...}}
            if let statusBlock = parseStatusLine(trimmed, index: blockIndex) {
                blocks.append(statusBlock)
                blockIndex += 1
                continue
            }

            // Bullet point: starts with • or - followed by a space
            // Note: "- " prefix is checked with an extra guard to avoid matching
            // negative numbers like "-0.001 BTC" as bullets.
            if trimmed.hasPrefix("• ") {
                let bulletText = String(trimmed.dropFirst(2))
                let elements = parseInlineElements(bulletText, baseId: "b\(blockIndex)")
                blocks.append(.bulletPoint(id: "b\(blockIndex)", elements: elements))
                blockIndex += 1
                continue
            }
            if trimmed.hasPrefix("- ") {
                let afterDash = trimmed.dropFirst(2)
                // Only treat as bullet if first char after "- " is NOT a digit or period
                // (avoids "-0.001 BTC" being parsed as a bullet).
                let firstChar = afterDash.first
                let looksLikeNumber = firstChar != nil && (firstChar!.isNumber || firstChar! == ".")
                if !looksLikeNumber {
                    let bulletText = String(afterDash)
                    let elements = parseInlineElements(bulletText, baseId: "b\(blockIndex)")
                    blocks.append(.bulletPoint(id: "b\(blockIndex)", elements: elements))
                    blockIndex += 1
                    continue
                }
            }

            // Regular rich text line
            let elements = parseInlineElements(trimmed, baseId: "b\(blockIndex)")
            blocks.append(.richText(id: "b\(blockIndex)", elements: elements))
            blockIndex += 1
        }

        return blocks
    }

    // MARK: - Line-Level Parsers

    /// Check if a line is a hero amount display.
    private static func parseHeroAmountLine(_ line: String, index: Int) -> FormattedBlock? {
        // Pattern: {{amount:VALUE}} optionally followed by whitespace and {{fiat:VALUE}}
        let amountPattern = #"\{\{amount:([^}]+)\}\}"#
        guard let amountMatch = line.range(of: amountPattern, options: .regularExpression) else {
            return nil
        }

        // Verify the line primarily consists of amount/fiat tokens (not mixed with other text)
        let stripped = line
            .replacingOccurrences(of: #"\{\{amount:[^}]+\}\}"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\{\{fiat:[^}]+\}\}"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        guard stripped.isEmpty else { return nil }

        let amountText = extractTokenValue(from: String(line[amountMatch]), prefix: "{{amount:", suffix: "}}")

        // Check for fiat
        var fiatText: String?
        let fiatPattern = #"\{\{fiat:([^}]+)\}\}"#
        if let fiatMatch = line.range(of: fiatPattern, options: .regularExpression) {
            fiatText = extractTokenValue(from: String(line[fiatMatch]), prefix: "{{fiat:", suffix: "}}")
        }

        return .heroAmount(id: "b\(index)", btcText: amountText, fiatText: fiatText)
    }

    /// Check if a line starts with a status token.
    private static func parseStatusLine(_ line: String, index: Int) -> FormattedBlock? {
        let statusPattern = #"^\{\{status:(success|pending|failed)\}\}"#
        guard let statusMatch = line.range(of: statusPattern, options: .regularExpression) else {
            return nil
        }

        let statusStr = extractTokenValue(from: String(line[statusMatch]), prefix: "{{status:", suffix: "}}")
        guard let status = StatusType(rawValue: statusStr) else { return nil }

        let remaining = String(line[statusMatch.upperBound...]).trimmingCharacters(in: .whitespaces)
        let elements: [InlineElement]
        if remaining.isEmpty {
            elements = []
        } else {
            elements = parseInlineElements(remaining, baseId: "b\(index)")
        }

        return .statusLine(id: "b\(index)", status: status, elements: elements)
    }

    // MARK: - Inline Parsing

    /// Parse a string into inline elements, splitting on {{address:...}} tokens.
    private static func parseInlineElements(_ input: String, baseId: String) -> [InlineElement] {
        var elements: [InlineElement] = []
        var remaining = input
        var elementIndex = 0

        while !remaining.isEmpty {
            // Find next {{address:...}}
            if let addrRange = remaining.range(of: #"\{\{address:([^}]+)\}\}"#, options: .regularExpression) {
                // Text before the address
                let before = String(remaining[remaining.startIndex..<addrRange.lowerBound])
                if !before.isEmpty {
                    let segments = parseTextSegments(before)
                    elements.append(.textRun(id: "\(baseId)_e\(elementIndex)", segments: segments))
                    elementIndex += 1
                }

                // The address itself
                let addrToken = String(remaining[addrRange])
                let addrValue = extractTokenValue(from: addrToken, prefix: "{{address:", suffix: "}}")
                elements.append(.addressPill(id: "\(baseId)_e\(elementIndex)", value: addrValue))
                elementIndex += 1

                remaining = String(remaining[addrRange.upperBound...])
            } else {
                // No more addresses — parse remaining as text
                let segments = parseTextSegments(remaining)
                if !segments.isEmpty {
                    elements.append(.textRun(id: "\(baseId)_e\(elementIndex)", segments: segments))
                }
                break
            }
        }

        return elements
    }

    /// Parse inline text formatting tokens into segments.
    private static func parseTextSegments(_ input: String) -> [TextSegment] {
        var segments: [TextSegment] = []
        var remaining = input[input.startIndex...]

        while !remaining.isEmpty {
            // Find next token
            if let (range, segment, _) = findNextInlineToken(in: remaining) {
                // Plain text before the token
                let before = remaining[remaining.startIndex..<range.lowerBound]
                if !before.isEmpty {
                    segments.append(.plain(String(before)))
                }
                segments.append(segment)
                remaining = remaining[range.upperBound...]
            } else {
                // No more tokens
                let text = String(remaining)
                if !text.isEmpty {
                    segments.append(.plain(text))
                }
                break
            }
        }

        return segments
    }

    /// Find the next inline formatting token in the given substring.
    private static func findNextInlineToken(in input: Substring) -> (Range<String.Index>, TextSegment, String)? {
        struct TokenMatch {
            let range: Range<String.Index>
            let segment: TextSegment
            let type: String
        }

        var candidates: [TokenMatch] = []

        // **bold**
        if let range = input.range(of: #"\*\*([^*]+)\*\*"#, options: .regularExpression) {
            let inner = String(input[range]).dropFirst(2).dropLast(2)
            candidates.append(TokenMatch(range: range, segment: .bold(String(inner)), type: "bold"))
        }

        // `code`
        if let range = input.range(of: #"`([^`]+)`"#, options: .regularExpression) {
            let inner = String(input[range]).dropFirst(1).dropLast(1)
            candidates.append(TokenMatch(range: range, segment: .code(String(inner)), type: "code"))
        }

        // {{dim:text}}
        if let range = input.range(of: #"\{\{dim:([^}]+)\}\}"#, options: .regularExpression) {
            let value = extractTokenValue(from: String(input[range]), prefix: "{{dim:", suffix: "}}")
            candidates.append(TokenMatch(range: range, segment: .dim(value), type: "dim"))
        }

        // {{green:text}}
        if let range = input.range(of: #"\{\{green:([^}]+)\}\}"#, options: .regularExpression) {
            let value = extractTokenValue(from: String(input[range]), prefix: "{{green:", suffix: "}}")
            candidates.append(TokenMatch(range: range, segment: .green(value), type: "green"))
        }

        // {{red:text}}
        if let range = input.range(of: #"\{\{red:([^}]+)\}\}"#, options: .regularExpression) {
            let value = extractTokenValue(from: String(input[range]), prefix: "{{red:", suffix: "}}")
            candidates.append(TokenMatch(range: range, segment: .red(value), type: "red"))
        }

        // {{fiat:text}}
        if let range = input.range(of: #"\{\{fiat:([^}]+)\}\}"#, options: .regularExpression) {
            let value = extractTokenValue(from: String(input[range]), prefix: "{{fiat:", suffix: "}}")
            candidates.append(TokenMatch(range: range, segment: .fiat(value), type: "fiat"))
        }

        // {{amount:text}} appearing inline (not as hero)
        if let range = input.range(of: #"\{\{amount:([^}]+)\}\}"#, options: .regularExpression) {
            let value = extractTokenValue(from: String(input[range]), prefix: "{{amount:", suffix: "}}")
            candidates.append(TokenMatch(range: range, segment: .bold(value), type: "amount"))
        }

        // Return the earliest match
        return candidates
            .sorted { $0.range.lowerBound < $1.range.lowerBound }
            .first
            .map { ($0.range, $0.segment, $0.type) }
    }

    // MARK: - Utility

    private static func extractTokenValue(from token: String, prefix: String, suffix: String) -> String {
        var result = token
        if result.hasPrefix(prefix) { result = String(result.dropFirst(prefix.count)) }
        if result.hasSuffix(suffix) { result = String(result.dropLast(suffix.count)) }
        return result
    }
}
