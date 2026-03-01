import SwiftUI

// MARK: - CommandsReferenceView
// Searchable, categorized reference of all chat commands the AI understands.
// Tapping a command copies it to the clipboard and injects it into chat.
// Data sourced from CommandsData.swift — the single source of truth.
//
// Platform: iOS 17.0+

struct CommandsReferenceView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""

    private var totalCount: Int {
        CommandsData.allCategories.reduce(0) { $0 + $1.commands.count }
    }

    var body: some View {
        List {
            // Header with command count
            Section {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppColors.accent)
                    Text("\(totalCount) commands across \(CommandsData.allCategories.count) categories")
                        .font(AppTypography.labelSmall)
                        .foregroundColor(AppColors.textSecondary)
                }
                .listRowBackground(Color.clear)
            }

            ForEach(filteredCategories) { category in
                Section {
                    ForEach(category.commands) { command in
                        commandRow(command)
                    }
                } header: {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: category.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(category.color)
                        Text(category.name)
                            .font(AppTypography.labelSmall)
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppColors.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Commands")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search commands...")
    }

    // MARK: - Command Row

    private func commandRow(_ command: CommandItem) -> some View {
        Button {
            HapticManager.lightTap()
            // Don't inject placeholder commands like "(paste an address)"
            let isPlaceholder = command.example.hasPrefix("(")
            if !isPlaceholder {
                UIPasteboard.general.string = command.example
                NotificationCenter.default.post(
                    name: .chatInjectCommand,
                    object: nil,
                    userInfo: ["command": command.example]
                )
            }
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(command.example)
                    .font(AppTypography.bodyMedium)
                    .fontWeight(.medium)
                    .foregroundColor(
                        command.example.hasPrefix("(")
                            ? AppColors.textSecondary
                            : AppColors.textPrimary
                    )

                Text(command.description)
                    .font(AppTypography.labelSmall)
                    .foregroundColor(AppColors.textTertiary)
                    .lineLimit(2)
            }
            .padding(.vertical, AppSpacing.xxxs)
        }
        .buttonStyle(.plain)
        .listRowBackground(AppColors.backgroundCard)
    }

    // MARK: - Filtered Data

    private var filteredCategories: [CommandCategory] {
        if searchText.isEmpty {
            return CommandsData.allCategories
        }
        let query = searchText.lowercased()
        return CommandsData.allCategories.compactMap { category in
            let matched = category.commands.filter { cmd in
                cmd.example.lowercased().contains(query)
                || cmd.description.lowercased().contains(query)
                || category.name.lowercased().contains(query)
            }
            guard !matched.isEmpty else { return nil }
            return CommandCategory(
                name: category.name,
                icon: category.icon,
                color: category.color,
                commands: matched
            )
        }
    }
}

// MARK: - Preview

#if DEBUG
struct CommandsReferenceView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            CommandsReferenceView()
        }
        .preferredColorScheme(.dark)
    }
}
#endif
