import SwiftUI

// MARK: - MessageBubbleView
// Individual chat message bubble.
//
// AI messages (left-aligned):
//   - Background: AppColors.backgroundAIBubble with 1px border
//   - Corner radius: 20 with bottom-leading 6
//   - Max width: 82% of screen
//   - "Wallet AI" label with accent dot above the bubble
//   - Text: AppTypography.bodyMedium, AppColors.textPrimary
//
// User messages (right-aligned):
//   - Background: AppColors.backgroundUserBubble
//   - Corner radius: 20 with bottom-trailing 6
//   - Max width: 82% of screen
//   - Text: AppTypography.bodyMedium weight .medium, AppColors.textOnUserBubble
//   - No label above
//
// Card-type messages render the appropriate inline card.
// Tips and action buttons render below the main content.

struct MessageBubbleView: View {
    let message: ChatMessage
    @EnvironmentObject private var chatViewModel: ChatViewModel

    // MARK: - Body

    var body: some View {
        if let responseType = message.responseType, !isTextOnly(responseType) {
            cardBubble(for: responseType)
        } else if message.isFromUser {
            userBubble
        } else {
            aiBubble
        }
    }

    // MARK: - AI Bubble

    private var aiBubble: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                aiLabel

                FormattedMessageView(content: message.content)
                    .padding(.vertical, AppSpacing.xs)
            }
            .frame(maxWidth: bubbleMaxWidth, alignment: .leading)

            Spacer(minLength: spacerMinWidth)
        }
    }

    // MARK: - User Bubble

    private var userBubble: some View {
        HStack(alignment: .top, spacing: 0) {
            Spacer(minLength: spacerMinWidth)

            Text(message.content)
                .font(AppTypography.chatBody)
                .foregroundColor(AppColors.textOnUserBubble)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.md)
                .background(AppColors.backgroundUserBubble)
                .clipShape(BubbleShape(isFromUser: true))
                .frame(maxWidth: bubbleMaxWidth, alignment: .trailing)
        }
    }

    // MARK: - Card Bubble

    private func cardBubble(for responseType: ResponseType) -> some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                aiLabel
                cardContent(for: responseType)
            }
            .frame(maxWidth: bubbleMaxWidth, alignment: .leading)

            Spacer(minLength: spacerMinWidth)
        }
    }

    // MARK: - AI Label

    private var aiLabel: some View {
        HStack(spacing: AppSpacing.xs) {
            Circle()
                .fill(AppColors.accent)
                .frame(width: 6, height: 6)

            Text(L10n.Chat.walletAI)
                .font(AppTypography.labelSmall)
                .foregroundColor(AppColors.textTertiary)
        }
    }

    // MARK: - Card Content Routing

    @ViewBuilder
    private func cardContent(for responseType: ResponseType) -> some View {
        switch responseType {
        case .text:
            FormattedMessageView(content: message.content)
                .padding(.vertical, AppSpacing.xs)

        case let .sendConfirmCard(toAddress, amount, fee, feeRate, estimatedMinutes, remainingBalance):
            TransactionConfirmCard(
                amount: amount,
                fiatAmount: 0,
                toAddress: toAddress,
                fee: fee,
                feeRate: feeRate,
                estimatedMinutes: estimatedMinutes,
                remainingBalance: remainingBalance,
                onConfirm: { chatViewModel.confirmTransaction() },
                onCancel: { chatViewModel.cancelTransaction() },
                onChangeFee: {}
            )

        case let .receiveCard(address, addressType):
            ReceiveQRCard(
                address: address,
                addressType: addressType,
                onCopy: { chatViewModel.copyAddress(address) },
                onShare: { chatViewModel.shareText(address) }
            )

        case let .balanceCard(btc, fiat, pending, utxoCount):
            BalanceSummaryCard(
                totalBalance: btc,
                confirmedBalance: btc - pending,
                pendingBalance: pending,
                fiatBalance: fiat,
                utxoCount: utxoCount,
                lastUpdated: Date()
            )

        case let .historyCard(transactions):
            TransactionHistoryCard(
                transactions: transactions,
                onTapTransaction: { txid in chatViewModel.viewTransactionDetail(txid) }
            )

        case let .successCard(txid, amount, toAddress):
            TransactionSuccessCard(
                txid: txid,
                amount: amount,
                fiatAmount: 0,
                toAddress: toAddress,
                onCopyTxid: { chatViewModel.copyTransactionID(txid) },
                onViewExplorer: {}
            )

        case let .feeCard(slow, medium, fast):
            FeeCardView(slow: slow, medium: medium, fast: fast)

        case let .priceCard(btcPrice, currency, formattedPrice):
            PriceCard(
                btcPrice: btcPrice,
                currency: currency,
                formattedPrice: formattedPrice
            )

        case let .tipsCard(tip):
            TipsCard(tip: tip)

        case let .actionButtons(buttons):
            ActionButtonsCard(buttons: buttons) { command in
                chatViewModel.sendMessage(command)
            }

        case .errorText:
            FormattedMessageView(content: message.content)
                .padding(.vertical, AppSpacing.xs)
        }
    }

    // MARK: - Helpers

    private func isTextOnly(_ responseType: ResponseType) -> Bool {
        switch responseType {
        case .text, .errorText:
            return true
        default:
            return false
        }
    }

    // MARK: - Layout Constants

    private var bubbleMaxWidth: CGFloat {
        UIScreen.main.bounds.width * 0.82
    }

    private var spacerMinWidth: CGFloat {
        UIScreen.main.bounds.width * 0.04
    }
}

