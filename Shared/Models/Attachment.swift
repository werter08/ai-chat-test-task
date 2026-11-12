import Foundation
import SwiftData

/// A photo attached to a user message. Stored as a downscaled JPEG, outside the main database file.
@Model
final class Attachment {
    var id: UUID
    @Attribute(.externalStorage) var data: Data
    var createdAt: Date
    var message: Message?

    init(data: Data, createdAt: Date = .now) {
        self.id = UUID()
        self.data = data
        self.createdAt = createdAt
    }
}
