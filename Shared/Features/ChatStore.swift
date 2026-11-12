import SwiftData

enum ChatStore {
    @MainActor
    static func deleteAll(_ chats: [Chat], engine: ChatEngine, context: ModelContext) {
        for chat in chats {
            engine.discard(chat)
            context.delete(chat)
        }
        try? context.save()
    }
}
