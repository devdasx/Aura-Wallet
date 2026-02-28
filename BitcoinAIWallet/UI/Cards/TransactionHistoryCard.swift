import SwiftUI

// MARK: - TransactionHistoryCard
// Inline chat card that lists recent transactions.
// Each row shows direction, address, amount, and status.
// Includes an empty-state message when there are no transactions.
//
// Uses TransactionDisplayItem defined in ResponseGenerator.swift.

struct TransactionHistoryCard: View {
    let transactions: [TransactionDisplayItem]
    let onTapTransaction: (String) -> Void

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            headerRow
            Divider().background(AppColors.border)

            if transactions.isEmpty {
                emptyState
            } else {
                transactionList
            }
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
            Text(L10n.History.recentTransactions)
                .font(AppTypography.headingLarge)
                .foregroundColor(AppColors.textPrimary)

            Spacer()

            Image(systemName: AppIcons.history)
                .font(AppTypography.headingMedium)
                .foregroundColor(AppColors.accent)
        }
    }

    // MARK: - Transaction List

    private var transactionList: some View {
        VStack(spacing: 0) {
            ForEach(Array(transactions.enumerated()), id: \.element.id) { index, transaction in
                Button {
                    onTapTransaction(transaction.id)
                } label: {
                    transactionRow(transaction)
                }
                .buttonStyle(.plain)

                if index < transactions.count - 1 {
                    Divider()
                        .background(AppColors.border)
                        .padding(.vertical, AppSpacing.sm)
                }
            }
        }
    }

    private func transactionRow(_ transaction: TransactionDisplayItem) -> some View {
        HStack(spacing: AppSpacing.md) {
            directionIcon(for: transaction.type)

            VStack(alignment: .leading, spacing: AppSpacing.xxxs) {
                Text(typeLabel(for: transaction.type))
                    .font(AppTypography.headingSmall)
                    .foregroundColor(AppColors.textPrimary)

                Text(truncatedAddress(transaction.address))
                    .font(AppTypography.monoSmall)
                    .foregroundColor(AppColors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: AppSpacing.xxxs) {
                Text(formattedAmount(transaction.amount, type: transaction.type))
                    .font(AppTypography.headingSmall)
                    .foregroundColor(amountColor(for: transaction.type))

                Text(transaction.status)
                    .font(AppTypography.labelSmall)
                    .foregroundColor(AppColors.textTertiary)
            }

            statusBadge(for: transaction)
        }
        .padding(.vertical, AppSpacing.xs)
    }

    // MARK: - Direction Icon

    private func directionIcon(for type: String) -> some View {
        let isSent = type.lowercased() == "sent"

        return ZStack {
            Circle()
                .fill(isSent ? AppColors.errorDim : AppColors.successDim)
                .frame(width: AppSpacing.xxxl, height: AppSpacing.xxxl)

            Image(systemName: isSent ? AppIcons.txSent : AppIcons.txReceived)
                .font(AppTypography.labelMedium)
                .foregroundColor(isSent ? AppColors.txSent : AppColors.txReceived)
        }
    }

    // MARK: - Status Badge

    private func statusBadge(for transaction: TransactionDisplayItem) -> some View {
        Group {
            if transaction.confirmations == 0 {
                Text(L10n.History.pending)
                    .font(AppTypography.labelSmall)
                    .foregroundColor(AppColors.txPending)
                    .padding(.horizontal, AppSpacing.xs)
                    .padding(.vertical, AppSpacing.xxxs)
                    .background(AppColors.warningDim)
                    .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.small, style: .continuous))
            } else {
                Image(systemName: AppIcons.txConfirmed)
                    .font(AppTypography.labelSmall)
                    .foregroundColor(AppColors.success)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: AppIcons.history)
                .font(.system(size: AppSpacing.xxxl))
                .foregroundColor(AppColors.textTertiary)

            Text(L10n.History.noTransactions)
                .font(AppTypography.bodyMedium)
                .foregroundColor(AppColors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.xxl)
    }

    // MARK: - Formatting Helpers

    private func typeLabel(for type: String) -> String {
        type.lowercased() == "sent" ? L10n.History.sent : L10n.History.received
    }

    private func amountColor(for type: String) -> Color {
        type.lowercased() == "sent" ? AppColors.txSent : AppColors.txReceived
    }

    private func formattedAmount(_ value: Decimal, type: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 8
        formatter.maximumFractionDigits = 8
        let formatted = formatter.string(from: value as NSDecimalNumber) ?? "0.00000000"
        let prefix = type.lowercased() == "sent" ? "-" : "+"
        return "\(prefix)\(L10n.Format.btcAmount(formatted))"
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
struct TransactionHistoryCard_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            TransactionHistoryCard(
                transactions: [
                    TransactionDisplayItem(
                        txid: "tx1abc",
                        type: "sent",
                        amount: 0.00125000,
                        address: "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh",
                        date: Date().addingTimeInterval(-3600),
                        confirmations: 3,
                        status: "confirmed"
                    ),
                    TransactionDisplayItem(
                        txid: "tx2def",
                        type: "received",
                        amount: 0.00500000,
                        address: "bc1p5cyxnuxmeuwuvkwfem96lqzszee02v3tg0eh9gq",
                        date: Date().addingTimeInterval(-7200),
                        confirmations: 0,
                        status: "pending"
                    ),
                    TransactionDisplayItem(
                        txid: "tx3ghi",
                        type: "sent",
                        amount: 0.00050000,
                        address: "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4",
                        date: Date().addingTimeInterval(-86400),
                        confirmations: 145,
                        status: "confirmed"
                    ),
                ],
                onTapTransaction: { _ in }
            )

            TransactionHistoryCard(
                transactions: [],
                onTapTransaction: { _ in }
            )
        }
        .padding(AppSpacing.lg)
        .background(AppColors.backgroundPrimary)
        .previewLayout(.sizeThatFits)
    }
}
#endif
