import SwiftData
import XCTest
@testable import AIChat

/// Scripted backend: emits `chunks`, then optionally fails; can hang to test Stop.
private struct MockClient: ChatStreaming {
    var chunks: [String] = []
    var failure: ChatAPIError?
    var hangAfterChunks = false
    /// When cancelled, end the stream without throwing (what AsyncThrowingStream does for a cancelled consumer).
    var quietCancel = false

    func stream(messages: [APIMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                for chunk in chunks { continuation.yield(chunk) }
                if let failure { continuation.finish(throwing: failure); return }
                if hangAfterChunks {
                    // Wait until cancelled.
                    while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(10)) }
                    if quietCancel { continuation.finish() } else { continuation.finish(throwing: CancellationError()) }
                    return
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

@MainActor
final class ChatEngineTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Chat.self, Message.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func waitUntilIdle(_ engine: ChatEngine, _ chat: Chat) async {
        for _ in 0..<300 where engine.state(for: chat).isGenerating {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func testSendStreamsAndPersistsReply() async throws {
        let context = try makeContext()
        let chat = Chat(); context.insert(chat)
        let engine = ChatEngine(client: MockClient(chunks: ["Hel", "lo", "!"]))

        engine.send("  Hi there  ", in: chat, context: context)
        XCTAssertTrue(engine.state(for: chat).isGenerating)
        await waitUntilIdle(engine, chat)

        let messages = chat.sortedMessages
        XCTAssertEqual(messages.map(\.roleRaw), ["user", "assistant"])
        XCTAssertEqual(messages[0].content, "Hi there")
        XCTAssertEqual(messages[1].content, "Hello!")
        XCTAssertNil(engine.state(for: chat).error)
        XCTAssertEqual(chat.title, "Hi there")
    }

    func testFailureBeforeFirstTokenLeavesNoEmptyAssistantMessage() async throws {
        let context = try makeContext()
        let chat = Chat(); context.insert(chat)
        let engine = ChatEngine(client: MockClient(failure: .offline))

        engine.send("Hello", in: chat, context: context)
        await waitUntilIdle(engine, chat)

        XCTAssertEqual(chat.messages.count, 1)
        XCTAssertEqual(engine.state(for: chat).error, .offline)
    }

    func testRetryAfterFailureProducesReply() async throws {
        let context = try makeContext()
        let chat = Chat(); context.insert(chat)
        let failing = ChatEngine(client: MockClient(failure: .rateLimited))
        failing.send("Hello", in: chat, context: context)
        await waitUntilIdle(failing, chat)
        XCTAssertEqual(failing.state(for: chat).error, .rateLimited)

        let working = ChatEngine(client: MockClient(chunks: ["OK"]))
        working.retry(chat, context: context)
        await waitUntilIdle(working, chat)

        XCTAssertEqual(chat.sortedMessages.map(\.content), ["Hello", "OK"])
        XCTAssertNil(working.state(for: chat).error)
    }

    func testRetryDropsPartialReplyAfterMidStreamError() async throws {
        let context = try makeContext()
        let chat = Chat(); context.insert(chat)
        let engine = ChatEngine(client: MockClient(chunks: ["Part"], failure: .server(nil)))
        engine.send("Q", in: chat, context: context)
        await waitUntilIdle(engine, chat)
        XCTAssertEqual(chat.sortedMessages.last?.content, "Part")

        let fixed = ChatEngine(client: MockClient(chunks: ["Full answer"]))
        fixed.retry(chat, context: context)
        await waitUntilIdle(fixed, chat)
        XCTAssertEqual(chat.sortedMessages.map(\.content), ["Q", "Full answer"])
    }

    func testStopKeepsPartialReplyWithoutError() async throws {
        let context = try makeContext()
        let chat = Chat(); context.insert(chat)
        let engine = ChatEngine(client: MockClient(chunks: ["Partial"], hangAfterChunks: true))

        engine.send("Go", in: chat, context: context)
        for _ in 0..<200 where chat.messages.count < 2 { try? await Task.sleep(for: .milliseconds(10)) }
        engine.stop(chat)
        await waitUntilIdle(engine, chat)

        // [user, partial reply, "stopped" note]
        XCTAssertEqual(chat.sortedMessages.map(\.roleRaw), ["user", "assistant", "note"])
        XCTAssertEqual(chat.sortedMessages[1].content, "Partial")
        XCTAssertFalse(engine.state(for: chat).isGenerating)
        XCTAssertNil(engine.state(for: chat).error)
    }

    func testStopBeforeFirstTokenIsNotAnErrorAndAddsNote() async throws {
        for quiet in [false, true] {
            let context = try makeContext()
            let chat = Chat(); context.insert(chat)
            let engine = ChatEngine(client: MockClient(hangAfterChunks: true, quietCancel: quiet))

            engine.send("Go", in: chat, context: context)
            XCTAssertTrue(engine.state(for: chat).isGenerating)
            engine.stop(chat)
            await waitUntilIdle(engine, chat)

            XCTAssertNil(engine.state(for: chat).error, "quietCancel=\(quiet)")
            XCTAssertEqual(chat.sortedMessages.map(\.roleRaw), ["user", "note"], "quietCancel=\(quiet)")
            XCTAssertEqual(chat.sortedMessages.last?.content, ChatEngine.stoppedNote)
        }
    }

    func testStopAfterPartialReplyKeepsReplyThenNote() async throws {
        let context = try makeContext()
        let chat = Chat(); context.insert(chat)
        let engine = ChatEngine(client: MockClient(chunks: ["Part"], hangAfterChunks: true, quietCancel: true))
        engine.send("Go", in: chat, context: context)
        for _ in 0..<200 where chat.messages.count < 2 { try? await Task.sleep(for: .milliseconds(10)) }
        engine.stop(chat)
        await waitUntilIdle(engine, chat)
        XCTAssertEqual(chat.sortedMessages.map(\.roleRaw), ["user", "assistant", "note"])
        XCTAssertNil(engine.state(for: chat).error)
    }

    func testNotesAreNeverSentToTheModel() {
        let messages = [Message(role: .user, content: "hi"), Message(role: .note, content: "stopped")]
        let request = ChatEngine.buildRequest(from: messages)
        XCTAssertEqual(request.map(\.role), ["system", "user"])
    }

    func testRetryAfterStopRemovesNoteAndRegenerates() async throws {
        let context = try makeContext()
        let chat = Chat(); context.insert(chat)
        let stopping = ChatEngine(client: MockClient(hangAfterChunks: true, quietCancel: true))
        stopping.send("Q", in: chat, context: context)
        stopping.stop(chat)
        await waitUntilIdle(stopping, chat)

        let working = ChatEngine(client: MockClient(chunks: ["Answer"]))
        working.retry(chat, context: context)
        await waitUntilIdle(working, chat)
        XCTAssertEqual(chat.sortedMessages.map(\.content), ["Q", "Answer"])
    }

    func testDiscardWhileGeneratingDoesNotTouchChat() async throws {
        let context = try makeContext()
        let chat = Chat(); context.insert(chat)
        let engine = ChatEngine(client: MockClient(hangAfterChunks: true, quietCancel: true))
        engine.send("Q", in: chat, context: context)
        engine.discard(chat)
        context.delete(chat)
        try context.save()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertFalse(engine.state(for: chat).isGenerating)
    }

    func testBlankMessageIsIgnored() async throws {
        let context = try makeContext()
        let chat = Chat(); context.insert(chat)
        let engine = ChatEngine(client: MockClient(chunks: ["x"]))
        engine.send("   \n ", in: chat, context: context)
        XCTAssertTrue(chat.messages.isEmpty)
        XCTAssertFalse(engine.state(for: chat).isGenerating)
    }

    func testRequestIncludesSystemPromptAndCapsContext() {
        let messages = (0..<50).map { Message(role: $0 % 2 == 0 ? .user : .assistant, content: "m\($0)") }
        let request = ChatEngine.buildRequest(from: messages)
        XCTAssertEqual(request.first?.role, "system")
        XCTAssertEqual(request.count, ChatEngine.maxContextMessages + 1)
        XCTAssertEqual(request.last?.content, "m49")
    }

    func testTitleIsTruncated() {
        XCTAssertEqual(ChatEngine.makeTitle(from: "short"), "short")
        let long = String(repeating: "a", count: 80)
        XCTAssertEqual(ChatEngine.makeTitle(from: long).count, 41)
    }
}
