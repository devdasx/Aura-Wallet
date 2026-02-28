import SwiftUI

// MARK: - ActionButtonsCard
// Displays interactive suggestion buttons below AI responses.
// Tapping a button injects the command into the chat input.
// Uses a horizontal flow layout with wrapping.

struct ActionButtonsCard: View {
    let buttons: [ActionButton]
    let onTap: (String) -> Void

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            ForEach(buttons) { button in
                Button(action: { onTap(button.command) }) {
                    HStack(spacing: AppSpacing.xs) {
                        if let icon = button.icon {
                            Image(systemName: icon)
                                .font(.system(size: 12, weight: .medium))
                        }

                        Text(button.label)
                            .font(AppTypography.labelSmall)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(AppColors.accent)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.sm)
                    .background(AppColors.accentDim)
                    .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.pill, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppCornerRadius.pill, style: .continuous)
                            .stroke(AppColors.accent.opacity(0.2), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - PriceCard
// Displays Bitcoin price information in an inline card.

struct PriceCard: View {
    let btcPrice: Decimal
    let currency: String
    let formattedPrice: String

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            // Bitcoin icon
            ZStack {
                Circle()
                    .fill(AppColors.accentDim)
                    .frame(width: 40, height: 40)

                Image(systemName: "bitcoinsign.circle.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(AppColors.accentGradient)
            }

            VStack(alignment: .leading, spacing: AppSpacing.xxxs) {
                Text("Bitcoin")
                    .font(AppTypography.bodyMedium)
                    .fontWeight(.semibold)
                    .foregroundColor(AppColors.textPrimary)

                Text("BTC/\(currency)")
                    .font(AppTypography.labelSmall)
                    .foregroundColor(AppColors.textTertiary)
            }

            Spacer()

            Text(formattedPrice)
                .font(AppTypography.headingLarge)
                .fontWeight(.bold)
                .foregroundColor(AppColors.textPrimary)
        }
        .padding(AppSpacing.lg)
        .background(AppColors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppCornerRadius.xl, style: .continuous)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }
}

// MARK: - Preview

#if DEBUG
struct ActionButtonsCard_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: AppSpacing.md) {
            ActionButtonsCard(
                buttons: [
                    ActionButton(label: "Send", command: "send", icon: "arrow.up.right"),
                    ActionButton(label: "Receive", command: "receive", icon: "arrow.down.left"),
                    ActionButton(label: "History", command: "history", icon: "clock"),
                ],
                onTap: { _ in }
            )

            PriceCard(
                btcPrice: 65432.10,
                currency: "USD",
                formattedPrice: "$65,432.10"
            )
        }
        .padding(AppSpacing.lg)
        .background(AppColors.backgroundPrimary)
        .preferredColorScheme(.dark)
        .previewLayout(.sizeThatFits)
    }
}
#endif
