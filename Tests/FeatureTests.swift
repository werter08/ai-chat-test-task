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
