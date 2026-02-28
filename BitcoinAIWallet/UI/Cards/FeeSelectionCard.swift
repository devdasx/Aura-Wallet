import SwiftUI

// MARK: - FeeSelectionCard
// Inline chat card that lets the user pick a fee tier or enter a custom rate.
// Each tier shows the label, sat/vB rate, estimated confirmation time, and cost.

struct FeeSelectionCard: View {
    let slowRate: Decimal
    let mediumRate: Decimal
    let fastRate: Decimal
    let estimatedSize: Int
    @Binding var selectedLevel: FeeLevel
    let onSelect: (FeeLevel) -> Void

    @State private var customRateText: String = ""

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            headerRow
            Divider().background(AppColors.border)
            tierList
            customFeeSection
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
            Text(L10n.Fee.title)
                .font(AppTypography.headingLarge)
                .foregroundColor(AppColors.textPrimary)

            Spacer()

            Image(systemName: AppIcons.fees)
                .font(AppTypography.headingMedium)
                .foregroundColor(AppColors.accent)
        }
    }

    // MARK: - Tier List

    private var tierList: some View {
        VStack(spacing: AppSpacing.md) {
            tierButton(
                level: .slow,
                label: L10n.Fee.slow,
                rate: slowRate,
                timeLabel: L10n.Fee.slowTime,
                icon: "tortoise"
            )

            tierButton(
                level: .medium,
                label: L10n.Fee.medium,
                rate: mediumRate,
                timeLabel: L10n.Fee.mediumTime,
                icon: "hare"
            )

            tierButton(
                level: .fast,
                label: L10n.Fee.fast,
                rate: fastRate,
                timeLabel: L10n.Fee.fastTime,
                icon: "bolt"
            )
        }
    }

    private func tierButton(
        level: FeeLevel,
        label: String,
        rate: Decimal,
        timeLabel: String,
        icon: String
    ) -> some View {
        let isSelected = selectedLevel == level
        let cost = estimatedCost(rate: rate)

        return Button {
            selectedLevel = level
            onSelect(level)
        } label: {
            HStack(spacing: AppSpacing.md) {
                ZStack {
                    Circle()
                        .fill(isSelected ? AppColors.accentDim : AppColors.backgroundTertiary)
                        .frame(width: AppSpacing.xxxl, height: AppSpacing.xxxl)

                    Image(systemName: icon)
                        .font(AppTypography.labelMedium)
                        .foregroundColor(isSelected ? AppColors.accent : AppColors.textSecondary)
                }

                VStack(alignment: .leading, spacing: AppSpacing.xxxs) {
                    Text(label)
                        .font(AppTypography.headingSmall)
                        .foregroundColor(AppColors.textPrimary)

                    Text(timeLabel)
                        .font(AppTypography.labelSmall)
                        .foregroundColor(AppColors.textTertiary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: AppSpacing.xxxs) {
                    Text(L10n.Format.feeRate(formattedRate(rate)))
                        .font(AppTypography.monoMedium)
                        .foregroundColor(AppColors.textPrimary)

                    Text(formattedBTC(cost))
                        .font(AppTypography.labelSmall)
                        .foregroundColor(AppColors.textTertiary)
                }
            }
            .padding(AppSpacing.md)
            .background(isSelected ? AppColors.backgroundCardHover : AppColors.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppCornerRadius.large, style: .continuous)
                    .stroke(
                        isSelected ? AppColors.accent : AppColors.border,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Custom Fee Section

    private var customFeeSection: some View {
        let isSelected = selectedLevel == .custom

        return VStack(spacing: AppSpacing.sm) {
            Button {
                selectedLevel = .custom
                onSelect(.custom)
            } label: {
                HStack(spacing: AppSpacing.md) {
                    ZStack {
                        Circle()
                            .fill(isSelected ? AppColors.accentDim : AppColors.backgroundTertiary)
                            .frame(width: AppSpacing.xxxl, height: AppSpacing.xxxl)

                        Image(systemName: "slider.horizontal.3")
                            .font(AppTypography.labelMedium)
                            .foregroundColor(isSelected ? AppColors.accent : AppColors.textSecondary)
                    }

                    Text(L10n.Fee.custom)
                        .font(AppTypography.headingSmall)
                        .foregroundColor(AppColors.textPrimary)

                    Spacer()

                    if isSelected {
                        Image(systemName: AppIcons.checkmark)
                            .font(AppTypography.labelMedium)
                            .foregroundColor(AppColors.accent)
                    }
                }
                .padding(AppSpacing.md)
                .background(isSelected ? AppColors.backgroundCardHover : AppColors.backgroundCard)
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.large, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppCornerRadius.large, style: .continuous)
                        .stroke(
                            isSelected ? AppColors.accent : AppColors.border,
                            lineWidth: isSelected ? 1.5 : 1
                        )
                )
            }
            .buttonStyle(.plain)

            if isSelected {
                HStack(spacing: AppSpacing.sm) {
                    TextField(
                        L10n.Fee.satVb,
                        text: $customRateText
                    )
                    .font(AppTypography.monoMedium)
                    .foregroundColor(AppColors.textPrimary)
                    .keyboardType(.decimalPad)
                    .padding(AppSpacing.md)
                    .background(AppColors.backgroundTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium, style: .continuous))

                    Text(L10n.Fee.satVb)
                        .font(AppTypography.labelMedium)
                        .foregroundColor(AppColors.textSecondary)
                }
                .padding(.horizontal, AppSpacing.sm)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .animation(.easeInOut(duration: 0.2), value: isSelected)
            }
        }
    }

    // MARK: - Calculation Helpers

    private func estimatedCost(rate: Decimal) -> Decimal {
        let sats = rate * Decimal(estimatedSize)
        return sats / 100_000_000
    }

    private func formattedRate(_ rate: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter.string(from: rate as NSDecimalNumber) ?? "0.0"
    }

    private func formattedBTC(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 8
        formatter.maximumFractionDigits = 8
        let formatted = formatter.string(from: value as NSDecimalNumber) ?? "0.00000000"
        return L10n.Format.btcAmount(formatted)
    }
}

// MARK: - Preview

#if DEBUG
struct FeeSelectionCard_Previews: PreviewProvider {
    struct PreviewWrapper: View {
        @State private var level: FeeLevel = .medium

        var body: some View {
            FeeSelectionCard(
                slowRate: 5,
                mediumRate: 12,
                fastRate: 25,
                estimatedSize: 140,
                selectedLevel: $level,
                onSelect: { _ in }
            )
            .padding(AppSpacing.lg)
            .background(AppColors.backgroundPrimary)
        }
    }

    static var previews: some View {
        PreviewWrapper()
            .previewLayout(.sizeThatFits)
    }
}
#endif