// MARK: - FeeCardView

private struct FeeCardView: View {
    let slow: FeeDisplayItem
    let medium: FeeDisplayItem
    let fast: FeeDisplayItem

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(L10n.Chat.feeEstimate)
                .font(AppTypography.labelMedium)
                .foregroundColor(AppColors.textPrimary)

            feeTierRow(item: fast)
            feeTierRow(item: medium)
            feeTierRow(item: slow)
        }
        .padding(AppSpacing.lg)
        .background(AppColors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppCornerRadius.xl, style: .continuous)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    private func feeTierRow(item: FeeDisplayItem) -> some View {
        HStack {
            Text(item.level)
                .font(AppTypography.bodyMedium)
                .fontWeight(.medium)
                .foregroundColor(AppColors.textPrimary)

            Spacer()

            VStack(alignment: .trailing, spacing: AppSpacing.xxxs) {
                Text(L10n.Format.feeRate("\(item.satPerVB)"))
                    .font(AppTypography.bodySmall)
                    .foregroundColor(AppColors.textSecondary)

                Text("~\(L10n.Format.estimatedMinutes(item.estimatedMinutes))")
                    .font(AppTypography.labelSmall)
                    .foregroundColor(AppColors.textTertiary)
            }
        }
        .padding(.vertical, AppSpacing.xxs)
    }
}

// MARK: - BubbleShape

struct BubbleShape: Shape {
    let isFromUser: Bool

    func path(in rect: CGRect) -> Path {
        let tl: CGFloat = AppCornerRadius.xl
        let tr: CGFloat = AppCornerRadius.xl
        let bl: CGFloat = isFromUser ? AppCornerRadius.xl : AppCornerRadius.small
        let br: CGFloat = isFromUser ? AppCornerRadius.small : AppCornerRadius.xl

        return Path { path in
            let w = rect.width
            let h = rect.height

            path.move(to: CGPoint(x: tl, y: 0))
            path.addLine(to: CGPoint(x: w - tr, y: 0))
            path.addArc(center: CGPoint(x: w - tr, y: tr), radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
            path.addLine(to: CGPoint(x: w, y: h - br))
            path.addArc(center: CGPoint(x: w - br, y: h - br), radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: CGPoint(x: bl, y: h))
            path.addArc(center: CGPoint(x: bl, y: h - bl), radius: bl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            path.addLine(to: CGPoint(x: 0, y: tl))
            path.addArc(center: CGPoint(x: tl, y: tl), radius: tl, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct MessageBubbleView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: AppSpacing.md) {
            MessageBubbleView(message: ChatMessage(
                content: "Hello! I'm your Bitcoin wallet assistant. How can I help you today?",
                isFromUser: false
            ))

            MessageBubbleView(message: ChatMessage(
                content: "What's my balance?",
                isFromUser: true
            ))
        }
        .environmentObject(ChatViewModel())
        .padding(AppSpacing.lg)
        .background(AppColors.backgroundPrimary)
        .preferredColorScheme(.dark)
        .previewLayout(.sizeThatFits)
    }
}
#endif
