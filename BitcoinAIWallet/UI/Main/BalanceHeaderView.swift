import SwiftUI

// MARK: - BalanceHeaderView
// Always-visible balance display fixed at the top of the main wallet screen.
//
// Layout:
//   Top row: Wallet label (left) + New Chat button (right)
//   Main row: Primary balance with gradient text (tappable to swap BTC/fiat)
//   Sub row: Secondary balance (smaller, secondary color)
//
// Tapping the balance area swaps which currency is displayed prominently.
// When balance is hidden, amounts are replaced with bullet characters.
// Hide/show and refresh are accessed via chat commands.

struct BalanceHeaderView: View {
    let btcBalance: Decimal
    let fiatBalance: Decimal
    let currencyCode: String
    let isHidden: Bool
    @Binding var isSwapped: Bool
    var onSidebar: (() -> Void)?
    var onNewChat: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            topRow
            balanceDisplay
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.top, AppSpacing.md)
        .padding(.bottom, AppSpacing.lg)
        .background(AppColors.backgroundPrimary)
        .appShadow(AppShadows.small)
    }

    // MARK: - Top Row

    /// Wallet name label on the left, new chat button on the right.
    private var topRow: some View {
        HStack(spacing: AppSpacing.sm) {
            // Sidebar toggle button
            if let onSidebar {
                Button(action: onSidebar) {
                    Image(systemName: AppIcons.menu)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppColors.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(AppColors.backgroundSecondary)
                        )
                }
                .buttonStyle(.plain)
            }

            // Bitcoin icon + Wallet label
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: AppIcons.bitcoin)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppColors.accent)

                Text(L10n.Wallet.mainWallet)
                    .font(AppTypography.labelMedium)
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()

            // New chat button
            if let onNewChat {
                Button(action: onNewChat) {
                    Image(systemName: AppIcons.newChat)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppColors.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(AppColors.backgroundSecondary)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Balance Display

    /// Shows primary and secondary balances. Tapping swaps which is prominent.
    /// When hidden, both are replaced with bullet characters.
    private var balanceDisplay: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            if isHidden {
                Text(hiddenBalanceText)
                    .font(AppTypography.displayLarge)
                    .foregroundColor(AppColors.textPrimary)

                Text(hiddenFiatText)
                    .font(AppTypography.fiatAmount)
                    .foregroundColor(AppColors.textSecondary)
            } else if isSwapped {
                // Fiat is primary (large), BTC is secondary (small)
                Text(formatFiat(fiatBalance))
                    .font(AppTypography.displayLarge)
                    .foregroundStyle(adaptiveBalanceGradient)

                Text(formatBTC(btcBalance))
                    .font(AppTypography.fiatAmount)
                    .foregroundColor(AppColors.textSecondary)
            } else {
                // BTC is primary (large), fiat is secondary (small)
                Text(formatBTC(btcBalance))
                    .font(AppTypography.displayLarge)
                    .foregroundStyle(adaptiveBalanceGradient)

                Text("\u{2248} " + formatFiat(fiatBalance))
                    .font(AppTypography.fiatAmount)
                    .foregroundColor(AppColors.textSecondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isSwapped.toggle()
            }
        }
    }

    // MARK: - Formatting

    /// Formats a Decimal BTC amount as "0.00000000 BTC".
    private func formatBTC(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 8
        formatter.maximumFractionDigits = 8
        formatter.groupingSeparator = ","
        let formatted = formatter.string(from: amount as NSDecimalNumber) ?? "0.00000000"
        return L10n.Format.btcAmount(formatted)
    }

    /// Formats a Decimal fiat amount with the user's selected currency symbol.
    private func formatFiat(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(currencyCode) 0.00"
    }

    // MARK: - Hidden State

    /// Bullet characters replacing the BTC balance when hidden.
    private var hiddenBalanceText: String {
        "\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}"
    }

    /// Bullet characters replacing the fiat balance when hidden.
    private var hiddenFiatText: String {
        "\u{2248} \u{2022}\u{2022}\u{2022}\u{2022}"
    }

    // MARK: - Adaptive Gradient

    /// Returns the balance gradient appropriate for the current color scheme.
    private var adaptiveBalanceGradient: LinearGradient {
        colorScheme == .dark
            ? AppColors.darkBalanceGradient
            : AppColors.lightBalanceGradient
    }
}

// MARK: - Preview

#if DEBUG
struct BalanceHeaderView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            BalanceHeaderView(
                btcBalance: Decimal(string: "0.05123456")!,
                fiatBalance: Decimal(string: "3245.67")!,
                currencyCode: "USD",
                isHidden: false,
                isSwapped: .constant(false),
                onNewChat: {}
            )
            .preferredColorScheme(.dark)
            .previewDisplayName("Dark - BTC Primary")

            BalanceHeaderView(
                btcBalance: Decimal(string: "0.05123456")!,
                fiatBalance: Decimal(string: "3245.67")!,
                currencyCode: "EUR",
                isHidden: false,
                isSwapped: .constant(true),
                onNewChat: {}
            )
            .preferredColorScheme(.dark)
            .previewDisplayName("Dark - Fiat Primary")

            BalanceHeaderView(
                btcBalance: Decimal(string: "0.05123456")!,
                fiatBalance: Decimal(string: "3245.67")!,
                currencyCode: "USD",
                isHidden: true,
                isSwapped: .constant(false),
                onNewChat: {}
            )
            .preferredColorScheme(.dark)
            .previewDisplayName("Dark - Hidden")

            BalanceHeaderView(
                btcBalance: 0,
                fiatBalance: 0,
                currencyCode: "GBP",
                isHidden: false,
                isSwapped: .constant(false),
                onNewChat: {}
            )
            .preferredColorScheme(.light)
            .previewDisplayName("Light - Zero Balance")
        }
        .previewLayout(.sizeThatFits)
    }
}
#endif
