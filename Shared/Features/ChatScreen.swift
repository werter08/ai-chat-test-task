import SwiftData
import SwiftUI

/// The main screen: header, conversation (or empty state) and the composer.
struct ChatScreen: View {
    let chat: Chat
    let onMenu: () -> Void
    let onNewChat: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(ChatEngine.self) private var engine
    @Environment(Toast.self) private var toast
    @AppStorage(UserProfile.nameKey) private var userName = ""
    @State private var draft = ""
    @State private var composerSize: ComposerSize = .compact

    private static let bottomID = "bottom"

    var body: some View {
        GeometryReader { geo in
            let state = engine.state(for: chat)
            let messages = chat.sortedMessages
            let showEmpty = messages.isEmpty && !state.isGenerating

            VStack(spacing: 0) {
                header

                // In full-screen compose mode the conversation is hidden so the editor gets the whole screen.
                if composerSize != .full {
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
                }

                ComposerView(
                    text: $draft,
                    size: $composerSize,
                    isGenerating: state.isGenerating,
                    availableHeight: geo.size.height,
                    onSend: { send(draft) },
                    onStop: { engine.stop(chat) }
                )
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .overlay(alignment: .top) {
            if let message = toast.message {
                ToastView(text: message)
                    .padding(.top, 64)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
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

    /// Not lazy on purpose: a lazy stack + "scroll to bottom on appear" left reopened chats blank until dragged.
    /// `defaultScrollAnchor(.bottom)` makes every chat open at its newest message.
    private func conversation(messages: [Message], state: ChatEngine.State) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(messages) { message in
                        if message.role == .note {
                            NoteRow(
                                text: message.content,
                                onRetry: message.id == messages.last?.id && !state.isGenerating
                                    ? { engine.retry(chat, context: context) } : nil
                            )
                        } else {
                            MessageBubble(
                                message: message,
                                isStreaming: state.isGenerating && message.id == messages.last?.id,
                                onReveal: { scrollToBottom(proxy, animated: false) }
                            )
                        }
                    }
                    if state.isGenerating && messages.last?.role != .assistant {
                        TypingIndicator()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Color.clear.frame(height: 1).id(Self.bottomID)
                }
                .padding(.horizontal, Theme.spacing3)
                .padding(.vertical, 12)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { scrollToBottom(proxy, animated: true) }
            .onChange(of: messages.last?.content) { scrollToBottom(proxy, animated: false) }
            .onChange(of: state.isGenerating) { scrollToBottom(proxy, animated: true) }
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
        composerSize = .compact
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
        } else {
            proxy.scrollTo(Self.bottomID, anchor: .bottom)
        }
    }
}
