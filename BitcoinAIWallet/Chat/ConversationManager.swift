import Foundation
import SwiftData
import SwiftUI

// MARK: - ConversationManager
// Manages conversation CRUD operations using SwiftData.
// Handles creating, loading, switching, renaming, deleting conversations
// and auto-titling based on the first user message.

@MainActor
final class ConversationManager: ObservableObject {

    // MARK: - Properties

    @Published var currentConversation: Conversation?

    private var modelContext: ModelContext

    // MARK: - Initialization

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Create

    /// Creates a new empty conversation and sets it as current.
    @discardableResult
    func createNewConversation() -> Conversation {
        let conversation = Conversation(title: localizedString("sidebar.new_chat"))
        modelContext.insert(conversation)
        currentConversation = conversation
        return conversation
    }

    // MARK: - Load

    /// Always starts a fresh conversation on app launch.
    /// Reuses the most recent empty conversation to avoid duplicates.
    func loadOrCreateInitial() {
        let descriptor = FetchDescriptor<Conversation>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let conversations = (try? modelContext.fetch(descriptor)) ?? []

        // Reuse the most recent conversation if it has no messages
        if let latest = conversations.first, latest.messages.isEmpty {
            currentConversation = latest
        } else {
            createNewConversation()
        }
    }

    /// Switches to a specific conversation.
    func switchTo(_ conversation: Conversation) {
        currentConversation = conversation
    }

    // MARK: - Messages

    /// Loads all persisted messages for the current conversation, sorted by timestamp.
    func loadMessages() -> [PersistedMessage] {
        guard let conversation = currentConversation else { return [] }
        return conversation.messages.sorted { $0.timestamp < $1.timestamp }
    }

    /// Persists a new message to the current conversation.
    @discardableResult
    func persistMessage(role: String, content: String, intentType: String? = nil) -> PersistedMessage? {
        guard let conversation = currentConversation else { return nil }
        let message = PersistedMessage(
            role: role,
            content: content,
            intentType: intentType
        )
        message.conversation = conversation
        conversation.messages.append(message)
        conversation.updatedAt = Date()
        modelContext.insert(message)
        return message
    }

    // MARK: - Auto-Title

    /// Updates the conversation title from the first user message.
    func autoTitleIfNeeded(firstUserMessage: String) {
        guard let conversation = currentConversation else { return }
        // Only auto-title if it still has the default title
        let defaultTitle = localizedString("sidebar.new_chat")
        guard conversation.title == defaultTitle || conversation.title == "New Chat" else { return }

        // Truncate to ~40 characters at a word boundary
        let truncated = truncateAtWord(firstUserMessage, maxLength: 40)
        conversation.title = truncated
    }

    // MARK: - Delete

    /// Deletes a conversation and all its messages.
    func delete(_ conversation: Conversation) {
        let wasCurrent = conversation.id == currentConversation?.id
        modelContext.delete(conversation)

        if wasCurrent {
            currentConversation = nil
            loadOrCreateInitial()
        }
    }

    // MARK: - Rename

    /// Renames a conversation.
    func rename(_ conversation: Conversation, to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        conversation.title = trimmed
    }

    // MARK: - Pin

    /// Toggles the pinned state of a conversation.
    func togglePin(_ conversation: Conversation) {
        conversation.isPinned.toggle()
    }

    // MARK: - Helpers

    /// Truncates a string at a word boundary.
    private func truncateAtWord(_ text: String, maxLength: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxLength else { return trimmed }

        let truncated = String(trimmed.prefix(maxLength))
        // Find last space to avoid cutting mid-word
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace]) + "..."
        }
        return truncated + "..."
    }
}
