import SwiftData
import SwiftUI

/// The main screen: header, mode chips, conversation (or empty state) and composer.
struct ChatScreen: View {
    let chat: Chat
    let onMenu: () -> Void
    let onNewChat: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(ChatEngine.self) private var engine
    @AppStorage(UserProfile.nameKey) private var userName = ""
    @State private var draft = ""

    private static let bottomID = "bottom"

    var body: some View {
        let state = engine.state(for: chat)
        let messages = chat.sortedMessages
        let showEmpty = messages.isEmpty && !state.isGenerating

        VStack(spacing: 0) {
            header

            if showEmpty {
                EmptyChatContent(
                    mode: chat.mode,
                    userName: userName,
                    onSelectMode: setMode,
                    onClearMode: { setMode(nil) },
                    onPrompt: send
                )
            } else {
                conversation(messages: messages, state: state)
            }

            if let error = bannerError(state: state) {
                ErrorBanner(error: error) { engine.retry(chat, context: context) }
                    .padding(.horizontal, Theme.spacing3)
                    .padding(.bottom, Theme.spacing2)
            }

            if state.isGenerating {
                StopPill { engine.stop(chat) }
                    .padding(.bottom, Theme.spacing2)
            }

            ComposerView(
                text: $draft,
                isGenerating: state.isGenerating,
                onSend: { send(draft) },
                onStop: { engine.stop(chat) }
            )
        }
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }

    // MARK: Header

    private var header: some View {
        ZStack {
            Text(Brand.name)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.accentColor)
            HStack(spacing: Theme.spacing1) {
                iconButton("line.3.horizontal", label: "Menu", action: onMenu)
                Spacer()
                iconButton("square.and.pencil", label: "New chat", action: onNewChat)
            }
        }
        .padding(.horizontal, Theme.spacing2)
        .frame(height: 56)
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(.primary.opacity(0.8))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: Conversation

    private func conversation(messages: [Message], state: ChatEngine.State) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(messages) { message in
                        MessageBubble(message: message)
                    }
                    if state.isGenerating && messages.last?.role == .user {
                        TypingIndicator()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Color.clear.frame(height: 1).id(Self.bottomID)
                }
                .padding(.horizontal, Theme.spacing3)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { scrollToBottom(proxy, animated: true) }
            .onChange(of: messages.last?.content) { scrollToBottom(proxy, animated: false) }
            .onChange(of: state.isGenerating) { scrollToBottom(proxy, animated: true) }
            .onAppear { scrollToBottom(proxy, animated: false) }
        }
    }

    // MARK: Actions

    /// Either the engine's last failure, or — after an app restart — a trailing unanswered user message.
    private func bannerError(state: ChatEngine.State) -> ChatAPIError? {
        if let error = state.error { return error }
        if !state.isGenerating, chat.lastMessage?.role == .user { return .noResponse }
        return nil
    }

    private func setMode(_ mode: ChatMode?) {
        chat.mode = mode
        try? context.save()
    }

    private func send(_ text: String) {
        engine.send(text, in: chat, context: context)
        draft = ""
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
        } else {
            proxy.scrollTo(Self.bottomID, anchor: .bottom)
        }
    }
}
