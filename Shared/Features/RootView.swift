import SwiftData
import SwiftUI

enum Route: Hashable {
    case history
    case search
}

/// Launches straight into an empty chat. History, search and settings hang off the header icons.
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Chat.updatedAt, order: .reverse) private var chats: [Chat]
    @State private var currentID: UUID?
    @State private var path: [Route] = []
    @State private var showSettings = false
    @AppStorage("didSeeOnboarding") private var didSeeOnboarding = false
    @AppStorage(AppearanceOption.key) private var appearance = AppearanceOption.system.rawValue

    /// Looked up by id so a deleted chat can never be dereferenced.
    private var current: Chat? { chats.first { $0.id == currentID } }

    var body: some View {
        Group {
            if didSeeOnboarding {
                NavigationStack(path: $path) {
                    Group {
                        if let current {
                            ChatScreen(
                                chat: current,
                                onMenu: { showSettings = true },
                                onHistory: { path.append(.history) },
                                onNewChat: startNewChat
                            )
                            .id(current.id)
                        } else {
                            Color.clear
                        }
                    }
                    .navigationDestination(for: Route.self) { route in
                        switch route {
                        case .history: HistoryView(onSelect: open, onNewChat: { path = []; startNewChat() })
                        case .search: SearchView(onSelect: open)
                        }
                    }
                }
                .sheet(isPresented: $showSettings) { SettingsView() }
                .onAppear(perform: ensureCurrent)
                .onChange(of: chats.map(\.id)) { ensureCurrent() }
            } else {
                OnboardingView {
                    withAnimation { didSeeOnboarding = true }
                }
            }
        }
        .preferredColorScheme(AppearanceOption(rawValue: appearance)?.colorScheme)
    }

    // MARK: Current chat

    private func open(_ chat: Chat) {
        currentID = chat.id
        path = []
    }

    /// Keeps `currentID` pointing at a live chat; falls back to a fresh empty one.
    private func ensureCurrent() {
        if current == nil { startNewChat() }
    }

    private func startNewChat() {
        // Reuse an existing empty chat instead of piling up blank ones.
        if let empty = chats.first(where: { $0.messages.isEmpty }) {
            currentID = empty.id
            return
        }
        let chat = Chat()
        context.insert(chat)
        try? context.save()
        currentID = chat.id
    }
}

enum AppearanceOption: Int, CaseIterable, Identifiable {
    static let key = "appearance"
    case system, light, dark

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
