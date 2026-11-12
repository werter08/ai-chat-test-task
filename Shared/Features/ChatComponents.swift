import SwiftUI

struct MessageBubble: View {
    let message: Message

    private var isUser: Bool { message.role == .user }

    private var rendered: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: message.content, options: options)) ?? AttributedString(message.content)
    }

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
            Text(rendered)
                .font(.system(size: 16))
                .lineSpacing(3)
                .textSelection(.enabled)
                .foregroundStyle(isUser ? Color.white : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isUser ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Theme.fill), in: shape)
                .accessibilityLabel("\(isUser ? "You" : "Assistant"): \(message.content)")
            if !isUser {
                VStack(spacing: 10) {
                    Button { Clipboard.copy(message.content) } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .accessibilityLabel("Copy")
                    ShareLink(item: message.content) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share")
                }
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
                .padding(.top, 6)
                Spacer(minLength: 24)
            }
        }
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

/// Mode chips under the header (Writing / Creative / …). Tapping the selected chip returns to general chat.
struct ModeChips: View {
    let selected: ChatMode?
    let onSelect: (ChatMode) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.spacing2) {
                ForEach(ChatMode.allCases) { mode in
                    let isSelected = mode == selected
                    Button { onSelect(mode) } label: {
                        Text(mode.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.7))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                isSelected ? Color.accentColor : Theme.fill,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, Theme.spacing3)
        }
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
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1)
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
                Text("Explore what I can help with")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .padding(.top, Theme.spacing1)
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
            VStack(spacing: Theme.spacing2) {
                Text(mode.introTitle).font(.system(size: 18, weight: .semibold, design: .rounded))
                Text(mode.intro)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, Theme.spacing3)

            Text("🎯 Quick Prompt")
                .font(.system(size: 15, weight: .semibold))
                .padding(.top, Theme.spacing3)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(mode.quickPrompts, id: \.self) { prompt in
                    Button { onPrompt(prompt) } label: {
                        Text("•  \(prompt) →")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.accentColor)
                            .multilineTextAlignment(.leading)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, Theme.spacing3)
    }
}

/// Composer from the design kit: rounded input + red rounded-square send/stop button.
struct ComposerView: View {
    @Binding var text: String
    let isGenerating: Bool
    let onSend: () -> Void
    let onStop: () -> Void

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: Theme.spacing2) {
            TextField("Ask me anything…", text: $text, axis: .vertical)
                .lineLimit(1...6)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .padding(.horizontal, 14)
                .frame(minHeight: Theme.controlHeight)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1)
                )
                .onSubmit { if canSend && !isGenerating { onSend() } }

            Button(action: isGenerating ? onStop : onSend) {
                Image(systemName: isGenerating ? "stop.fill" : "paperplane.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: Theme.controlHeight, height: Theme.controlHeight)
                    .background(
                        Color.accentColor.opacity(isGenerating || canSend ? 1 : 0.4),
                        in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!isGenerating && !canSend)
            .accessibilityLabel(isGenerating ? "Stop generating" : "Send message")
        }
        .padding(.horizontal, Theme.spacing3)
        .padding(.vertical, Theme.spacing2)
        .background(.bar)
    }
}
