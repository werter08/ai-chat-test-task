import SwiftData
import SwiftUI

/// Past chats (clock icon). Empty chats are hidden.
struct HistoryView: View {
    let onSelect: (Chat) -> Void
    let onNewChat: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(ChatEngine.self) private var engine
    @Query(sort: \Chat.updatedAt, order: .reverse) private var allChats: [Chat]
    @State private var confirmClear = false

    private var chats: [Chat] { allChats.filter { !$0.messages.isEmpty } }

    var body: some View {
        Group {
            if chats.isEmpty {
                blankCanvas
            } else {
                List {
                    ForEach(chats) { chat in
                        ChatHistoryRow(chat: chat) { onSelect(chat) }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { delete(chat) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("History")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                NavigationLink(value: Route.search) {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("Search")
                if !chats.isEmpty {
                    Button { confirmClear = true } label: { Image(systemName: "trash") }
                        .accessibilityLabel("Delete all chats")
                }
            }
        }
        .confirmationDialog("Delete all chats?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Delete all", role: .destructive) { ChatStore.deleteAll(allChats, engine: engine, context: context) }
        } message: {
            Text("This can't be undone.")
        }
    }

    private var blankCanvas: some View {
        VStack(spacing: Theme.spacing3) {
            Image(systemName: "text.bubble")
                .font(.system(size: 72))
                .foregroundStyle(Color.accentColor.opacity(0.7))
            Text("Your canvas is blank 🖋️")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
            Text("No past chats, no worries.\nEvery idea starts somewhere — ask me anything.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Ask your first question", action: onNewChat)
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, Theme.spacing2)
        }
        .padding(Theme.spacing4)
        .frame(maxWidth: 420, maxHeight: .infinity)
        .frame(maxWidth: .infinity)
    }

    private func delete(_ chat: Chat) {
        engine.discard(chat)
        context.delete(chat)
        try? context.save()
    }
}

struct ChatHistoryRow: View {
    let chat: Chat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(chat.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(chat.updatedAt, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

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
