import SwiftUI
import SwiftData

// MARK: - ConversationSidebarView
// Sidebar showing all past conversations, grouped by date.
// Supports search, swipe-to-delete, pin/unpin, and new chat creation.
// Rendered inside a NavigationSplitView as the sidebar column.

struct ConversationSidebarView: View {
    @Binding var selectedConversation: Conversation?
    @Binding var isOpen: Bool
    @ObservedObject var conversationManager: ConversationManager
    let onSettings: () -> Void

    @Query(sort: \Conversation.updatedAt, order: .reverse)
    private var allConversations: [Conversation]

    @State private var searchText: String = ""
    @State private var conversationToDelete: Conversation?
    @State private var showDeleteConfirmation = false
    @State private var conversationToRename: Conversation?
    @State private var renameText: String = ""
    @State private var showRenameAlert = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            sidebarHeader

            // Search bar
            searchBar

            // Conversation list
            conversationList

            // Bottom settings row
            Divider().background(AppColors.separator)
            settingsRow
        }
        .background(AppColors.backgroundPrimary)
        .alert(L10n.Sidebar.deleteConversation, isPresented: $showDeleteConfirmation) {
            Button(L10n.Common.cancel, role: .cancel) {}
            Button(L10n.Common.delete, role: .destructive) {
                if let conversation = conversationToDelete {
                    conversationManager.delete(conversation)
                    if selectedConversation?.id == conversation.id {
                        selectedConversation = conversationManager.currentConversation
                    }
                }
            }
        } message: {
            Text(L10n.Sidebar.deleteConfirmMessage)
        }
        .alert(L10n.Sidebar.rename, isPresented: $showRenameAlert) {
            TextField(L10n.Sidebar.conversationName, text: $renameText)
            Button(L10n.Common.cancel, role: .cancel) {}
            Button(L10n.Common.save) {
                if let conversation = conversationToRename {
                    conversationManager.rename(conversation, to: renameText)
                }
            }
        }
    }

    // MARK: - Header

    private var sidebarHeader: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: AppIcons.bitcoin)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AppColors.accent)

            Text(L10n.Common.appName)
                .font(AppTypography.headingMedium)
                .foregroundColor(AppColors.textPrimary)

            Spacer()

            // New chat button
            Button {
                HapticManager.buttonTap()
                createNewChat()
            } label: {
                Image(systemName: AppIcons.plus)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppColors.accent)
                    .frame(width: 32, height: 32)
                    .background(AppColors.backgroundSecondary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.md)
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(AppTypography.bodySmall)
                .foregroundColor(AppColors.textTertiary)

            TextField(L10n.Sidebar.searchPlaceholder, text: $searchText)
                .font(AppTypography.bodyMedium)
                .foregroundColor(AppColors.textPrimary)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .background(AppColors.backgroundInput)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium, style: .continuous))
        .padding(.horizontal, AppSpacing.lg)
        .padding(.bottom, AppSpacing.sm)
    }

    // MARK: - Conversation List

    private var conversationList: some View {
        ScrollView {
            if filteredConversations.isEmpty {
                VStack(spacing: AppSpacing.md) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 32))
                        .foregroundColor(AppColors.textTertiary)
                    Text(L10n.Sidebar.noConversations)
                        .font(AppTypography.bodyMedium)
                        .foregroundColor(AppColors.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, AppSpacing.huge)
            } else {
                LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                    // Pinned conversations
                    let pinned = filteredConversations.filter(\.isPinned)
                    if !pinned.isEmpty {
                        sectionView(title: L10n.Sidebar.pinned, conversations: pinned)
                    }

                    // Today
                    let today = unpinnedForPeriod(.today)
                    if !today.isEmpty {
                        sectionView(title: L10n.Chat.today, conversations: today)
                    }

                    // Yesterday
                    let yesterday = unpinnedForPeriod(.yesterday)
                    if !yesterday.isEmpty {
                        sectionView(title: L10n.Sidebar.yesterday, conversations: yesterday)
                    }

                    // This Week
                    let thisWeek = unpinnedForPeriod(.thisWeek)
                    if !thisWeek.isEmpty {
                        sectionView(title: L10n.Sidebar.thisWeek, conversations: thisWeek)
                    }

                    // Older
                    let older = unpinnedForPeriod(.older)
                    if !older.isEmpty {
                        sectionView(title: L10n.Sidebar.older, conversations: older)
                    }
                }
            }
        }
    }

    // MARK: - Section

    private func sectionView(title: String, conversations: [Conversation]) -> some View {
        Section {
            ForEach(conversations) { conversation in
                ConversationRowView(
                    conversation: conversation,
                    isSelected: selectedConversation?.id == conversation.id
                )
                .onTapGesture {
                    HapticManager.selection()
                    selectedConversation = conversation
                    withAnimation(.easeInOut(duration: 0.25)) { isOpen = false }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        conversationToDelete = conversation
                        showDeleteConfirmation = true
                    } label: {
                        Label(L10n.Common.delete, systemImage: AppIcons.trash)
                    }

                    Button {
                        HapticManager.selection()
                        conversationManager.togglePin(conversation)
                    } label: {
                        Label(
                            conversation.isPinned ? L10n.Sidebar.unpin : L10n.Sidebar.pin,
                            systemImage: conversation.isPinned ? "pin.slash.fill" : "pin.fill"
                        )
                    }
                    .tint(AppColors.warning)
                }
                .contextMenu {
                    Button {
                        conversationToRename = conversation
                        renameText = conversation.title
                        showRenameAlert = true
                    } label: {
                        Label(L10n.Sidebar.rename, systemImage: "pencil")
                    }

                    Button {
                        conversationManager.togglePin(conversation)
                    } label: {
                        Label(
                            conversation.isPinned ? L10n.Sidebar.unpin : L10n.Sidebar.pin,
                            systemImage: conversation.isPinned ? "pin.slash.fill" : "pin.fill"
                        )
                    }

                    Divider()

                    Button(role: .destructive) {
                        conversationToDelete = conversation
                        showDeleteConfirmation = true
                    } label: {
                        Label(L10n.Common.delete, systemImage: AppIcons.trash)
                    }
                }
            }
        } header: {
            Text(title)
                .font(AppTypography.labelSmall)
                .foregroundColor(AppColors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.xs)
                .background(AppColors.backgroundPrimary)
        }
    }

    // MARK: - Settings Row

    private var settingsRow: some View {
        Button {
            HapticManager.buttonTap()
            onSettings()
        } label: {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: AppIcons.settings)
                    .font(AppTypography.bodyMedium)
                    .foregroundColor(AppColors.textSecondary)

                Text(L10n.Settings.title)
                    .font(AppTypography.bodyMedium)
                    .foregroundColor(AppColors.textPrimary)

                Spacer()

                Image(systemName: AppIcons.chevronRight)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.textTertiary)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var filteredConversations: [Conversation] {
        guard !searchText.isEmpty else { return allConversations }
        let query = searchText.lowercased()
        return allConversations.filter { conversation in
            conversation.title.lowercased().contains(query) ||
            conversation.messages.contains { $0.content.lowercased().contains(query) }
        }
    }

    private func unpinnedForPeriod(_ period: TimePeriod) -> [Conversation] {
        filteredConversations.filter { !$0.isPinned && period.contains($0.updatedAt) }
    }

    private func createNewChat() {
        let conversation = conversationManager.createNewConversation()
        selectedConversation = conversation
        withAnimation(.easeInOut(duration: 0.25)) { isOpen = false }
    }
}

// MARK: - TimePeriod

private enum TimePeriod {
    case today, yesterday, thisWeek, older

    func contains(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let now = Date()

        switch self {
        case .today:
            return calendar.isDateInToday(date)
        case .yesterday:
            return calendar.isDateInYesterday(date)
        case .thisWeek:
            guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) else { return false }
            return date > weekAgo && !calendar.isDateInToday(date) && !calendar.isDateInYesterday(date)
        case .older:
            guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) else { return false }
            return date <= weekAgo
        }
    }
}
