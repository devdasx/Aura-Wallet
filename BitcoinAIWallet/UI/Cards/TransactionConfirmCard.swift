import SwiftUI

// MARK: - TransactionConfirmCard
// Inline chat card shown before the user signs a transaction.
// Displays amount, destination, fee, and confirm / cancel actions.

struct TransactionConfirmCard: View {
    let amount: Decimal
    let fiatAmount: Decimal
    let toAddress: String
    let fee: Decimal
    let feeRate: Decimal
    let estimatedMinutes: Int
    let remainingBalance: Decimal
    let onConfirm: () -> Void
    let onCancel: () -> Void
    let onChangeFee: () -> Void

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            headerRow
            Divider().background(AppColors.border)
            detailRows
            Divider().background(AppColors.border)
            footerButtons
        }
        .padding(AppSpacing.xl)
        .background(AppColors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppCornerRadius.xl, style: .continuous)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            Text(L10n.Send.title)
                .font(AppTypography.headingLarge)
                .foregroundColor(AppColors.textPrimary)

            Spacer()

            Text(L10n.Send.review)
                .font(AppTypography.labelMedium)
                .foregroundColor(AppColors.accent)
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, AppSpacing.xxs)
                .background(AppColors.accentDim)
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.small, style: .continuous))
        }
    }

    // MARK: - Detail Rows

    private var detailRows: some View {
        VStack(spacing: AppSpacing.md) {
            detailRow(
                label: L10n.Send.amount,
                primaryValue: formattedBTC(amount),
                secondaryValue: formattedUSD(fiatAmount)
            )

            detailRow(
                label: L10n.Send.to,
                monoValue: truncatedAddress(toAddress)
            )

            feeRow

            detailRow(
                label: L10n.Send.estimatedTime,
                primaryValue: L10n.Format.estimatedMinutes(estimatedMinutes)
            )

            detailRow(
                label: L10n.Send.remaining,
                primaryValue: formattedBTC(remainingBalance)
            )
        }
    }

    private func detailRow(
        label: String,
        primaryValue: String,
        secondaryValue: String? = nil
    ) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(AppTypography.bodyMedium)
                .foregroundColor(AppColors.textSecondary)

            Spacer()

            VStack(alignment: .trailing, spacing: AppSpacing.xxxs) {
                Text(primaryValue)
                    .font(AppTypography.bodyMedium)
                    .foregroundColor(AppColors.textPrimary)

                if let secondary = secondaryValue {
                    Text(secondary)
                        .font(AppTypography.labelSmall)
                        .foregroundColor(AppColors.textTertiary)
                }
            }
        }
    }

    private func detailRow(
        label: String,
        monoValue: String
    ) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(AppTypography.bodyMedium)
                .foregroundColor(AppColors.textSecondary)

            Spacer()

            Text(monoValue)
                .font(AppTypography.monoMedium)
                .foregroundColor(AppColors.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var feeRow: some View {
        HStack(alignment: .top) {
            Text(L10n.Send.networkFee)
                .font(AppTypography.bodyMedium)
                .foregroundColor(AppColors.textSecondary)

            Spacer()

            VStack(alignment: .trailing, spacing: AppSpacing.xxxs) {
                Text(formattedBTC(fee))
                    .font(AppTypography.bodyMedium)
                    .foregroundColor(AppColors.textPrimary)

                Text(L10n.Format.feeRate(feeRateFormatted))
                    .font(AppTypography.labelSmall)
                    .foregroundColor(AppColors.textTertiary)
            }

            Button(action: onChangeFee) {
                Image(systemName: AppIcons.chevronRight)
                    .font(AppTypography.labelSmall)
                    .foregroundColor(AppColors.accent)
            }
            .buttonStyle(.plain)
            .padding(.leading, AppSpacing.xxs)
        }
    }

    // MARK: - Footer Buttons

    private var footerButtons: some View {
        HStack(spacing: AppSpacing.md) {
            Button(action: onCancel) {
                Text(L10n.Common.cancel)
                    .font(AppTypography.buttonLarge)
                    .foregroundColor(AppColors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.md)
                    .background(AppColors.backgroundCard)
                    .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.large, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppCornerRadius.large, style: .continuous)
                            .stroke(AppColors.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Button(action: onConfirm) {
                Text(L10n.Send.confirmAndSign)
                    .font(AppTypography.buttonLarge)
                    .foregroundColor(AppColors.textOnAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.md)
                    .background(AppColors.accentGradient)
                    .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.large, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Formatting Helpers

    private func formattedBTC(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 8
        formatter.maximumFractionDigits = 8
        let formatted = formatter.string(from: value as NSDecimalNumber) ?? "0.00000000"
        return L10n.Format.btcAmount(formatted)
    }

    private func formattedUSD(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let formatted = formatter.string(from: value as NSDecimalNumber) ?? "0.00"
        return L10n.Format.usdAmount(formatted)
    }

    private var feeRateFormatted: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter.string(from: feeRate as NSDecimalNumber) ?? "0.0"
    }

    private func truncatedAddress(_ address: String) -> String {
        guard address.count > 16 else { return address }
        let prefix = address.prefix(8)
        let suffix = address.suffix(8)
        return "\(prefix)...\(suffix)"
    }
}

// MARK: - Preview

#if DEBUG
struct TransactionConfirmCard_Previews: PreviewProvider {
    static var previews: some View {
        TransactionConfirmCard(
            amount: 0.00125000,
            fiatAmount: 78.50,
            toAddress: "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh",
            fee: 0.00001200,
            feeRate: 12.5,
            estimatedMinutes: 20,
            remainingBalance: 0.04873800,
            onConfirm: {},
            onCancel: {},
            onChangeFee: {}
        )
        .padding(AppSpacing.lg)
        .background(AppColors.backgroundPrimary)
        .previewLayout(.sizeThatFits)
    }
}
#endif
