import XCTest
@testable import AIChat

final class SSEParserTests: XCTestCase {
    func testParsesDelta() {
        let line = #"data: {"choices":[{"delta":{"content":"Hel"},"finish_reason":null}]}"#
        XCTAssertEqual(SSEParser.parse(line: line), .delta("Hel"))
    }

    func testParsesDoneMarker() {
        XCTAssertEqual(SSEParser.parse(line: "data: [DONE]"), .done)
    }

    func testIgnoresKeepAliveCommentAndBlank() {
        XCTAssertEqual(SSEParser.parse(line: ": OPENROUTER PROCESSING"), .ignore)
        XCTAssertEqual(SSEParser.parse(line: ""), .ignore)
    }

    func testIgnoresEmptyAndRoleOnlyDeltas() {
        XCTAssertEqual(SSEParser.parse(line: #"data: {"choices":[{"delta":{"role":"assistant","content":""}}]}"#), .ignore)
        XCTAssertEqual(SSEParser.parse(line: #"data: {"choices":[]}"#), .ignore)
    }

    func testIgnoresMalformedJSON() {
        XCTAssertEqual(SSEParser.parse(line: "data: {not json"), .ignore)
    }

    func testParsesMidStreamError() {
        let line = #"data: {"error":{"code":429,"message":"Rate limit exceeded"}}"#
        XCTAssertEqual(SSEParser.parse(line: line), .error(code: 429, message: "Rate limit exceeded"))
    }

    func testPreservesUnicodeAndWhitespace() {
        let line = #"data: {"choices":[{"delta":{"content":" привет 👋"}}]}"#
        XCTAssertEqual(SSEParser.parse(line: line), .delta(" привет 👋"))
    }
}

final class ChatAPIErrorTests: XCTestCase {
    func testStatusMapping() {
        XCTAssertEqual(ChatAPIError.from(status: 401, message: nil), .unauthorized)
        XCTAssertEqual(ChatAPIError.from(status: 402, message: nil), .insufficientCredits)
        XCTAssertEqual(ChatAPIError.from(status: 404, message: nil), .modelUnavailable)
        XCTAssertEqual(ChatAPIError.from(status: 429, message: nil), .rateLimited)
        XCTAssertEqual(ChatAPIError.from(status: 502, message: "x"), .server("x"))
    }

    func testTransportMapping() {
        XCTAssertEqual(ChatAPIError.from(transport: URLError(.notConnectedToInternet)), .offline)
        XCTAssertEqual(ChatAPIError.from(transport: URLError(.timedOut)), .timeout)
        XCTAssertNil(ChatAPIError.from(transport: URLError(.cancelled)))
        XCTAssertNil(ChatAPIError.from(transport: CancellationError()))
    }
}

final class KeyVaultTests: XCTestCase {
    func testRoundTrip() {
        let salt: [UInt8] = (0..<32).map { UInt8(($0 * 37 + 11) % 256) }
        let secret = "sk-or-v1-test-0123456789"
        let blob = KeyVault.conceal(secret, salt: salt)
        XCTAssertNotEqual(String(bytes: blob, encoding: .utf8), secret)
        XCTAssertEqual(KeyVault.reveal(blob: blob, salt: salt), secret)
    }

    func testEmptyBlobYieldsNil() {
        XCTAssertNil(KeyVault.reveal(blob: [], salt: [1, 2, 3]))
    }
}
