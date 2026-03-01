// MARK: - FormattedMessageView.swift
// Bitcoin AI Wallet
//
// Renders a token-formatted AI response string as rich SwiftUI content.
// Parses the input through MessageFormatter, then renders each block
// using the appropriate helper view (HeroAmount, BulletPoint, StatusDot, etc.).
//
// Platform: iOS 17.0+
// Framework: SwiftUI

import SwiftUI

// MARK: - FormattedMessageView

struct FormattedMessageView: View {
    let content: String

    private var blocks: [FormattedBlock] {
        MessageFormatter.parse(content)
    }

    var body: some View {
        if blocks.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: AppSpacing.xxxs) {
                ForEach(blocks) { block in
                    blockView(for: block)
                }
            }
        }
    }

    @ViewBuilder
    private func blockView(for block: FormattedBlock) -> some View {
        switch block {
        case .richText(_, let elements):
            InlineContentView(elements: elements)

        case .heroAmount(_, let btcText, let fiatText):
            HeroAmountView(btcText: btcText, fiatText: fiatText)

        case .statusLine(_, let status, let elements):
            HStack(spacing: AppSpacing.sm) {
                StatusDotView(status: status)
                if !elements.isEmpty {
                    InlineContentView(elements: elements)
                }
            }

        case .bulletPoint(_, let elements):
            BulletPointView(elements: elements)

        case .spacer:
            Color.clear
                .frame(height: AppSpacing.xs)
        }
    }
}

// MARK: - InlineContentView

/// Renders a sequence of inline elements (text runs + address pills) in a flow layout.
struct InlineContentView: View {
    let elements: [InlineElement]

    var body: some View {
        if elements.isEmpty {
            EmptyView()
        } else if elements.count == 1, case .textRun(_, let segments) = elements[0] {
            // Single text run — use concatenated Text for best wrapping
            buildText(from: segments)
        } else {
            // Mixed content — use wrapping layout
            FlowLayout(spacing: AppSpacing.xxs) {
                ForEach(elements) { element in
                    switch element {
                    case .textRun(_, let segments):
                        buildText(from: segments)
                    case .addressPill(_, let value):
                        InlineAddressView(value: value)
                    }
                }
            }
        }
    }

    private func buildText(from segments: [TextSegment]) -> Text {
        segments.reduce(Text("")) { result, segment in
            result + styledText(for: segment)
        }
    }

    private func styledText(for segment: TextSegment) -> Text {
        switch segment {
        case .plain(let str):
            return Text(str)
                .font(AppTypography.chatBody)
                .foregroundColor(AppColors.textPrimary)
        case .bold(let str):
            return Text(str)
                .font(AppTypography.chatBody)
                .bold()
                .foregroundColor(AppColors.textPrimary)
        case .code(let str):
            return Text(str)
                .font(AppTypography.monoMedium)
                .foregroundColor(AppColors.textPrimary)
        case .dim(let str):
            return Text(str)
                .font(AppTypography.chatBodySmall)
                .foregroundColor(AppColors.textTertiary)
        case .green(let str):
            return Text(str)
                .font(AppTypography.chatBody)
                .foregroundColor(AppColors.success)
        case .red(let str):
            return Text(str)
                .font(AppTypography.chatBody)
                .foregroundColor(AppColors.error)
        case .fiat(let str):
            return Text(str)
                .font(AppTypography.chatBodySmall)
                .foregroundColor(AppColors.textSecondary)
        }
    }
}

// MARK: - FlowLayout

/// A simple wrapping horizontal layout for mixed inline elements.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: ProposedViewSize(width: bounds.width, height: bounds.height), subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(subviews[index].sizeThatFits(.unspecified))
            )
        }
    }

    private struct LayoutResult {
        var size: CGSize
        var positions: [CGPoint]
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> LayoutResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            totalWidth = max(totalWidth, currentX - spacing)
        }

        return LayoutResult(
            size: CGSize(width: totalWidth, height: currentY + lineHeight),
            positions: positions
        )
    }
}
