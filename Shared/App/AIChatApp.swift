import SwiftData
import SwiftUI

@main
struct AIChatApp: App {
    private let container: ModelContainer
    @State private var engine: ChatEngine
    @State private var toast = Toast()
    @State private var speech: SpeechInput

    init() {
        let schema = Schema([Chat.self, Message.self, Attachment.self])
        // SwiftData does not create this folder on a fresh install; without it Core Data logs recovery errors.
        try? FileManager.default.createDirectory(
            at: URL.applicationSupportDirectory, withIntermediateDirectories: true
        )
        #if DEBUG
        let arguments = CommandLine.arguments
        let inMemory = arguments.contains("-uiTestInMemory")
        let client: ChatStreaming = arguments.contains("-uiTestFakeStream") ? DemoStreamingClient() : OpenRouterClient()
        let speechService: SpeechService? = arguments.contains("-uiTestFakeSpeech") ? FakeSpeechService() : nil
        #else
        let inMemory = false
        let client: ChatStreaming = OpenRouterClient()
        let speechService: SpeechService? = nil
        #endif
        _speech = State(initialValue: SpeechInput(service: speechService))
        _engine = State(initialValue: ChatEngine(client: client))
        do {
            container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: inMemory)])
        } catch {
            // Never crash on a corrupt store: fall back to memory so the app stays usable.
            let memory = ModelConfiguration(isStoredInMemoryOnly: true)
            container = try! ModelContainer(for: schema, configurations: [memory])
        }
        #if DEBUG
        if arguments.contains("-uiTestSeedMarkdown") {
            DemoData.seedMarkdownChat(into: container.mainContext)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(engine)
                .environment(toast)
                .environment(speech)
                #if os(macOS)
                .frame(minWidth: 720, minHeight: 480)
                #endif
        }
        .modelContainer(container)
    }
}
