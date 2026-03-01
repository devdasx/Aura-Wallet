import SwiftUI
import UIKit

// MARK: - ChatInputBar
// Floating input bar at the bottom of the chat interface.
// Matches Claude's design: rounded, glass-effect background, floating with padding.
//
// Bottom toolbar: [Paste] [QR Scan] ---- [Mic] [Send]
// Paste button only visible when clipboard has content.
// Send button is a filled circle — accent when text, muted when empty.
//
// iOS 26+: Uses .glassEffect(.regular) for Liquid Glass material.
// Pre-iOS 26: Warm semi-transparent card background.

struct ChatInputBar: View {
    @Binding var text: String
    let onSend: () -> Void
    let onScanQR: () -> Void
    let onPaste: () -> Void

    @FocusState private var isFocused: Bool
    @State private var hasClipboardContent: Bool = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: AppSpacing.sm) {
                // Text editor — multi-line, grows up to 6 lines
                TextField(L10n.Chat.inputPlaceholder, text: $text, axis: .vertical)
                    .font(AppTypography.chatBody)
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(1...6)
                    .focused($isFocused)
                    .submitLabel(.send)
                    .onSubmit {
                        sendIfNotEmpty()
                    }

                // Bottom toolbar row
                HStack(spacing: AppSpacing.lg) {
                    // Left side: Paste + QR Scan
                    HStack(spacing: AppSpacing.md) {
                        // Paste button — only visible when clipboard has content
                        if hasClipboardContent {
                            Button(action: {
                                HapticManager.lightTap()
                                onPaste()
                            }) {
                                Image(systemName: "doc.on.clipboard")
                                    .font(.system(size: 16))
                                    .foregroundColor(AppColors.textSecondary)
                            }
                            .buttonStyle(.plain)
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                        }

                        // QR Scanner button
                        Button(action: {
                            HapticManager.lightTap()
                            onScanQR()
                        }) {
                            Image(systemName: AppIcons.scan)
                                .font(.system(size: 16))
                                .foregroundColor(AppColors.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    // Right side: Send button
                    HStack(spacing: AppSpacing.md) {
                        // Send button — filled circle
                        Button(action: sendIfNotEmpty) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(canSend ? AppColors.textOnAccent : AppColors.textTertiary)
                                .frame(width: 32, height: 32)
                                .background(
                                    Circle()
                                        .fill(canSend ? AppColors.accent : AppColors.backgroundTertiary)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSend)
                        .animation(.easeInOut(duration: 0.2), value: canSend)
                    }
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md)
            .background(inputBackground)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(AppColors.border.opacity(0.5), lineWidth: 0.5)
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .onAppear {
            checkClipboard()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
            checkClipboard()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            checkClipboard()
        }
    }

    // MARK: - Input Background

    @ViewBuilder
    private var inputBackground: some View {
        // Warm semi-transparent background
        AppColors.backgroundCard.opacity(0.95)
    }

    // MARK: - Computed Properties

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Actions

    private func sendIfNotEmpty() {
        guard canSend else { return }
        isFocused = false
        HapticManager.lightTap()
        onSend()
    }

    private func checkClipboard() {
        withAnimation(.easeInOut(duration: 0.2)) {
            hasClipboardContent = UIPasteboard.general.hasStrings || UIPasteboard.general.hasURLs
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ChatInputBar_Previews: PreviewProvider {
    @State static var text = ""

    static var previews: some View {
        VStack {
            Spacer()
            ChatInputBar(text: $text, onSend: {}, onScanQR: {}, onPaste: {})
        }
        .background(AppColors.backgroundPrimary)
        .preferredColorScheme(.dark)
    }
}
#endif
