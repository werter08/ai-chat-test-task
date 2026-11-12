import Foundation
import Observation
import SwiftData

/// Orchestrates sending, streaming, stopping and retrying — one generation task per chat.
/// Views read `state(for:)`; they never talk to the network layer directly.
@MainActor
@Observable
final class ChatEngine {
    struct State: Equatable {
        var isGenerating = false
        var error: ChatAPIError?
    }

    /// How many recent messages are sent as context (keeps requests small for free models).
    nonisolated static let maxContextMessages = 30
    nonisolated static let systemPrompt = "You are a helpful, concise assistant. Answer in the user's language."

    private(set) var states: [UUID: State] = [:]
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private let client: ChatStreaming
    @ObservationIgnored private let profile: () -> UserProfile

    init(client: ChatStreaming, profile: @escaping () -> UserProfile = { .current }) {
        self.client = client
        self.profile = profile
    }

    func state(for chat: Chat) -> State {
        states[chat.id] ?? State()
    }

    // MARK: Actions

    func send(_ text: String, in chat: Chat, context: ModelContext) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !state(for: chat).isGenerating else { return }

        let message = Message(role: .user, content: trimmed)
        message.chat = chat
        context.insert(message)
        if chat.title == Chat.defaultTitle {
            chat.title = Self.makeTitle(from: trimmed)
        }
        chat.updatedAt = .now
        try? context.save()
        generate(in: chat, context: context)
    }

    /// Re-requests the answer to the last user message, dropping any partial/failed assistant reply.
    func retry(_ chat: Chat, context: ModelContext) {
        guard !state(for: chat).isGenerating else { return }
        if let last = chat.lastMessage, last.role == .assistant {
            // Detach first: a deleted model stays in `chat.messages` until the context saves.
            chat.messages.removeAll { $0.id == last.id }
            context.delete(last)
            try? context.save()
        }
        guard chat.lastMessage?.role == .user else { return }
        generate(in: chat, context: context)
    }

    /// Stops the running generation; the partial reply is kept.
    func stop(_ chat: Chat) {
        tasks[chat.id]?.cancel()
    }

    /// Cancels and forgets everything about a chat (call before deleting it).
    func discard(_ chat: Chat) {
        tasks[chat.id]?.cancel()
        tasks[chat.id] = nil
        states[chat.id] = nil
    }

    // MARK: Generation

    private func generate(in chat: Chat, context: ModelContext) {
        let chatID = chat.id
        let history = Self.buildRequest(from: chat.sortedMessages, mode: chat.mode, profile: profile())
        states[chatID] = State(isGenerating: true, error: nil)

        tasks[chatID] = Task { [weak self, client] in
            // The assistant message is created lazily on the first token, so no empty bubble is ever persisted.
            var reply: Message?
            var failure: ChatAPIError?
            do {
                for try await delta in client.stream(messages: history) {
                    if let reply {
                        reply.content += delta
                    } else {
                        let created = Message(role: .assistant, content: delta)
                        created.chat = chat
                        context.insert(created)
                        reply = created
                    }
                }
                if reply == nil { failure = .invalidResponse }
            } catch is CancellationError {
                // Stopped by the user — keep whatever has arrived.
            } catch {
                failure = (error as? ChatAPIError) ?? ChatAPIError.from(transport: error)
            }
            chat.updatedAt = .now
            try? context.save()
            self?.finish(chatID: chatID, error: failure)
        }
    }

    private func finish(chatID: UUID, error: ChatAPIError?) {
        tasks[chatID] = nil
        states[chatID] = State(isGenerating: false, error: error)
    }

    // MARK: Helpers

    nonisolated static func buildRequest(from messages: [Message], mode: ChatMode? = nil, profile: UserProfile = UserProfile()) -> [APIMessage] {
        let recent = messages.suffix(maxContextMessages).map { APIMessage(role: $0.roleRaw, content: $0.content) }
        return [APIMessage(role: "system", content: makeSystemPrompt(mode: mode, profile: profile))] + recent
    }

    nonisolated static func makeSystemPrompt(mode: ChatMode?, profile: UserProfile) -> String {
        var parts = [systemPrompt]
        if let mode { parts.append(mode.systemPrompt) }
        let name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { parts.append("The user's name is \(name.prefix(40)).") }
        let instructions = profile.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !instructions.isEmpty {
            parts.append("Custom instructions from the user: \(instructions.prefix(UserProfile.maxInstructionsLength))")
        }
        return parts.joined(separator: "\n")
    }

    nonisolated static func makeTitle(from text: String) -> String {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return firstLine.count > 40 ? String(firstLine.prefix(40)) + "…" : firstLine
    }
}
