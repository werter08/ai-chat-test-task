import SwiftUI

/// Speed of the typewriter reveal: proportional to the backlog (so it never lags far behind the network)
/// but never slower than one character per tick (so it always looks like typing).
enum TypewriterPacing {
    nonisolated static func step(backlog: Int) -> Int {
        max(1, Int((Double(backlog) / 12).rounded(.up)))
    }
}

private struct RevealKey: Hashable {
    let count: Int
    let streaming: Bool
}

struct TypingCursor: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(Color.accentColor)
            .frame(width: 3, height: 18)
            .phaseAnimator([1.0, 0.15]) { content, phase in
                content.opacity(phase)
            } animation: { _ in
                .easeInOut(duration: 0.5)
            }
            .accessibilityHidden(true)
    }
}

struct MessageBubble: View {
    let message: Message
    let isStreaming: Bool
    let onReveal: () -> Void
    @Environment(Toast.self) private var toast
    @State private var copied = false
    /// Characters of the reply shown so far while it is typed out; nil = show everything.
    @State private var revealed: Int?

    init(message: Message, isStreaming: Bool = false, onReveal: @escaping () -> Void = {}) {
        self.message = message
        self.isStreaming = isStreaming
        self.onReveal = onReveal
        // Only a reply that is being streamed right now is typed out; stored history appears instantly.
        _revealed = State(initialValue: isStreaming ? 0 : nil)
    }

    private var displayedText: String {
        guard let revealed else { return message.content }
        return StreamingMarkdown.closeOpenMarkers(String(message.content.prefix(revealed)))
    }

    private var isUser: Bool { message.role == .user }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: Theme.cardRadius,
                bottomLeading: isUser ? Theme.cardRadius : 4,
                bottomTrailing: isUser ? 4 : Theme.cardRadius,
                topTrailing: Theme.cardRadius
            ),
            style: .continuous
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.spacing2) {
            if isUser { Spacer(minLength: 48) }
            bubble
            if !isUser {
                VStack(spacing: 10) {
                    Button(action: copyMessage) {
                        Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                            .foregroundStyle(copied ? Color.green : .secondary)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .accessibilityLabel(copied ? "Copied" : "Copy")
                    ShareLink(item: message.content) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share")
                }
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
                .padding(.top, 6)
                .sensoryFeedback(.success, trigger: copied) { _, new in new }
            }
        }
    }

    /// Catches the displayed text up to the received text, a few characters per frame.
    private func reveal() async {
        guard var shown = revealed else { return }
        let total = message.content.count
        while shown < total, !Task.isCancelled {
            shown = min(total, shown + TypewriterPacing.step(backlog: total - shown))
            revealed = shown
            onReveal()
            try? await Task.sleep(for: .milliseconds(16))
        }
        if shown >= total, !isStreaming, !Task.isCancelled {
            revealed = nil   // finished: render the full text normally
            onReveal()
        }
    }

    private func copyMessage() {
        Clipboard.copy(message.content)
        toast.show("Copied to clipboard")
        withAnimation(.snappy) { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.snappy) { copied = false }
        }
    }

    @ViewBuilder
    private var bubble: some View {
        if isUser {
            Text(InlineMarkdown.attributed(message.content))
                .font(.system(size: 16))
                .lineSpacing(3)
                .textSelection(.enabled)
                .foregroundStyle(Color.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.accentColor, in: shape)
                .frame(maxWidth: 560, alignment: .trailing)
                .accessibilityLabel("You: \(message.content)")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                MarkdownView(text: displayedText)
                if revealed != nil { TypingCursor() }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.fill, in: shape)
            .frame(maxWidth: 680, alignment: .leading)
            .task(id: RevealKey(count: message.content.count, streaming: isStreaming)) { await reveal() }
        }
    }
}

/// Centered, display-only line such as "You stopped the response." (with Retry when it is the last item).
struct NoteRow: View {
    let text: String
    let onRetry: (() -> Void)?

