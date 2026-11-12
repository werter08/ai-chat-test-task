import XCTest
@testable import AIChat

final class SystemPromptTests: XCTestCase {
    func testGeneralPromptHasNoModeOrProfile() {
        let prompt = ChatEngine.makeSystemPrompt(mode: nil, profile: UserProfile())
        XCTAssertEqual(prompt, ChatEngine.systemPrompt)
    }

    func testModeNameAndInstructionsAreIncluded() {
        let profile = UserProfile(name: "  Jude ", instructions: "Answer briefly.")
        let prompt = ChatEngine.makeSystemPrompt(mode: .developer, profile: profile)
        XCTAssertTrue(prompt.contains(ChatMode.developer.systemPrompt))
        XCTAssertTrue(prompt.contains("The user's name is Jude."))
        XCTAssertTrue(prompt.contains("Answer briefly."))
    }

    func testInstructionsAreCapped() {
        let long = String(repeating: "x", count: 2000)
        let prompt = ChatEngine.makeSystemPrompt(mode: nil, profile: UserProfile(instructions: long))
        XCTAssertLessThan(prompt.count, ChatEngine.systemPrompt.count + UserProfile.maxInstructionsLength + 100)
    }
}

final class ChatModeTests: XCTestCase {
    func testChatStoresModeRoundTrip() {
        let chat = Chat()
        XCTAssertNil(chat.mode)
        chat.mode = .creative
        XCTAssertEqual(chat.modeRaw, "creative")
        chat.mode = nil
        XCTAssertNil(chat.modeRaw)
    }

    func testUnknownStoredModeFallsBackToGeneral() {
        let chat = Chat()
        chat.modeRaw = "does-not-exist"
        XCTAssertNil(chat.mode)
    }

    func testEveryModeHasContent() {
        for mode in ChatMode.allCases {
            XCTAssertFalse(mode.quickPrompts.isEmpty, mode.title)
            XCTAssertFalse(mode.systemPrompt.isEmpty, mode.title)
        }
    }
}

final class RecentSearchesTests: XCTestCase {
    func testNewestFirstDedupedAndCapped() {
        var items: [String] = []
        for term in ["a", "b", "c"] { items = RecentSearches.adding(term, to: items) }
        XCTAssertEqual(items, ["c", "b", "a"])
        items = RecentSearches.adding("B", to: items)
        XCTAssertEqual(items, ["B", "c", "a"])
        for i in 0..<20 { items = RecentSearches.adding("t\(i)", to: items) }
        XCTAssertEqual(items.count, RecentSearches.limit)
    }

    func testBlankIsIgnoredAndCodecRoundTrips() {
        XCTAssertEqual(RecentSearches.adding("   ", to: ["x"]), ["x"])
        let raw = RecentSearches.encode(["one", "two"])
        XCTAssertEqual(RecentSearches.decode(raw), ["one", "two"])
        XCTAssertEqual(RecentSearches.decode("not json"), [])
    }
}
