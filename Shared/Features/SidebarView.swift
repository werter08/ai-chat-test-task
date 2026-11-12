import SwiftData
import SwiftUI

/// Full-screen side panel: search, "New chat" button and the list of past chats. Settings lives in the footer.
struct SidebarView: View {
    let currentID: UUID?
    let onSelect: (Chat) -> Void
    let onNewChat: () -> Void
    let onSettings: () -> Void
    let onClose: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(ChatEngine.self) private var engine
    @Query(sort: \Chat.updatedAt, order: .reverse) private var allChats: [Chat]
    @AppStorage(UserProfile.nameKey) private var userName = ""
    @State private var query = ""

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var chats: [Chat] {
        allChats.filter { chat in
            guard !chat.messages.isEmpty else { return false }
            guard !trimmed.isEmpty else { return true }
            return chat.title.localizedCaseInsensitiveContains(trimmed)
                || chat.messages.contains { $0.content.localizedCaseInsensitiveContains(trimmed) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            searchField
                .padding(.horizontal, Theme.spacing3)
            Button(action: onNewChat) {
                Label("New chat", systemImage: "square.and.pencil")
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, Theme.spacing3)
            .padding(.vertical, Theme.spacing3)

            content
            Divider()
            footer
        }
        .background { Rectangle().fill(.background).ignoresSafeArea() }
    }

    private var topBar: some View {
        HStack {
            Text(Brand.name)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.accentColor)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.8))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, Theme.spacing3)
        .frame(height: 56)
    }

    private var searchField: some View {
        HStack(spacing: Theme.spacing2) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search chats", text: $query)
                .textFieldStyle(.plain)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: Theme.controlHeight)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var content: some View {
        if chats.isEmpty {
            Group {
                if trimmed.isEmpty {
                    VStack(spacing: Theme.spacing2) {
                        Image(systemName: "text.bubble")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.accentColor.opacity(0.7))
                        Text("No chats yet")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                        Text("Your conversations will show up here.")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ContentUnavailableView.search(text: trimmed)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                Section {
                    ForEach(chats) { chat in
                        ChatHistoryRow(chat: chat, isCurrent: chat.id == currentID) { onSelect(chat) }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: Theme.spacing3, bottom: 4, trailing: Theme.spacing3))
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { delete(chat) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                } header: {
                    Text("Recent")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.plain)
        }
    }

    private var footer: some View {
        Button(action: onSettings) {
            HStack(spacing: Theme.spacing3) {
                Image(systemName: "gearshape")
                    .font(.system(size: 20))
                Text(userName.trimmingCharacters(in: .whitespaces).isEmpty ? "Settings" : "\(userName) · Settings")
                    .font(.system(size: 16, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, Theme.spacing3)
            .frame(height: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sidebar.settings")
    }

    private func delete(_ chat: Chat) {
        engine.discard(chat)
        context.delete(chat)
        try? context.save()
    }
}

struct ChatHistoryRow: View {
    let chat: Chat
    var isCurrent = false
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
            .background(
                isCurrent ? Color.accentColor.opacity(0.10) : Theme.fill,
                in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .strokeBorder(isCurrent ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
