import SwiftUI

// MARK: - ChatInputBar
// Fixed input bar at the bottom of the chat interface.
// Contains a text field for natural language input and a circular send button.
//
// - Background: AppColors.backgroundSecondary with top border
// - TextField: rounded rect background (AppColors.backgroundTertiary)
// - Placeholder: L10n.Chat.inputPlaceholder
// - Send button: circle with arrow up icon, accent when text present, gray when empty
// - Respects safe area for bottom padding

struct ChatInputBar: View {
    @Binding var text: String
    let onSend: () -> Void

    @FocusState private var isFocused: Bool

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Top border separator
            Rectangle()
                .fill(AppColors.separator)
                .frame(height: 1)

            HStack(alignment: .bottom, spacing: AppSpacing.md) {
                // Text input field with warm-tinted rounded background
                TextField(L10n.Chat.inputPlaceholder, text: $text, axis: .vertical)
                    .font(AppTypography.chatBody)
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(1...5)
                    .focused($isFocused)
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.md)
                    .background(AppColors.backgroundInput)
                    .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.xl, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppCornerRadius.xl, style: .continuous)
                            .stroke(
                                isFocused ? AppColors.accent.opacity(0.5) : AppColors.border,
                                lineWidth: 1
                            )
                    )
                    .submitLabel(.send)
                    .onSubmit {
                        sendIfNotEmpty()
                    }

                // Send button — circular with arrow up
                Button(action: sendIfNotEmpty) {
                    Image(systemName: AppIcons.sendMessage)
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(canSend ? AppColors.accent : AppColors.textTertiary)
                }
                .disabled(!canSend)
                .animation(.easeInOut(duration: 0.2), value: canSend)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md)
        }
        .background(AppColors.backgroundSecondary)
    }

    // MARK: - Computed Properties

    /// Whether the send button should be enabled.
    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Actions

    /// Sends the message if the text field is not empty.
    private func sendIfNotEmpty() {
        guard canSend else { return }
        onSend()
    }
}

// MARK: - Preview

#if DEBUG
struct ChatInputBar_Previews: PreviewProvider {
    @State static var text = ""

    static var previews: some View {
        VStack {
            Spacer()
            ChatInputBar(text: $text, onSend: {})
        }
        .background(AppColors.backgroundPrimary)
        .preferredColorScheme(.dark)
    }
}
#endif
