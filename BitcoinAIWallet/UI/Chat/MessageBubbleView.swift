import SwiftUI

// MARK: - MessageBubbleView
// Individual chat message bubble.
//
// AI messages (left-aligned):
//   - No background (transparent)
//   - "Wallet AI" label with accent dot above
//   - Character-by-character typing animation for new messages
//   - Tap to skip typing animation
//
// User messages (right-aligned):
//   - Background: AppColors.backgroundUserBubble
//   - Custom BubbleShape with asymmetric corners
//
// Card-type messages render the appropriate inline card.

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
            AnimatedAIBubble(message: message)
                .environmentObject(chatViewModel)
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
                onViewExplorer: { chatViewModel.openExplorer(txid: txid) }
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
            HStack(alignment: .top, spacing: AppSpacing.sm) {
                Image(systemName: AppIcons.error)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AppColors.error)
                    .padding(.top, 2)

                FormattedMessageView(content: message.content)
            }
            .padding(AppSpacing.md)
            .background(AppColors.error.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppCornerRadius.medium, style: .continuous)
                    .stroke(AppColors.error.opacity(0.25), lineWidth: 1)
            )
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

// MARK: - AnimatedAIBubble

/// AI text bubble with typing animation for new messages.
/// Old messages from history display instantly without animation.
/// Shows inline action buttons when present (e.g., Paste/Scan during send flow).
private struct AnimatedAIBubble: View {
    let message: ChatMessage
    @EnvironmentObject private var chatViewModel: ChatViewModel
    @StateObject private var animator = TypingAnimator()

    private var bubbleMaxWidth: CGFloat {
        UIScreen.main.bounds.width * 0.82
    }

    private var spacerMinWidth: CGFloat {
        UIScreen.main.bounds.width * 0.04
    }

    /// Whether to show inline action buttons for this message.
    private var showInlineActions: Bool {
        guard let actions = message.inlineActions, !actions.isEmpty else { return false }
        guard !message.inlineActionsUsed else { return false }
        return !animator.isAnimating
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                // AI label
                HStack(spacing: AppSpacing.xs) {
                    Circle()
                        .fill(AppColors.accent)
                        .frame(width: 6, height: 6)

                    Text(L10n.Chat.walletAI)
                        .font(AppTypography.labelSmall)
                        .foregroundColor(AppColors.textTertiary)
                }

                // Animated or instant text
                FormattedMessageView(content: animator.displayedText)
                    .padding(.vertical, AppSpacing.xs)

                // Inline action buttons (e.g., Paste/Scan during send flow)
                if showInlineActions, let actions = message.inlineActions {
                    InlineActionButtons(actions: actions) { action in
                        chatViewModel.handleInlineAction(action, messageId: message.id)
                    }
                }
            }
            .frame(maxWidth: bubbleMaxWidth, alignment: .leading)

            Spacer(minLength: spacerMinWidth)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if animator.isAnimating {
                animator.skipToEnd()
            }
        }
        .onAppear {
            // Guard: only animate if truly new AND not already animated.
            // animatedMessageIDs survives SwiftUI view recreation (lives on ViewModel).
            let alreadyAnimated = chatViewModel.animatedMessageIDs.contains(message.id)
            if message.isNew && !message.isFromUser && !alreadyAnimated {
                chatViewModel.markMessageAnimated(message.id)
                animator.startTyping(message.content)
            } else {
                animator.showInstantly(message.content)
            }
        }
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