    var body: some View {
        HStack(spacing: Theme.spacing2) {
            Image(systemName: "stop.circle")
            Text(text)
            if let onRetry {
                Button("Retry", action: onRetry)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .fontWeight(.semibold)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.fill, in: Capsule())
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct TypingIndicator: View {
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 8, height: 8)
                    .phaseAnimator([0.4, 1.0]) { content, phase in
                        content.opacity(phase)
                    } animation: { _ in
                        .easeInOut(duration: 0.5).delay(Double(index) * 0.15)
                    }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .accessibilityLabel("Assistant is typing")
    }
}

struct ErrorBanner: View {
    let error: ChatAPIError
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(error.title).font(.subheadline.weight(.semibold))
                Text(error.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Retry", action: onRetry)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch error {
        case .offline: "wifi.slash"
        case .timeout: "clock.badge.exclamationmark"
        case .insufficientCredits, .rateLimited: "gauge.with.dots.needle.100percent"
        default: "exclamationmark.triangle.fill"
        }
    }
}

/// "Stop generating…" pill shown above the composer while a reply streams.
struct StopPill: View {
    let onStop: () -> Void

    var body: some View {
        Button(action: onStop) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(Color.accentColor).frame(width: 12, height: 12)
                Text("Stop generating…").font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, Theme.spacing3)
            .padding(.vertical, 10)
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stop generating")
    }
}

struct ModeCard: View {
    let mode: ChatMode
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Theme.spacing2) {
                HStack(spacing: 8) {
                    Image(systemName: mode.symbol)
                        .foregroundStyle(isSelected ? Color.accentColor : .primary)
                    Text(mode.title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(isSelected ? Color.accentColor : .primary)
                }
                Text(mode.blurb)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(mode.cta)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(Theme.spacing3)
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
            .background(
                isSelected ? Color.accentColor.opacity(0.10) : Theme.fill,
                in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.6) : Theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(mode.title). \(mode.blurb) \(mode.cta)")
    }
}

/// Empty chat content: greeting + mode cards (general), or the selected mode's intro + quick prompts.
struct EmptyChatContent: View {
    let mode: ChatMode?
    let userName: String
    let onSelectMode: (ChatMode) -> Void
    let onClearMode: () -> Void
    let onPrompt: (String) -> Void

    private var greeting: String {
        let name = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Hey there 👋" : "Hey \(name) 👋"
    }

