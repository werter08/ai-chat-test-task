#if DEBUG
import SwiftData

/// Debug-only fixtures used by UI tests (launch args `-uiTestInMemory -uiTestSeedMarkdown`).
/// Never compiled into Release builds; the in-memory store keeps real user data untouched.
enum DemoData {
    static let markdownSample = """
    ## The core idea

    `async` marks a function as a *suspending* function. `await` marks a **suspension point** — where execution may pause.

    ```swift
    func fetchUser(id: Int) async throws -> User

    func loadProfile(id: Int) async {
        do {
            let user = try await fetchUser(id: id)  // suspends here
            print(user.name)
        } catch {
            print("failed: \\(error)")
        }
    }
    ```

    Key points:

    - `try await` and `await try` are both legal
    - Throwing is the **outer** operation
    1. Mark the function `async`
    2. Call it with `await`

    > Suspension is cooperative, not preemptive.

    | Keyword | Meaning |
    |---|---|
    | async | can suspend |
    | await | suspension point |
    """

    @MainActor
    static func seedMarkdownChat(into context: ModelContext) {
        let chat = Chat(title: "Demo: async/await")
        context.insert(chat)
        let question = Message(role: .user, content: "Explain async/await in Swift", createdAt: .now.addingTimeInterval(-2))
        question.chat = chat
        let answer = Message(role: .assistant, content: markdownSample, createdAt: .now.addingTimeInterval(-1))
        answer.chat = chat
        context.insert(question)
        context.insert(answer)
        try? context.save()
    }
}
#endif
