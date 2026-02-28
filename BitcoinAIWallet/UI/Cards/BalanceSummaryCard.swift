import SwiftUI

// MARK: - BalanceSummaryCard
// Inline chat card that shows a detailed balance breakdown.
// Displays total, confirmed, pending balances, UTXO count, and last-updated time.

struct BalanceSummaryCard: View {
    let totalBalance: Decimal
    let confirmedBalance: Decimal
    let pendingBalance: Decimal
    let fiatBalance: Decimal
    let utxoCount: Int
    let lastUpdated: Date

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            headerRow
            Divider().background(AppColors.border)
            totalBalanceSection
            Divider().background(AppColors.border)
            breakdownSection
            Divider().background(AppColors.border)
            metadataSection
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
            Text(L10n.Wallet.totalBalance)
                .font(AppTypography.headingLarge)
                .foregroundColor(AppColors.textPrimary)

            Spacer()

            Image(systemName: AppIcons.bitcoin)
                .font(AppTypography.headingLarge)
                .foregroundColor(AppColors.accent)
        }
    }

    // MARK: - Total Balance

    private var totalBalanceSection: some View {
        VStack(alignment: .center, spacing: AppSpacing.xs) {
            Text(formattedBTC(totalBalance))
                .font(AppTypography.displayLarge)
                .foregroundColor(AppColors.textPrimary)

            Text(formattedUSD(fiatBalance))
                .font(AppTypography.fiatAmount)
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Breakdown

    private var breakdownSection: some View {
        VStack(spacing: AppSpacing.md) {
            breakdownRow(
                label: L10n.Wallet.availableBalance,
                value: formattedBTC(confirmedBalance),
                color: AppColors.success
            )

            breakdownRow(
                label: L10n.Wallet.pendingBalance,
                value: formattedBTC(pendingBalance),
                color: pendingBalance > 0 ? AppColors.txPending : AppColors.textTertiary
            )
        }
    }

    private func breakdownRow(
        label: String,
        value: String,
        color: Color
    ) -> some View {
        HStack {
            HStack(spacing: AppSpacing.sm) {
                Circle()
                    .fill(color)
                    .frame(width: AppSpacing.sm, height: AppSpacing.sm)

                Text(label)
                    .font(AppTypography.bodyMedium)
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()

            Text(value)
                .font(AppTypography.monoMedium)
                .foregroundColor(AppColors.textPrimary)
        }
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        VStack(spacing: AppSpacing.sm) {
            HStack {
                Text(L10n.Wallet.utxoCount)
                    .font(AppTypography.labelMedium)
                    .foregroundColor(AppColors.textSecondary)

                Spacer()

                Text(L10n.Format.utxoCount(utxoCount))
                    .font(AppTypography.labelMedium)
                    .foregroundColor(AppColors.textPrimary)
            }

            HStack {
                Text(L10n.Wallet.lastUpdated)
                    .font(AppTypography.labelMedium)
                    .foregroundColor(AppColors.textSecondary)

                Spacer()

                Text(formattedTimestamp(lastUpdated))
                    .font(AppTypography.labelMedium)
                    .foregroundColor(AppColors.textTertiary)
            }
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

    private func formattedTimestamp(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Preview

#if DEBUG
struct BalanceSummaryCard_Previews: PreviewProvider {
    static var previews: some View {
        BalanceSummaryCard(
            totalBalance: 0.05000000,
            confirmedBalance: 0.04800000,
            pendingBalance: 0.00200000,
            fiatBalance: 3150.00,
            utxoCount: 7,
            lastUpdated: Date().addingTimeInterval(-120)
        )
        .padding(AppSpacing.lg)
        .background(AppColors.backgroundPrimary)
        .previewLayout(.sizeThatFits)
    }
}
#endif
