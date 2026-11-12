import SwiftData
import SwiftUI

/// Persisted list of recent search terms (most recent first, deduplicated, capped).
enum RecentSearches {
    static let key = "recentSearches"
    static let limit = 8

    static func decode(_ raw: String) -> [String] {
        (try? JSONDecoder().decode([String].self, from: Data(raw.utf8))) ?? []
    }

    static func encode(_ items: [String]) -> String {
        (try? JSONEncoder().encode(items)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    static func adding(_ term: String, to items: [String]) -> [String] {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }
        let rest = items.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        return Array(([trimmed] + rest).prefix(limit))
    }
}

struct SearchView: View {
    let onSelect: (Chat) -> Void

    @Query(sort: \Chat.updatedAt, order: .reverse) private var allChats: [Chat]
    @AppStorage(RecentSearches.key) private var recentRaw = "[]"
    @State private var query = ""
    @FocusState private var focused: Bool

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var recents: [String] { RecentSearches.decode(recentRaw) }

    private var results: [Chat] {
        guard !trimmed.isEmpty else { return [] }
        return allChats.filter { chat in
            !chat.messages.isEmpty
                && (chat.title.localizedCaseInsensitiveContains(trimmed)
                    || chat.messages.contains { $0.content.localizedCaseInsensitiveContains(trimmed) })
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing3) {
            searchField
            if trimmed.isEmpty {
                recentList
            } else if results.isEmpty {
                ContentUnavailableView.search(text: trimmed)
            } else {
                List {
                    ForEach(results) { chat in
                        ChatHistoryRow(chat: chat) { select(chat) }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.spacing3)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .navigationTitle("Search")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear { focused = true }
    }

    private var searchField: some View {
        HStack(spacing: Theme.spacing2) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search chats", text: $query)
                .textFieldStyle(.plain)
                .focused($focused)
                .submitLabel(.search)
                .onSubmit(remember)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: Theme.controlHeight)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(focused ? 0.7 : 0.3), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var recentList: some View {
        if !recents.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Previous Search")
                    .font(.system(size: 16, weight: .medium))
                    .padding(.bottom, Theme.spacing2)
                Divider()
                ForEach(recents, id: \.self) { term in
                    HStack {
                        Button { query = term } label: {
                            Text(term)
                                .font(.system(size: 15))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Button { removeRecent(term) } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Remove \(term)")
                    }
                    .padding(.vertical, 14)
                }
            }
        } else {
            Text("Search your past chats by title or message.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }

    private func remember() {
        recentRaw = RecentSearches.encode(RecentSearches.adding(trimmed, to: recents))
    }

    private func removeRecent(_ term: String) {
        recentRaw = RecentSearches.encode(recents.filter { $0 != term })
    }

    private func select(_ chat: Chat) {
        remember()
        onSelect(chat)
    }
}
