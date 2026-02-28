import SwiftUI

// MARK: - TypingIndicator
// Animated three-dot indicator shown while the AI is generating a response.
// Left-aligned like an AI message with the "Wallet AI" label above.
// Three dots animate sequentially with an opacity pulse effect.

struct TypingIndicator: View {
    @State private var animating = false

    // MARK: - Body

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                // "Wallet AI" label with orange dot
                HStack(spacing: AppSpacing.xs) {
                    Circle()
                        .fill(AppColors.accent)
                        .frame(width: 6, height: 6)

                    Text(L10n.Chat.walletAI)
                        .font(AppTypography.labelSmall)
                        .foregroundColor(AppColors.textTertiary)
                }

                // Animated dots — no bubble, sits on background
                HStack(spacing: AppSpacing.xs) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(AppColors.textTertiary)
                            .frame(width: 7, height: 7)
                            .opacity(animating ? 0.3 : 1.0)
                            .animation(
                                .easeInOut(duration: 0.6)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(index) * 0.2),
                                value: animating
                            )
                    }
                }
                .padding(.vertical, AppSpacing.sm)
            }

            Spacer()
        }
        .onAppear {
            animating = true
        }
    }
}

// MARK: - Preview

#if DEBUG
struct TypingIndicator_Previews: PreviewProvider {
    static var previews: some View {
        TypingIndicator()
            .padding(AppSpacing.lg)
            .background(AppColors.backgroundPrimary)
            .preferredColorScheme(.dark)
            .previewLayout(.sizeThatFits)
    }
}
#endif
