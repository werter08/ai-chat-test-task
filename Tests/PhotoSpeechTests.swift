import ImageIO
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import AIChat

// MARK: - Dictation

final class SpeechTextMergerTests: XCTestCase {
    func testEmptyBoxTakesTheTranscript() {
        XCTAssertEqual(SpeechTextMerger.merge(base: "", transcript: "hello there"), "hello there")
        XCTAssertEqual(SpeechTextMerger.merge(base: "   ", transcript: "hello"), "hello")
    }

    func testAppendsToExistingTextWithOneSpace() {
        XCTAssertEqual(SpeechTextMerger.merge(base: "Note:", transcript: "hello"), "Note: hello")
        XCTAssertEqual(SpeechTextMerger.merge(base: "Note: ", transcript: "hello"), "Note: hello")
        XCTAssertEqual(SpeechTextMerger.merge(base: "Line\n", transcript: "next"), "Line\nnext")
    }

    func testEmptyTranscriptLeavesTheTextAlone() {
        XCTAssertEqual(SpeechTextMerger.merge(base: "typed", transcript: ""), "typed")
        XCTAssertEqual(SpeechTextMerger.merge(base: "typed", transcript: "  \n"), "typed")
    }

    func testPartialResultsReplaceEachOtherInsteadOfAccumulating() {
        // Each callback carries the FULL transcript so far; merging against the same base must not duplicate words.
        let base = "Hi"
        XCTAssertEqual(SpeechTextMerger.merge(base: base, transcript: "hello"), "Hi hello")
        XCTAssertEqual(SpeechTextMerger.merge(base: base, transcript: "hello world"), "Hi hello world")
    }
}

@MainActor
final class SpeechInputTests: XCTestCase {
    private final class ScriptedService: SpeechService {
        var transcripts: [String] = []
        var error: SpeechError?
        private(set) var stopped = false

        func start(onText: @escaping @MainActor (String) -> Void, onEnd: @escaping @MainActor () -> Void) async throws {
            if let error { throw error }
            for transcript in transcripts { onText(transcript) }
        }
        func stop() { stopped = true }
    }

    func testDictationFillsTheBoxAndKeepsTypedText() async {
        let service = ScriptedService()
        service.transcripts = ["hello", "hello world"]
        let input = SpeechInput(service: service)
        var box = "Note:"
        input.toggle(currentText: box, apply: { box = $0 }, report: { _ in XCTFail("no error expected") })
        for _ in 0..<100 where !input.isListening { try? await Task.sleep(for: .milliseconds(10)) }

        XCTAssertTrue(input.isListening)
        XCTAssertEqual(box, "Note: hello world")

        input.toggle(currentText: box, apply: { box = $0 }, report: { _ in })   // second tap stops
        XCTAssertFalse(input.isListening)
        XCTAssertTrue(service.stopped)
        XCTAssertEqual(box, "Note: hello world", "stopping keeps the dictated text in the box")
    }

    func testPermissionProblemIsReportedAndNotListening() async {
        let service = ScriptedService()
        service.error = .microphoneDenied
        let input = SpeechInput(service: service)
        var reported: String?
        input.toggle(currentText: "", apply: { _ in }, report: { reported = $0 })
        for _ in 0..<100 where reported == nil { try? await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(input.isListening)
        XCTAssertEqual(reported, SpeechError.microphoneDenied.message)
    }

    func testRecognizerExistsForEnglish() {
        // No permission needed to construct the recognizer; documents the on-device capability on this runtime.
        XCTAssertNotNil(SFSpeechRecognizerProbe.recognizer(for: "en-US"))
    }
}

// MARK: - Photos: encoding, model choice, request building

final class APIMessageEncodingTests: XCTestCase {
    private func json(_ message: APIMessage) throws -> [String: Any] {
        let data = try JSONEncoder().encode(message)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testPlainMessageKeepsStringContent() throws {
        let object = try json(APIMessage(role: "user", content: "hi"))
        XCTAssertEqual(object["content"] as? String, "hi")
    }

    func testPhotoMessageUsesMultiPartContent() throws {
        let object = try json(APIMessage(role: "user", content: "what is this?", imageURLs: ["data:image/jpeg;base64,AAAA"]))
        let parts = try XCTUnwrap(object["content"] as? [[String: Any]])
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0]["type"] as? String, "text")
        XCTAssertEqual(parts[0]["text"] as? String, "what is this?")
        XCTAssertEqual(parts[1]["type"] as? String, "image_url")
        XCTAssertEqual((parts[1]["image_url"] as? [String: Any])?["url"] as? String, "data:image/jpeg;base64,AAAA")
    }

    func testVisionModelIsUsedOnlyWhenARequestContainsAPhoto() {
        let text = [APIMessage(role: "user", content: "hi")]
        let photo = [APIMessage(role: "user", content: "hi"), APIMessage(role: "user", content: "see", imageURLs: ["data:image/jpeg;base64,AA"])]
        XCTAssertEqual(OpenRouterClient.chooseModel(for: text, text: "text-model", vision: "vision-model"), "text-model")
        XCTAssertEqual(OpenRouterClient.chooseModel(for: photo, text: "text-model", vision: "vision-model"), "vision-model")
    }
}

