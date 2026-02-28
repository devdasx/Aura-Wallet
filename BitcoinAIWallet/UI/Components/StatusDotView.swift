// MARK: - StatusDotView.swift
// Bitcoin AI Wallet
//
// Colored 8px circle + status label in matching color.
// Used for transaction status display (confirmed, pending, failed).
//
// Platform: iOS 17.0+
// Framework: SwiftUI

import SwiftUI

struct StatusDotView: View {
    let status: StatusType

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)

            Text(label)
                .font(AppTypography.bodyMedium)
                .fontWeight(.semibold)
                .foregroundColor(dotColor)
        }
    }

    private var dotColor: Color {
        switch status {
        case .success: return AppColors.success
        case .pending: return AppColors.warning
        case .failed: return AppColors.error
        }
    }

    private var label: String {
        switch status {
        case .success: return L10n.History.confirmed
        case .pending: return L10n.History.pending
        case .failed: return L10n.Common.error
        }
    }
}
