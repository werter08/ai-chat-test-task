import SwiftData
import SwiftUI

/// Settings page (pushed from the sidebar footer) in the app's own card-based style.
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(ChatEngine.self) private var engine
    @Query private var chats: [Chat]

    @AppStorage(UserProfile.nameKey) private var name = ""
    @AppStorage(UserProfile.instructionsKey) private var instructions = ""
    @AppStorage(AppearanceOption.key) private var appearance = AppearanceOption.system.rawValue
    @State private var confirmDelete = false

    private var initial: String {
        name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing4) {
                profileCard
                section("Personalization") { instructionsCard }
                section("Appearance") { appearancePicker }
                section("About") { aboutCard }
                deleteButton
            }
            .padding(Theme.spacing3)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background { Rectangle().fill(.background).ignoresSafeArea() }
        .navigationTitle("Settings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .confirmationDialog("Delete all chats?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete all", role: .destructive) { ChatStore.deleteAll(chats, engine: engine, context: context) }
        } message: {
            Text("This can't be undone.")
        }
    }

    // MARK: Profile

    private var profileCard: some View {
        HStack(spacing: Theme.spacing3) {
            Text(initial)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 68, height: 68)
                .background(
                    LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.65)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    in: Circle()
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                TextField("Your name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Text("Used in greetings and shared with the AI as context.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Theme.spacing3)
        .card()
    }

    // MARK: Personalization

    private var instructionsCard: some View {
        VStack(alignment: .trailing, spacing: Theme.spacing2) {
            ZStack(alignment: .topLeading) {
                if instructions.isEmpty {
                    Text("e.g. Answer briefly. I'm an iOS developer. Reply in English.")
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $instructions)
                    .font(.system(size: 15))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 100)
                    .onChange(of: instructions) {
                        if instructions.count > UserProfile.maxInstructionsLength {
                            instructions = String(instructions.prefix(UserProfile.maxInstructionsLength))
                        }
                    }
            }
            Text("\(instructions.count)/\(UserProfile.maxInstructionsLength) · added to every chat")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(Theme.spacing3)
        .card()
    }

    // MARK: Appearance

    private var appearancePicker: some View {
        HStack(spacing: 4) {
            ForEach(AppearanceOption.allCases) { option in
                let selected = option.rawValue == appearance
                Button { appearance = option.rawValue } label: {
                    VStack(spacing: 6) {
                        Image(systemName: option.symbol).font(.system(size: 18))
                        Text(option.title).font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.75))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        selected ? Color.accentColor : Color.clear,
                        in: RoundedRectangle(cornerRadius: Theme.controlRadius - 2, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .card()
    }

    // MARK: About

    private var aboutCard: some View {
        VStack(spacing: 0) {
            NavigationLink { InfoPage(title: "Help", text: Self.helpText) } label: {
                SettingsRow(symbol: "questionmark.circle", title: "Help", showsChevron: true)
            }
            .buttonStyle(.plain)
            rowDivider
            NavigationLink { InfoPage(title: "Privacy", text: Self.privacyText) } label: {
                SettingsRow(symbol: "lock.shield", title: "Privacy", showsChevron: true)
            }
            .buttonStyle(.plain)
            rowDivider
            SettingsRow(symbol: "cpu", title: "Model", value: Secrets.model)
            rowDivider
            SettingsRow(symbol: "info.circle", title: "Version", value: Self.version)
        }
        .card()
    }

    private var rowDivider: some View {
        Divider().padding(.leading, 52)
    }

    // MARK: Danger zone

    private var deleteButton: some View {
        Button { confirmDelete = true } label: {
            Label("Delete all chats", systemImage: "trash")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.red)
                .frame(maxWidth: .infinity, minHeight: Theme.controlHeight)
                .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(chats.isEmpty)
        .opacity(chats.isEmpty ? 0.4 : 1)
    }

    // MARK: Helpers

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing2) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            content()
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "1.0") (\(info?["CFBundleVersion"] as? String ?? "1"))"
    }

    static let helpText = """
    Pick a mode (Writing, Creative, Conversation, Personal, Developer) from the cards to tune the assistant, or just type.

    • Send: the red button. While a reply is streaming it becomes Stop — tap it to stop; what has arrived is kept.
    • Error? Tap Retry on the banner.
    • New chat: the pencil icon. Past chats and search: the menu icon.
    • Your name and custom instructions (Settings) are added to every conversation.
    """

    static let privacyText = """
    Your chats are stored only on this device.

    To produce a reply, the recent messages of the current chat, your name and your custom instructions are sent to the AI provider (OpenRouter and the model's host). Do not share sensitive information.

    The app has no accounts and no analytics.
    """
}

private struct SettingsRow: View {
    let symbol: String
    let title: String
    var value: String?
    var showsChevron = false

    var body: some View {
        HStack(spacing: Theme.spacing3) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            Text(title)
                .font(.system(size: 16, weight: .medium))
            Spacer(minLength: Theme.spacing2)
            if let value {
                Text(value)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Theme.spacing3)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}

private struct InfoPage: View {
    let title: String
    let text: String

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(size: 16))
                .lineSpacing(5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.spacing3)
                .card()
                .padding(Theme.spacing3)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
        }
        .background { Rectangle().fill(.background).ignoresSafeArea() }
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

extension View {
    /// Rounded filled card with a hairline border (design kit: 16px radius).
    func card() -> some View {
        background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
    }
}

extension AppearanceOption {
    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }
}
