import Foundation
import SwiftData

enum MessageRole: String, Codable {
    case user
    case assistant
}

@Model
final class Message {
    var id: UUID
    var roleRaw: String
    var content: String
    var createdAt: Date
    var chat: Chat?

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
}
