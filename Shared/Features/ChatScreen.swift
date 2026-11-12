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
    @Environment(SpeechInput.self) private var speech
    @AppStorage(UserProfile.nameKey) private var userName = ""
    @State private var draft = ""
    /// Photos picked for the message being written (shown above the text box).
    @State private var draftImages: [DraftImage] = ChatScreen.initialImages()
    @State private var composerSize: ComposerSize = .compact
    /// True when part of the conversation is below the visible area.
    @State private var hasMoreBelow = false
    /// Drives programmatic scrolling (iOS 18 API): jump to the bottom, or bring a sent message to the top.
    @State private var scrollPosition = ScrollPosition(edge: .bottom)

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
                    images: $draftImages,
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
        .onDisappear { speech.stop() }
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
    ///
    /// Scrolling rules: a reopened chat starts at its newest message; when you send, your message is scrolled to
    /// the top once and the reply grows beneath it — nothing follows the text while it is written, so you can read
    /// from the top. When the reply is ready, a "Go down" bubble appears if part of it is below the fold.
    private func conversation(messages: [Message], state: ChatEngine.State) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(messages) { message in
                    Group {
                        if message.role == .note {
                            NoteRow(
                                text: message.content,
                                onRetry: message.id == messages.last?.id && !state.isGenerating
                                    ? { engine.retry(chat, context: context) } : nil
                            )
                        } else {
                            MessageBubble(
                                message: message,
                                isStreaming: state.isGenerating && message.id == messages.last?.id
                            )
                        }
                    }
                    .id(message.id)
                }
                if state.isGenerating && messages.last?.role != .assistant {
                    TypingIndicator()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, Theme.spacing3)
            .padding(.vertical, 12)
        }
        .scrollPosition($scrollPosition)
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .scrollDismissesKeyboard(.interactively)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.visibleRect.maxY < geometry.contentSize.height - 80
        } action: { _, moreBelow in
            hasMoreBelow = moreBelow
        }
        .onChange(of: messages.count) {
            guard let last = messages.last, last.role == .user else { return }
            let id = last.id
            Task { @MainActor in
                await Task.yield()
                withAnimation(.easeInOut(duration: 0.35)) { scrollPosition.scrollTo(id: id, anchor: .top) }
            }
        }
        .overlay(alignment: .bottom) {
            if hasMoreBelow && !state.isGenerating {
                GoDownButton { scrollToBottom() }
                    .padding(.bottom, Theme.spacing3)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: hasMoreBelow && !state.isGenerating)
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
        speech.stop()
        engine.send(text, images: draftImages.map(\.jpeg), in: chat, context: context)
        draft = ""
        draftImages = []
        composerSize = .compact
    }

    private static func initialImages() -> [DraftImage] {
        #if DEBUG
        if CommandLine.arguments.contains("-uiTestSeedPhoto") { return [DraftImage(jpeg: DemoData.samplePhotoJPEG())] }
        #endif
        return []
    }

    private func scrollToBottom() {
        withAnimation(.easeInOut(duration: 0.5)) { scrollPosition.scrollTo(edge: .bottom) }
    }
}
