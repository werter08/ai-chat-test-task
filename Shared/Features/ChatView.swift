import SwiftData
import SwiftUI

struct ChatView: View {
    let chat: Chat
    @Environment(\.modelContext) private var context
    @Environment(ChatEngine.self) private var engine
    @State private var draft = ""

    private static let bottomID = "bottom"

    var body: some View {
        let state = engine.state(for: chat)
        let messages = chat.sortedMessages

        VStack(spacing: 0) {
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
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                }
                .scrollDismissesKeyboard(.interactively)
                .overlay {
                    if messages.isEmpty && !state.isGenerating {
                        EmptyChatView(onPick: send)
                    }
                }
                .onChange(of: messages.count) { scrollToBottom(proxy, animated: true) }
                .onChange(of: messages.last?.content) { scrollToBottom(proxy, animated: false) }
                .onChange(of: state.isGenerating) { scrollToBottom(proxy, animated: true) }
                .onAppear { scrollToBottom(proxy, animated: false) }
            }

            if let error = bannerError(state: state) {
                ErrorBanner(error: error) {
                    engine.retry(chat, context: context)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            ComposerView(
                text: $draft,
                isGenerating: state.isGenerating,
                onSend: { send(draft) },
                onStop: { engine.stop(chat) }
            )
        }
        .navigationTitle(chat.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    /// Either the engine's last failure, or — after an app restart — a trailing unanswered user message.
    private func bannerError(state: ChatEngine.State) -> ChatAPIError? {
        if let error = state.error { return error }
        if !state.isGenerating, chat.lastMessage?.role == .user { return .noResponse }
        return nil
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
