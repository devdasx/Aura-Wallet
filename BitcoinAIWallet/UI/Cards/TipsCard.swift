import SwiftUI

// MARK: - TipsCard
// Displays a rotating tip below AI responses.
// Compact card with icon, title, and body text.
// Uses the design system tokens throughout.

struct TipsCard: View {
    let tip: TipItem
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            // Tip icon
            Image(systemName: tip.icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AppColors.accentGradient)
                .frame(width: 28, height: 28)
                .background(AppColors.accentDim)
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.small, style: .continuous))

            // Tip content
            VStack(alignment: .leading, spacing: AppSpacing.xxxs) {
                Text(tip.title)
                    .font(AppTypography.labelSmall)
                    .fontWeight(.semibold)
                    .foregroundColor(AppColors.textSecondary)

                Text(tip.body)
                    .font(AppTypography.bodySmall)
                    .foregroundColor(AppColors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            // Dismiss button (optional)
            if let onDismiss = onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AppColors.textTertiary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(AppSpacing.md)
        .background(AppColors.backgroundTertiary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.large, style: .continuous))
    }
}

// MARK: - Preview

#if DEBUG
struct TipsCard_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: AppSpacing.md) {
            TipsCard(
                tip: TipItem(
                    id: "preview",
                    icon: "lock.shield",
                    titleKey: "tip.sec_1.title",
                    bodyKey: "tip.sec_1.body",
                    category: .security
                ),
                onDismiss: {}
            )
        }
        .padding(AppSpacing.lg)
        .background(AppColors.backgroundPrimary)
        .preferredColorScheme(.dark)
        .previewLayout(.sizeThatFits)
    }
}
#endif
