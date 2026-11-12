import Foundation
import SwiftData

enum MessageRole: String, Codable {
    case user
    case assistant
    /// Local, display-only marker (e.g. "You stopped the response."). Never sent to the AI.
    case note
}

@Model
final class Message {
    var id: UUID
    var roleRaw: String
    var content: String
    var createdAt: Date
    var chat: Chat?
    @Relationship(deleteRule: .cascade, inverse: \Attachment.message)
    var attachments: [Attachment] = []

    init(role: MessageRole, content: String, createdAt: Date = .now) {
        self.id = UUID()
        self.roleRaw = role.rawValue
        self.content = content
        self.createdAt = createdAt
    }

    var role: MessageRole {
        get { MessageRole(rawValue: roleRaw) ?? .assistant }
        set { roleRaw = newValue.rawValue }
    }

    var sortedAttachments: [Attachment] {
        attachments.sorted { $0.createdAt < $1.createdAt }
    }
}

