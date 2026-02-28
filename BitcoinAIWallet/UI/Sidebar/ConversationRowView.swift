import SwiftUI

// MARK: - ConversationRowView
// A single row in the conversation sidebar list.
// Shows the conversation title (truncated) and relative timestamp.
// Highlighted when selected.

struct ConversationRowView: View {
    let conversation: Conversation
    let isSelected: Bool

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            // Pin indicator
            if conversation.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundColor(AppColors.warning)
            }

            VStack(alignment: .leading, spacing: AppSpacing.xxxs) {
                Text(conversation.title)
                    .font(AppTypography.bodyMedium)
                    .fontWeight(.medium)
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(1)

                Text(relativeTimestamp)
                    .font(AppTypography.labelSmall)
                    .foregroundColor(AppColors.textTertiary)
            }

            Spacer()
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: AppCornerRadius.large, style: .continuous)
                .fill(isSelected ? AppColors.sidebarActiveRow : Color.clear)
        )
        .padding(.horizontal, AppSpacing.sm)
        .contentShape(Rectangle())
    }

    // MARK: - Timestamp

    private var relativeTimestamp: String {
        let calendar = Calendar.current
        let date = conversation.updatedAt

        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return L10n.Sidebar.yesterday
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}
