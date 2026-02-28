import SwiftUI

// MARK: - TransactionSuccessCard
// Inline chat card displayed after a transaction is successfully broadcast.
// Shows an animated checkmark, amount, TXID, and an explorer link.

struct TransactionSuccessCard: View {
    let txid: String
    let amount: Decimal
    let fiatAmount: Decimal
    let toAddress: String
    let onCopyTxid: () -> Void
    let onViewExplorer: () -> Void

    @State private var checkmarkScale: CGFloat = 0.0
    @State private var checkmarkOpacity: Double = 0.0

    // MARK: - Body

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            animatedCheckmark
            titleSection
            Divider().background(AppColors.border)
            detailSection
            Divider().background(AppColors.border)
            actionsSection
        }
        .padding(AppSpacing.xl)
        .background(AppColors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppCornerRadius.xl, style: .continuous)
                .stroke(AppColors.success.opacity(0.4), lineWidth: 1)
        )
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6, blendDuration: 0)) {
                checkmarkScale = 1.0
                checkmarkOpacity = 1.0
            }
        }
    }

    // MARK: - Animated Checkmark

    private var animatedCheckmark: some View {
        ZStack {
            Circle()
                .fill(AppColors.successDim)
                .frame(width: AppSpacing.massive, height: AppSpacing.massive)

            Image(systemName: AppIcons.success)
                .font(.system(size: AppSpacing.xxl, weight: .medium))
                .foregroundColor(AppColors.success)
        }
        .scaleEffect(checkmarkScale)
        .opacity(checkmarkOpacity)
    }

    // MARK: - Title

    private var titleSection: some View {
        VStack(spacing: AppSpacing.xs) {
            Text(L10n.History.transactionSent)
                .font(AppTypography.headingLarge)
                .foregroundColor(AppColors.textPrimary)

            HStack(spacing: AppSpacing.xxs) {
                Text(formattedBTC(amount))
                    .font(AppTypography.displayMedium)
                    .foregroundColor(AppColors.textPrimary)
            }

            Text(formattedUSD(fiatAmount))
                .font(AppTypography.fiatAmount)
                .foregroundColor(AppColors.textSecondary)
        }
    }

    // MARK: - Details

    private var detailSection: some View {
        VStack(spacing: AppSpacing.md) {
            HStack(alignment: .top) {
                Text(L10n.Send.to)
                    .font(AppTypography.bodyMedium)
                    .foregroundColor(AppColors.textSecondary)

                Spacer()

                Text(truncatedAddress(toAddress))
                    .font(AppTypography.monoMedium)
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            HStack(alignment: .top) {
                Text(L10n.History.txid)
                    .font(AppTypography.bodyMedium)
                    .foregroundColor(AppColors.textSecondary)

                Spacer()

                Button(action: onCopyTxid) {
                    HStack(spacing: AppSpacing.xxs) {
                        Text(truncatedTxid(txid))
                            .font(AppTypography.monoMedium)
                            .foregroundColor(AppColors.accent)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Image(systemName: AppIcons.copy)
                            .font(AppTypography.labelSmall)
                            .foregroundColor(AppColors.accent)
                    }
                }
                .buttonStyle(.plain)
            }

            HStack {
                Text(L10n.History.pending)
                    .font(AppTypography.labelMedium)
                    .foregroundColor(AppColors.txPending)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, AppSpacing.xxxs)
                    .background(AppColors.warningDim)
                    .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.small, style: .continuous))

                Spacer()
            }
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        Button(action: onViewExplorer) {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: AppIcons.globe)
                    .font(AppTypography.labelMedium)

                Text(L10n.History.viewOnExplorer)
                    .font(AppTypography.buttonMedium)
            }
            .foregroundColor(AppColors.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.md)
            .background(AppColors.accentDim)
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.large, style: .continuous))
        }
        .buttonStyle(.plain)
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

    private func truncatedAddress(_ address: String) -> String {
        guard address.count > 16 else { return address }
        let prefix = address.prefix(8)
        let suffix = address.suffix(8)
        return "\(prefix)...\(suffix)"
    }

    private func truncatedTxid(_ txid: String) -> String {
        guard txid.count > 20 else { return txid }
        let prefix = txid.prefix(10)
        let suffix = txid.suffix(10)
        return "\(prefix)...\(suffix)"
    }
}

// MARK: - Preview

#if DEBUG
struct TransactionSuccessCard_Previews: PreviewProvider {
    static var previews: some View {
        TransactionSuccessCard(
            txid: "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2",
            amount: 0.00125000,
            fiatAmount: 78.50,
            toAddress: "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh",
            onCopyTxid: {},
            onViewExplorer: {}
        )
        .padding(AppSpacing.lg)
        .background(AppColors.backgroundPrimary)
        .previewLayout(.sizeThatFits)
    }
}
#endif
