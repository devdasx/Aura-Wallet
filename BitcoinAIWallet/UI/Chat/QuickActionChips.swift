import SwiftUI

// MARK: - QuickActionChips
// Horizontally scrollable row of action chips displayed above the chat input bar.
// Each chip dispatches a quick action command to the ChatViewModel.
//
// QuickAction is a top-level enum defined in ChatViewModel.swift.

struct QuickActionChips: View {
    let onAction: (QuickAction) -> Void

    /// The actions to display, in presentation order.
    private let actions: [ChipItem] = [
        ChipItem(action: .send, icon: AppIcons.send, label: L10n.QuickAction.send),
        ChipItem(action: .receive, icon: AppIcons.receive, label: L10n.QuickAction.receive),
        ChipItem(action: .history, icon: AppIcons.history, label: L10n.QuickAction.history),
        ChipItem(action: .fees, icon: AppIcons.fees, label: L10n.QuickAction.fees),
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.sm) {
                ForEach(actions) { item in
                    QuickActionChipButton(item: item) {
                        onAction(item.action)
                    }
                }
            }
            .padding(.horizontal, AppSpacing.lg)
        }
    }
}

// MARK: - ChipItem

/// Data model for a single quick-action chip.
private struct ChipItem: Identifiable {
    let id = UUID()
    let action: QuickAction
    let icon: String
    let label: String
}

// MARK: - QuickActionChipButton

/// A single chip button with icon and label, styled as a bordered pill.
private struct QuickActionChipButton: View {
    let item: ChipItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: item.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppColors.accent)

                Text(item.label)
                    .font(AppTypography.buttonSmall)
                    .foregroundColor(AppColors.textPrimary)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
            .background(AppColors.backgroundSecondary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(AppColors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#if DEBUG
struct QuickActionChips_Previews: PreviewProvider {
    static var previews: some View {
        QuickActionChips(onAction: { _ in })
            .padding(.vertical, AppSpacing.sm)
            .background(AppColors.backgroundPrimary)
            .preferredColorScheme(.dark)
            .previewLayout(.sizeThatFits)
    }
}
#endif
