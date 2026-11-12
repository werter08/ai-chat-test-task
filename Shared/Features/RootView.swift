import SwiftData
import SwiftUI

enum Route: Hashable {
    case settings
}

/// Launches straight into an empty chat. The menu icon (or an edge swipe) opens a push-style drawer
/// (history + new chat); Settings is a regular pushed page.
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Chat.updatedAt, order: .reverse) private var chats: [Chat]
    @State private var currentID: UUID?
    @State private var path: [Route] = []
    @State private var showSidebar = false
    @AppStorage("didSeeOnboarding") private var didSeeOnboarding = false
    @AppStorage(AppearanceOption.key) private var appearance = AppearanceOption.system.rawValue

    /// Looked up by id so a deleted chat can never be dereferenced.
    private var current: Chat? { chats.first { $0.id == currentID } }

    var body: some View {
        Group {
            if didSeeOnboarding {
                DrawerContainer(isOpen: $showSidebar, swipeEnabled: path.isEmpty) {
                    SidebarView(
                        currentID: currentID,
                        onSelect: { chat in
                            currentID = chat.id
                            path = []
                            setSidebar(false)
                        },
                        onNewChat: {
                            path = []
                            startNewChat()
                            setSidebar(false)
                        },
                        onSettings: {
                            setSidebar(false)
                            path.append(.settings)
                        },
                        onClose: { setSidebar(false) }
                    )
                } content: {
                    NavigationStack(path: $path) {
                        Group {
                            if let current {
                                ChatScreen(
                                    chat: current,
                                    onMenu: { setSidebar(true) },
                                    onNewChat: startNewChat
                                )
                                .id(current.id)
                            } else {
                                Color.clear
                            }
                        }
                        .navigationDestination(for: Route.self) { route in
                            switch route {
                            case .settings: SettingsView()
                            }
                        }
                    }
                }
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

    // MARK: Sidebar

    private func setSidebar(_ visible: Bool) {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { showSidebar = visible }
    }

    // MARK: Current chat

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
