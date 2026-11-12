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
    /// Only the most recent messages that carry photos are sent with their pictures (request size).
    nonisolated static let maxPhotoMessages = 3
    nonisolated static let stoppedNote = "You stopped the response."
    nonisolated static let systemPrompt = "You are a helpful, concise assistant. Answer in the user's language."

    private(set) var states: [UUID: State] = [:]
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]
    /// Chats whose generation the user stopped by hand (as opposed to being cancelled by a deletion).
    @ObservationIgnored private var stopRequested: Set<UUID> = []
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

    /// Sends a user message. `images` are already downscaled JPEGs; a message may be photos only.
    func send(_ text: String, images: [Data] = [], in chat: Chat, context: ModelContext) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !images.isEmpty, !state(for: chat).isGenerating else { return }

        let message = Message(role: .user, content: trimmed)
        message.chat = chat
        context.insert(message)
        for (index, data) in images.prefix(ImageProcessing.maxPhotosPerMessage).enumerated() {
            let attachment = Attachment(data: data, createdAt: Date.now.addingTimeInterval(Double(index) * 0.001))
            attachment.message = message
            context.insert(attachment)
        }
        if chat.title == Chat.defaultTitle {
            chat.title = Self.makeTitle(from: trimmed.isEmpty ? "Photo" : trimmed)
        }
        chat.updatedAt = .now
        try? context.save()
        generate(in: chat, context: context)
    }

    /// Re-requests the answer to the last user message, dropping any "stopped" note and partial/failed reply.
    func retry(_ chat: Chat, context: ModelContext) {
        guard !state(for: chat).isGenerating else { return }
        while let last = chat.lastMessage, last.role == .note { remove(last, from: chat, context: context) }
        if let last = chat.lastMessage, last.role == .assistant { remove(last, from: chat, context: context) }
        try? context.save()
        guard chat.lastMessage?.role == .user else { return }
        generate(in: chat, context: context)
    }

    /// Stops the running generation. The partial reply is kept and a "stopped" note is added to the chat;
    /// this is not an error.
    func stop(_ chat: Chat) {
        guard let task = tasks[chat.id] else { return }
        stopRequested.insert(chat.id)
        task.cancel()
    }

    /// Cancels and forgets everything about a chat (call before deleting it).
    func discard(_ chat: Chat) {
        tasks[chat.id]?.cancel()
        tasks[chat.id] = nil
        states[chat.id] = nil
        stopRequested.remove(chat.id)
    }

    /// Detach first: a deleted model stays in `chat.messages` until the context saves.
    private func remove(_ message: Message, from chat: Chat, context: ModelContext) {
        chat.messages.removeAll { $0.id == message.id }
        context.delete(message)
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
                // A cancelled stream ends quietly (no error) — only a *non-cancelled* empty stream is a failure.
                if reply == nil && !Task.isCancelled { failure = .invalidResponse }
            } catch is CancellationError {
                // Stopped — handled below.
            } catch {
                failure = (error as? ChatAPIError) ?? ChatAPIError.from(transport: error)
            }
            // The chat may have been deleted while generating (`discard` clears the task entry): touch nothing then.
            guard let self, self.tasks[chatID] != nil else { return }
            if self.stopRequested.remove(chatID) != nil {
                failure = nil
                let note = Message(role: .note, content: Self.stoppedNote)
                note.chat = chat
                context.insert(note)
            }
            chat.updatedAt = .now
            try? context.save()
            self.finish(chatID: chatID, error: failure)
        }
    }

    private func finish(chatID: UUID, error: ChatAPIError?) {
        tasks[chatID] = nil
        states[chatID] = State(isGenerating: false, error: error)
    }

    // MARK: Helpers

    nonisolated static func buildRequest(from messages: [Message], mode: ChatMode? = nil, profile: UserProfile = UserProfile()) -> [APIMessage] {
        let conversation = messages.filter { $0.role != .note }.suffix(maxContextMessages)
        let withPhotos = Set(conversation.filter { !$0.attachments.isEmpty }.suffix(maxPhotoMessages).map(\.id))
        let recent = conversation.map { message -> APIMessage in
            guard !message.attachments.isEmpty else {
                return APIMessage(role: message.roleRaw, content: message.content)
            }
            let urls = withPhotos.contains(message.id)
                ? message.sortedAttachments.map { "data:image/jpeg;base64," + $0.data.base64EncodedString() }
                : []
            // A photo-only message still needs some text; older photos that are no longer sent become a marker.
            let text = message.content.isEmpty ? (urls.isEmpty ? "[photo]" : "Describe this image.") : message.content
            return APIMessage(role: message.roleRaw, content: text, imageURLs: urls)
        }
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
