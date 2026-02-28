import SwiftUI

// MARK: - InlineActionButtons
// Pill-shaped, accent-tinted buttons rendered inside AI chat bubbles.
// Used during active flows (send → paste/scan, receive → copy/share).
// Not shown in loaded conversation history.
//
// Visual: pill shape, accent text + icon, accent-tinted background,
// subtle accent border. Horizontally laid out below message text.

struct InlineActionButtons: View {
    let actions: [InlineAction]
    let onAction: (InlineAction) -> Void

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            ForEach(actions) { action in
                Button(action: {
                    HapticManager.lightTap()
                    onAction(action)
                }) {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: action.icon)
                            .font(.system(size: 13, weight: .medium))

                        Text(action.label)
                            .font(AppTypography.bodySmall)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(AppColors.accent)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.sm)
                    .background(AppColors.accent.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.pill, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppCornerRadius.pill, style: .continuous)
                            .stroke(AppColors.accent.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, AppSpacing.sm)
    }
}

// MARK: - Preview

#if DEBUG
struct InlineActionButtons_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: AppSpacing.lg) {
            // Send flow buttons
            InlineActionButtons(
                actions: [
                    InlineAction(icon: "doc.on.clipboard", label: "Paste Clipboard", type: .pasteAddress),
                    InlineAction(icon: "qrcode.viewfinder", label: "Scan QR", type: .scanQR),
                ],
                onAction: { _ in }
            )

            // Receive flow buttons
            InlineActionButtons(
                actions: [
                    InlineAction(icon: "doc.on.doc", label: "Copy Address", type: .copyText),
                    InlineAction(icon: "square.and.arrow.up", label: "Share", type: .shareText),
                ],
                onAction: { _ in }
            )
        }
        .padding(AppSpacing.lg)
        .background(AppColors.backgroundPrimary)
        .preferredColorScheme(.dark)
        .previewLayout(.sizeThatFits)
    }
}
#endif
