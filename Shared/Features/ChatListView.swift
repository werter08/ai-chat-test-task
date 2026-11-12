import SwiftData
import SwiftUI

struct ChatListView: View {
    @Binding var selection: Chat?
    @Environment(\.modelContext) private var context
    @Environment(ChatEngine.self) private var engine
    @Query(sort: \Chat.updatedAt, order: .reverse) private var chats: [Chat]

    var body: some View {
        List(selection: $selection) {
            ForEach(chats) { chat in
                ChatRow(chat: chat)
                    .tag(chat)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { delete(chat) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button(role: .destructive) { delete(chat) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .overlay {
            if chats.isEmpty {
                ContentUnavailableView {
                    Label("No chats yet", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("Start a conversation with the assistant.")
                } actions: {
                    Button("New chat", action: newChat)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Chats")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: newChat) {
                    Label("New chat", systemImage: "square.and.pencil")
                }
            }
        }
    }

    private func newChat() {
        // Reuse an existing empty chat instead of piling up blank ones.
        if let empty = chats.first(where: { $0.messages.isEmpty }) {
            selection = empty
            return
        }
        let chat = Chat()
        context.insert(chat)
        try? context.save()
        selection = chat
    }

    private func delete(_ chat: Chat) {
        if selection == chat { selection = nil }
        engine.discard(chat)
        context.delete(chat)
        try? context.save()
    }
}

private struct ChatRow: View {
    let chat: Chat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(chat.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(chat.updatedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(chat.lastMessage?.content ?? "No messages yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }
}