final class ImageProcessingTests: XCTestCase {
    private func makeJPEG(width: Int, height: Int) -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.9, green: 0.3, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return output as Data
    }

    func testLargePhotoIsDownscaledKeepingAspectRatio() throws {
        let original = makeJPEG(width: 3000, height: 1500)
        let small = try XCTUnwrap(ImageProcessing.downscaledJPEG(from: original, maxDimension: 1024))
        let size = try XCTUnwrap(ImageProcessing.pixelSize(of: small))
        XCTAssertLessThanOrEqual(max(size.width, size.height), 1024)
        XCTAssertEqual(size.width / size.height, 2, accuracy: 0.02)
        XCTAssertLessThan(small.count, original.count)
    }

    func testGarbageDataIsRejected() {
        XCTAssertNil(ImageProcessing.downscaledJPEG(from: Data([1, 2, 3, 4])))
    }
}

@MainActor
final class PhotoEngineTests: XCTestCase {
    private final class Recorder: @unchecked Sendable {
        var requests: [[APIMessage]] = []
    }

    private struct RecordingClient: ChatStreaming {
        let recorder: Recorder
        func stream(messages: [APIMessage]) -> AsyncThrowingStream<String, Error> {
            recorder.requests.append(messages)
            return AsyncThrowingStream { continuation in
                continuation.yield("Nice picture.")
                continuation.finish()
            }
        }
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Chat.self, Message.self, Attachment.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func waitUntilIdle(_ engine: ChatEngine, _ chat: Chat) async {
        for _ in 0..<300 where engine.state(for: chat).isGenerating {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private let photo = Data([0xFF, 0xD8, 0xFF, 0xD9])   // content is irrelevant for these tests

    func testPhotoOnlyMessageIsSentWithPlaceholderTextAndImage() async throws {
        let context = try makeContext()
        let chat = Chat(); context.insert(chat)
        let recorder = Recorder()
        let engine = ChatEngine(client: RecordingClient(recorder: recorder))

        engine.send("", images: [photo], in: chat, context: context)
        await waitUntilIdle(engine, chat)

        let user = try XCTUnwrap(chat.sortedMessages.first)
        XCTAssertEqual(user.attachments.count, 1)
        XCTAssertEqual(chat.title, "Photo")
        let sent = try XCTUnwrap(recorder.requests.first?.last)
        XCTAssertEqual(sent.imageURLs.count, 1)
        XCTAssertTrue(sent.imageURLs[0].hasPrefix("data:image/jpeg;base64,"))
        XCTAssertEqual(sent.content, "Describe this image.")
        XCTAssertEqual(chat.sortedMessages.last?.content, "Nice picture.")
    }

    func testTextAndPhotoKeepTheUsersText() async throws {
        let context = try makeContext()
        let chat = Chat(); context.insert(chat)
        let recorder = Recorder()
        let engine = ChatEngine(client: RecordingClient(recorder: recorder))
        engine.send("What is this?", images: [photo, photo], in: chat, context: context)
        await waitUntilIdle(engine, chat)
        let sent = try XCTUnwrap(recorder.requests.first?.last)
        XCTAssertEqual(sent.content, "What is this?")
        XCTAssertEqual(sent.imageURLs.count, 2)
        XCTAssertEqual(chat.title, "What is this?")
    }

    func testEmptyMessageWithoutPhotosIsIgnored() throws {
        let context = try makeContext()
        let chat = Chat(); context.insert(chat)
        let engine = ChatEngine(client: RecordingClient(recorder: Recorder()))
        engine.send("  ", images: [], in: chat, context: context)
        XCTAssertTrue(chat.messages.isEmpty)
    }

    func testAtMostFourPhotosPerMessage() async throws {
        let context = try makeContext()
        let chat = Chat(); context.insert(chat)
        let engine = ChatEngine(client: RecordingClient(recorder: Recorder()))
        engine.send("many", images: Array(repeating: photo, count: 9), in: chat, context: context)
        await waitUntilIdle(engine, chat)
        XCTAssertEqual(chat.sortedMessages.first?.attachments.count, ImageProcessing.maxPhotosPerMessage)
    }

    func testOnlyTheMostRecentPhotoMessagesCarryPictures() throws {
        let context = try makeContext()
        let chat = Chat(); context.insert(chat)
        var messages: [Message] = []
        for index in 0..<5 {
            let message = Message(role: .user, content: index == 0 ? "" : "photo \(index)",
                                  createdAt: .now.addingTimeInterval(Double(index)))
            message.chat = chat
            context.insert(message)
            let attachment = Attachment(data: photo); attachment.message = message; context.insert(attachment)
            messages.append(message)
        }
        let request = ChatEngine.buildRequest(from: messages)   // [system] + 5
        let carrying = request.dropFirst().map { !$0.imageURLs.isEmpty }
        XCTAssertEqual(carrying, [false, false, true, true, true], "only the last \(ChatEngine.maxPhotoMessages) keep their pictures")
        XCTAssertEqual(request[1].content, "[photo]", "an old photo-only message becomes a marker")
        XCTAssertEqual(request[2].content, "photo 1", "an old message keeps its text")
    }

    func testDeletingAMessageDeletesItsPhotos() throws {
        let context = try makeContext()
        let chat = Chat(); context.insert(chat)
        let message = Message(role: .user, content: "x"); message.chat = chat; context.insert(message)
        let attachment = Attachment(data: photo); attachment.message = message; context.insert(attachment)
        try context.save()
        context.delete(chat)
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Attachment>()), 0)
    }
}

import Speech

enum SFSpeechRecognizerProbe {
    static func recognizer(for identifier: String) -> SFSpeechRecognizer? {
        SFSpeechRecognizer(locale: Locale(identifier: identifier))
    }
}
