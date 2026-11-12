#if DEBUG
import ImageIO
import SwiftData
import UniformTypeIdentifiers

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

/// Simulated backend for UI tests (`-uiTestFakeStream`): a silent "reasoning" pause, then the sample reply in small chunks.
struct DemoStreamingClient: ChatStreaming {
    func stream(messages: [APIMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                try? await Task.sleep(for: .milliseconds(700))
                let text = DemoData.markdownSample
                var index = text.startIndex
                while index < text.endIndex, !Task.isCancelled {
                    let end = text.index(index, offsetBy: 14, limitedBy: text.endIndex) ?? text.endIndex
                    continuation.yield(String(text[index..<end]))
                    index = end
                    try? await Task.sleep(for: .milliseconds(60))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Simulated dictation for UI tests (`-uiTestFakeSpeech`): emits "Hello from speech input" word by word.
@MainActor
final class FakeSpeechService: SpeechService {
    private var task: Task<Void, Never>?

    func start(onText: @escaping @MainActor (String) -> Void, onEnd: @escaping @MainActor () -> Void) async throws {
        let words = ["Hello", "from", "speech", "input"]
        task = Task {
            for index in words.indices {
                try? await Task.sleep(for: .milliseconds(300))
                if Task.isCancelled { return }
                onText(words[...index].joined(separator: " "))
            }
        }
    }

    func stop() { task?.cancel() }
}

extension DemoData {
    /// A small generated picture (gradient + circle) used by UI tests (`-uiTestSeedPhoto`).
    static func samplePhotoJPEG() -> Data {
        let width = 480, height = 320
        let space = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let gradient = CGGradient(colorsSpace: space,
                                        colors: [CGColor(red: 0.98, green: 0.45, blue: 0.35, alpha: 1),
                                                 CGColor(red: 0.25, green: 0.45, blue: 0.95, alpha: 1)] as CFArray,
                                        locations: [0, 1]) else { return Data() }
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
        context.setFillColor(CGColor(gray: 1, alpha: 0.9))
        context.fillEllipse(in: CGRect(x: 300, y: 170, width: 90, height: 90))
        guard let image = context.makeImage() else { return Data() }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return Data() }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return output as Data
    }
}
#endif

