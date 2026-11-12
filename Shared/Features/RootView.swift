import SwiftData
import SwiftUI

enum Route: Hashable {
    case settings
}

/// Launches straight into an empty chat. The menu icon opens a full-screen sidebar (history + new chat);
/// Settings is a regular pushed page.
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
                ZStack {
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

                    if showSidebar { sidebar }
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

    /// Full width on phones; a 380pt panel with a dimmed backdrop on wide screens (iPad / Mac).
    private var sidebar: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 600
            HStack(spacing: 0) {
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
                .frame(width: wide ? 380 : geo.size.width)
                if wide {
                    Color.black.opacity(0.25)
                        .onTapGesture { setSidebar(false) }
                }
            }
        }
        .transition(.move(edge: .leading))
        .zIndex(1)
    }

    private func setSidebar(_ visible: Bool) {
        withAnimation(.easeInOut(duration: 0.25)) { showSidebar = visible }
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
