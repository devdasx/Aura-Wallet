// MARK: - BulletPointView.swift
// Bitcoin AI Wallet
//
// A bullet list item: small dot + formatted inline content.
// Used by FormattedMessageView when parsing "• " prefixed lines.
//
// Platform: iOS 17.0+
// Framework: SwiftUI

import SwiftUI

struct BulletPointView: View {
    let elements: [InlineElement]

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
            Circle()
                .fill(AppColors.textTertiary)
                .frame(width: 4, height: 4)
                .offset(y: 1)

            InlineContentView(elements: elements)
        }
        .padding(.leading, AppSpacing.md)
    }
}
