import SwiftUI

/// First-launch intro (3 pages, Skip / Next), shown once. Layout follows the design kit.
struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var page = 0

    private struct Page {
        let symbol: String
        let title: String
        let text: String
    }

    private let pages = [
        Page(symbol: "bubble.left.and.text.bubble.right.fill",
             title: "Meet Your Smarter Assistant",
             text: "Chat with your AI companion — designed to help you think, plan, create, and explore faster than ever."),
        Page(symbol: "sparkles",
             title: "Answers, Ideas & Support",
             text: "From quick facts to deep conversations, ask about any topic and watch the reply appear as it is written."),
        Page(symbol: "lock.shield.fill",
             title: "Your Chats Stay With You",
             text: "Conversations are saved on this device. Messages are sent to the AI provider only to generate a reply."),
    ]

    private var isLast: Bool { page == pages.count - 1 }

    var body: some View {
        VStack(spacing: Theme.spacing4) {
            Spacer(minLength: 0)

            ZStack {
                Circle().fill(Color.accentColor.opacity(0.10))
                Image(systemName: pages[page].symbol)
                    .font(.system(size: 84, weight: .regular))
                    .foregroundStyle(Color.accentColor)
                    .symbolRenderingMode(.hierarchical)
                    .id(page)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
            .frame(width: 220, height: 220)
            .accessibilityHidden(true)

            VStack(spacing: Theme.spacing2) {
                Text(pages[page].title)
                    .font(.display(30))
                    .multilineTextAlignment(.center)
                Text(pages[page].text)
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .id(page)
            .transition(.opacity)
            .padding(.horizontal, Theme.spacing3)

            HStack(spacing: 6) {
                ForEach(pages.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? Color.accentColor : Color.accentColor.opacity(0.18))
                        .frame(width: index == page ? 24 : 8, height: 8)
                }
            }
            .accessibilityHidden(true)

            Spacer(minLength: 0)

            HStack(spacing: Theme.spacing2) {
                if !isLast {
                    Button("Skip", action: onFinish)
                        .buttonStyle(PrimaryButtonStyle(tinted: true))
                }
                Button(isLast ? "Get Started" : "Next") {
                    if isLast { onFinish() } else { withAnimation(.easeInOut(duration: 0.3)) { page += 1 } }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(Theme.spacing3)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.accentColor.opacity(0.0001)) // keeps full-area hit testing
    }
}
