// MARK: - InlineAddressView.swift
// Bitcoin AI Wallet
//
// Monospace truncated address/TXID in a pill background with a copy button.
// Tapping copies full value to clipboard + haptic + "Copied!" toast.
//
// Platform: iOS 17.0+
// Framework: SwiftUI

import SwiftUI

struct InlineAddressView: View {
    let value: String
    @State private var showCopied = false

    var body: some View {
        Button {
            Self.secureCopy(value)
            HapticManager.lightTap()
            showCopied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                showCopied = false
            }
        } label: {
            HStack(spacing: AppSpacing.xs) {
                Text(truncated)
                    .font(AppTypography.monoMedium)
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(1)

                Image(systemName: showCopied ? AppIcons.checkmark : AppIcons.copy)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(showCopied ? AppColors.success : AppColors.textTertiary)
            }
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xxs)
            .background(AppColors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.small, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showCopied ? L10n.Common.copied : value)
        .accessibilityHint(L10n.Common.copy)
    }

    private var truncated: String {
        guard value.count > 16 else { return value }
        let prefix = value.prefix(8)
        let suffix = value.suffix(6)
        return "\(prefix)...\(suffix)"
    }

    // MARK: - Secure Clipboard

    /// Copies a value to the clipboard with a 60-second expiration and local-only flag.
    /// This prevents other apps from reading the clipboard after the timeout and
    /// prevents clipboard syncing to other devices via Universal Clipboard.
    static func secureCopy(_ text: String) {
        let pasteboard = UIPasteboard.general
        pasteboard.setItems(
            [["public.plain-text": text]],
            options: [
                .localOnly: true,
                .expirationDate: Date().addingTimeInterval(60)
            ]
        )
    }
}
