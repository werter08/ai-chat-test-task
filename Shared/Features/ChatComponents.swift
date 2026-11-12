import SwiftUI

struct MessageBubble: View {
    let message: Message

    private var isUser: Bool { message.role == .user }

    private var rendered: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: message.content, options: options)) ?? AttributedString(message.content)
    }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 48) }
            Text(rendered)
                .font(.system(size: 16))
                .lineSpacing(3)
                .textSelection(.enabled)
                .foregroundStyle(isUser ? Color.white : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    isUser ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Theme.fill),
                    in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                )
                .frame(maxWidth: 560, alignment: isUser ? .trailing : .leading)
                .accessibilityLabel("\(isUser ? "You" : "Assistant"): \(message.content)")
            if !isUser { Spacer(minLength: 48) }
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

/// Empty chat: greeting layout from the design kit, plus tappable starter prompts.
struct EmptyChatView: View {
    let onPick: (String) -> Void

    private let suggestions = [
        "Explain how HTTPS works in simple words",
        "Write a short poem about autumn",
        "Give me 3 ideas for a weekend project",
    ]

    var body: some View {
        VStack(spacing: Theme.spacing3) {
            VStack(spacing: Theme.spacing2) {
                Text("Hey there 👋")
                    .font(.display(32))
                Text("I'm your AI buddy — ready to chat, answer, and assist.")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("Just say the word.")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.top, Theme.spacing1)
            }
            VStack(spacing: Theme.spacing2) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button(suggestion) { onPick(suggestion) }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, Theme.spacing3)
                        .padding(.vertical, 10)
                        .background(Color.accentColor.opacity(0.10), in: Capsule())
                        .buttonStyle(.plain)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.top, Theme.spacing2)
        }
        .padding(Theme.spacing3)
        .frame(maxWidth: 480)
    }
}

/// Composer from the design kit: rounded input ("Ask anything") + red rounded-square send button.
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
            TextField("Ask anything", text: $text, axis: .vertical)
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
