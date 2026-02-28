// MARK: - HeroAmountView.swift
// Bitcoin AI Wallet
//
// Large accent-colored BTC amount + optional smaller fiat equivalent.
// The "hero number" in AI responses — draws the eye immediately.
//
// Platform: iOS 17.0+
// Framework: SwiftUI

import SwiftUI

struct HeroAmountView: View {
    let btcText: String
    let fiatText: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
            Text(btcText)
                .font(AppTypography.displayMedium)
                .fontWeight(.bold)
                .foregroundColor(AppColors.accent)

            if let fiat = fiatText {
                Text(fiat)
                    .font(AppTypography.bodySmall)
                    .foregroundColor(AppColors.textSecondary)
            }
        }
    }
}
