import SwiftUI

// MARK: - ChatView
// Main scrollable chat message list.
// Messages scroll from bottom; new messages auto-scroll into view.
// Displays a date separator, message bubbles, and a typing indicator.
// Auto-scrolls during typing animation unless the user has scrolled up.

struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel

    /// Tracks whether the user has manually scrolled away from the bottom.
    /// When true, auto-scroll is suppressed so we don't fight user intent.
    @State private var isNearBottom: Bool = true

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: AppSpacing.md) {
                    // Date separator for "Today"
                    dateSeparator

                    // Message bubbles
                    ForEach(viewModel.messages) { message in
                        MessageBubbleView(message: message)
                            .id(message.id)
                    }

                    // Processing card when an async operation is in progress
                    if let processingState = viewModel.activeProcessingState {
                        HStack(alignment: .top, spacing: 0) {
                            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                                // "Wallet AI" label (matches TypingIndicator)
                                HStack(spacing: AppSpacing.xs) {
                                    Circle()
                                        .fill(AppColors.accent)
                                        .frame(width: 6, height: 6)

                                    Text(L10n.Chat.walletAI)
                                        .font(AppTypography.labelSmall)
                                        .foregroundColor(AppColors.textTertiary)
                                }

                                AIProcessingIndicator(processingState: processingState)
                            }
                            .frame(maxWidth: UIScreen.main.bounds.width * 0.82, alignment: .leading)
                            Spacer(minLength: UIScreen.main.bounds.width * 0.04)
                        }
                        .id("processing")
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.98)),
                            removal: .opacity
                        ))
                    }

                    // Typing indicator when AI is generating a response
                    if viewModel.isTyping {
                        TypingIndicator()
                            .id("typing")
                    }

                    // Bottom anchor for scroll-position detection
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                        .onAppear { isNearBottom = true }
                        .onDisappear { isNearBottom = false }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.md)
                .padding(.bottom, AppSpacing.sm)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.3)) {
                    scrollToBottom(proxy: proxy)
                }
            }
            .onChange(of: viewModel.isTyping) { _, typing in
                if typing {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo("typing", anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.activeProcessingState != nil) { _, isActive in
                if isActive {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo("processing", anchor: .bottom)
                    }
                }
            }
            // Auto-scroll during typing animation (every ~10 characters)
            .onReceive(NotificationCenter.default.publisher(for: .typingAnimationProgress)) { _ in
                guard isNearBottom else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    scrollToBottom(proxy: proxy)
                }
            }
        }
        .background(AppColors.backgroundPrimary)
    }

    // MARK: - Date Separator

    /// A centered pill showing the current date grouping label (e.g., "Today").
    private var dateSeparator: some View {
        Text(L10n.Chat.today)
            .font(AppTypography.labelSmall)
            .foregroundColor(AppColors.textTertiary)
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.xxs)
            .background(AppColors.backgroundSecondary)
            .clipShape(Capsule())
            .padding(.vertical, AppSpacing.sm)
    }

    // MARK: - Helpers

    /// Scrolls to the latest message, processing card, or typing indicator.
    private func scrollToBottom(proxy: ScrollViewProxy) {
        if viewModel.isTyping {
            proxy.scrollTo("typing", anchor: .bottom)
        } else if viewModel.activeProcessingState != nil {
            proxy.scrollTo("processing", anchor: .bottom)
        } else if let lastID = viewModel.messages.last?.id {
            proxy.scrollTo(lastID, anchor: .bottom)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ChatView_Previews: PreviewProvider {
    static var previews: some View {
        ChatView(viewModel: ChatViewModel())
            .preferredColorScheme(.dark)
    }
}
#endif
