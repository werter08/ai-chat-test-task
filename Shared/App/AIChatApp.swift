import SwiftData
import SwiftUI

@main
struct AIChatApp: App {
    private let container: ModelContainer
    @State private var engine = ChatEngine(client: OpenRouterClient())

    init() {
        let schema = Schema([Chat.self, Message.self])
        do {
            container = try ModelContainer(for: schema)
        } catch {
            // Never crash on a corrupt store: fall back to memory so the app stays usable.
            let memory = ModelConfiguration(isStoredInMemoryOnly: true)
            container = try! ModelContainer(for: schema, configurations: [memory])
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(engine)
                #if os(macOS)
                .frame(minWidth: 720, minHeight: 480)
                #endif
        }
        .modelContainer(container)
    }
}
