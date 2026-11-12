import XCTest
@testable import AIChat

/// Opt-in integration test against the real OpenRouter API (uses the embedded key).
/// Run with: TEST_RUNNER_RUN_LIVE_TESTS=1 xcodebuild test ...
final class LiveAPITests: XCTestCase {
    func testClientStreamsRealReply() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_LIVE_TESTS"] == "1", "set RUN_LIVE_TESTS=1 to run")
        try XCTSkipIf(KeyVault.apiKey() == nil, "no embedded key")

        var reply = ""
        let stream = OpenRouterClient().stream(messages: [
            APIMessage(role: "user", content: "Reply with exactly one word: pong"),
        ])
        for try await delta in stream { reply += delta }
        XCTAssertFalse(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func testInvalidKeyMapsToUnauthorized() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_LIVE_TESTS"] == "1", "set RUN_LIVE_TESTS=1 to run")
        let client = OpenRouterClient(keyProvider: { "invalid-key" })
        do {
            for try await _ in client.stream(messages: [APIMessage(role: "user", content: "hi")]) {}
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? ChatAPIError, .unauthorized)
        }
    }

    func testVisionModelDescribesAPhoto() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_LIVE_TESTS"] == "1", "set RUN_LIVE_TESTS=1 to run")
        try XCTSkipIf(KeyVault.apiKey() == nil, "no embedded key")
        let jpeg = try XCTUnwrap(ImageProcessing.downscaledJPEG(from: DemoData.samplePhotoJPEG()))
        let message = APIMessage(
            role: "user",
            content: "Name the dominant colors in this picture in one short sentence.",
            imageURLs: ["data:image/jpeg;base64," + jpeg.base64EncodedString()]
        )
        var reply = ""
        do {
            for try await delta in OpenRouterClient().stream(messages: [message]) { reply += delta }
        } catch ChatAPIError.rateLimited {
            throw XCTSkip("free model is rate limited right now")
        }
        XCTAssertFalse(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}