    var body: some View {
        ScrollView {
            if let mode {
                modeIntro(mode)
            } else {
                general
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var general: some View {
        VStack(spacing: Theme.spacing4) {
            VStack(spacing: Theme.spacing2) {
                Text(greeting)
                    .font(.display(32))
                Text("What would you like to do today?")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(.top, Theme.spacing4)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: Theme.spacing2)], spacing: Theme.spacing2) {
                ForEach(ChatMode.allCases) { mode in
                    ModeCard(mode: mode, isSelected: false) { onSelectMode(mode) }
                }
            }
        }
        .padding(.horizontal, Theme.spacing3)
        .padding(.bottom, Theme.spacing3)
    }

    private func modeIntro(_ mode: ChatMode) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing3) {
            Button(action: onClearMode) {
                HStack(spacing: 6) {
                    Text(mode.title)
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.accentColor, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(mode.title) mode. Tap to leave this mode")

            VStack(spacing: Theme.spacing2) {
                Text(mode.introTitle).font(.system(size: 18, weight: .semibold, design: .rounded))
                Text(mode.intro)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)

            Text("🎯 Quick Prompts")
                .font(.system(size: 15, weight: .semibold))
                .padding(.top, Theme.spacing2)
            VStack(spacing: Theme.spacing2) {
                ForEach(mode.quickPrompts, id: \.self) { prompt in
                    Button { onPrompt(prompt) } label: {
                        HStack(spacing: Theme.spacing2) {
                            Text(prompt)
                                .font(.system(size: 15, weight: .medium))
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                                .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, Theme.spacing3)
        .padding(.bottom, Theme.spacing3)
    }
}

/// How much room the message editor takes: one line (grows to 6), 30% of the screen, or the whole screen.
enum ComposerSize {
    case compact, third, full

    var next: ComposerSize {
        switch self {
        case .compact: .third
        case .third: .full
        case .full: .compact
        }
    }
}

/// Composer from the design kit: rounded input + red rounded-square send/stop button.
/// While focused the field glows; the corner button cycles compact → 30% → full screen → compact.
struct ComposerView: View {
    @Binding var text: String
    @Binding var size: ComposerSize
    let isGenerating: Bool
    let availableHeight: CGFloat
    let onSend: () -> Void
    let onStop: () -> Void

    @FocusState private var focused: Bool

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
    }

    var body: some View {
        // Compact: field and send button side by side. Expanded (30% / full): editor on top, full-width send below.
        Group {
            if size == .compact {
                HStack(alignment: .bottom, spacing: Theme.spacing2) {
                    field
                    sendButton(wide: false)
                }
            } else {
                VStack(spacing: Theme.spacing2) {
                    field
                    sendButton(wide: true)
                }
            }
        }
        .padding(.horizontal, Theme.spacing3)
        .padding(.vertical, Theme.spacing2)
        .frame(maxHeight: size == .full ? .infinity : nil, alignment: .bottom)
        .background {
            // Full-screen compose blends with the page; otherwise the composer sits on a bar material.
            if size == .full { Color.clear } else { Rectangle().fill(.bar).ignoresSafeArea(edges: .bottom) }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: size)
    }

    // MARK: Field

    private var field: some View {
        ZStack(alignment: .topTrailing) {
            if size == .compact {
                TextField("Ask me anything…", text: $text, axis: .vertical)
                    .lineLimit(1...6)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .padding(.leading, 14)
                    .padding(.trailing, 44)
                    .frame(minHeight: Theme.controlHeight)
                    .focused($focused)
                    .onSubmit { if canSend && !isGenerating { onSend() } }
            } else {
                editor
            }
            sizeButton
        }
        .frame(maxHeight: size == .full ? .infinity : nil)
        .background(focused ? Color.accentColor.opacity(0.06) : Theme.fill, in: shape)
        .overlay(shape.strokeBorder(focused ? Color.accentColor : Theme.border, lineWidth: focused ? 2 : 1))
        .shadow(color: Color.accentColor.opacity(focused ? 0.35 : 0), radius: focused ? 10 : 0)
        .animation(.easeInOut(duration: 0.2), value: focused)
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("Ask me anything…")
                    .font(.system(size: 16))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(.system(size: 16))
                .scrollContentBackground(.hidden)
                .focused($focused)
        }
        .padding(.leading, 9)
        .padding(.trailing, 44)
        .padding(.vertical, 6)
        .frame(height: size == .third ? max(120, availableHeight * 0.3) : nil)
        .frame(maxHeight: size == .full ? .infinity : nil)
    }

    private var sizeButton: some View {
        Button(action: cycleSize) {
            Image(systemName: size == .full ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(focused ? Color.accentColor : .secondary)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 7)
        .padding(.trailing, 4)
        .accessibilityLabel(size == .full ? "Collapse input" : "Expand input")
    }

    private func cycleSize() {
        size = size.next
        // The text view is replaced when switching between compact and expanded: give focus back.
        Task {
            try? await Task.sleep(for: .milliseconds(60))
            focused = true
        }
    }

    // MARK: Send / stop

    private func sendButton(wide: Bool) -> some View {
        Button(action: isGenerating ? onStop : onSend) {
            HStack(spacing: Theme.spacing2) {
                Image(systemName: isGenerating ? "stop.fill" : "paperplane.fill")
                    .font(.system(size: 18, weight: .semibold))
                if wide {
                    Text(isGenerating ? "Stop" : "Send")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: wide ? .infinity : Theme.controlHeight)
            .frame(width: wide ? nil : Theme.controlHeight, height: Theme.controlHeight)
            .background(
                Color.accentColor.opacity(isGenerating || canSend ? 1 : 0.4),
                in: shape
            )
        }
        .buttonStyle(.plain)
        .disabled(!isGenerating && !canSend)
        .accessibilityLabel(isGenerating ? "Stop generating" : "Send message")
    }
}
