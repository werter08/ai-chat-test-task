import SwiftData
import SwiftUI

/// Settings sheet (grid icon): profile, personalization, appearance, data and about.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
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
        NavigationStack {
            Form {
                Section("Profile") {
                    HStack(spacing: Theme.spacing3) {
                        Text(initial)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(Color.accentColor, in: Circle())
                            .accessibilityHidden(true)
                        TextField("Your name", text: $name)
                            .font(.system(size: 17, weight: .medium))
                            .textContentType(.givenName)
                    }
                }

                Section {
                    TextEditor(text: $instructions)
                        .frame(minHeight: 110)
                        .onChange(of: instructions) {
                            if instructions.count > UserProfile.maxInstructionsLength {
                                instructions = String(instructions.prefix(UserProfile.maxInstructionsLength))
                            }
                        }
                } header: {
                    Text("Personalization")
                } footer: {
                    Text("Tell the assistant how to answer (tone, language, what to know about you). Added to every chat. \(instructions.count)/\(UserProfile.maxInstructionsLength)")
                }

                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        ForEach(AppearanceOption.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Data") {
                    Button("Delete all chats", role: .destructive) { confirmDelete = true }
                        .disabled(chats.isEmpty)
                }

                Section("About") {
                    NavigationLink("Help") { InfoPage(title: "Help", text: Self.helpText) }
                    NavigationLink("Privacy") { InfoPage(title: "Privacy", text: Self.privacyText) }
                    LabeledContent("Model", value: Secrets.model)
                    LabeledContent("Version", value: Self.version)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Delete all chats?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete all", role: .destructive) { ChatStore.deleteAll(chats, engine: engine, context: context) }
            } message: {
                Text("This can't be undone.")
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 520)
        #endif
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "1.0") (\(info?["CFBundleVersion"] as? String ?? "1"))"
    }

    static let helpText = """
    Pick a mode (Writing, Creative, Conversation, Personal, Developer) to tune the assistant, or just type.

    • Send: the red button. While a reply is streaming it becomes Stop — tap it to stop; what has arrived is kept.
    • Error? Tap Retry on the banner.
    • New chat: the pencil icon. Past chats and search: the clock icon.
    • Your name and custom instructions (Settings) are added to every conversation.
    """

    static let privacyText = """
    Your chats are stored only on this device.

    To produce a reply, the recent messages of the current chat, your name and your custom instructions are sent to the AI provider (OpenRouter and the model's host). Do not share sensitive information.

    The app has no accounts and no analytics.
    """
}

private struct InfoPage: View {
    let title: String
    let text: String

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(size: 16))
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.spacing3)
        }
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
