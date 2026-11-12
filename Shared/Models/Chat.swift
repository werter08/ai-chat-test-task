import Foundation
import SwiftData

@Model
final class Chat {
    static let defaultTitle = "New chat"

    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    /// Raw `ChatMode`; nil = general chat.
    var modeRaw: String?
    @Relationship(deleteRule: .cascade, inverse: \Message.chat)
    var messages: [Message] = []

    init(title: String = Chat.defaultTitle) {
        self.id = UUID()
        self.title = title
        self.createdAt = .now
        self.updatedAt = .now
    }

    var mode: ChatMode? {
        get { modeRaw.flatMap(ChatMode.init(rawValue:)) }
        set { modeRaw = newValue?.rawValue }
    }

    var sortedMessages: [Message] {
        messages.sorted { $0.createdAt < $1.createdAt }
    }

    var lastMessage: Message? {
        messages.max { $0.createdAt < $1.createdAt }
    }
}
