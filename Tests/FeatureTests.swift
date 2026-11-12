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

final class DrawerMathTests: XCTestCase {
    func testNothingMovesUntilTheSwipeIsClearlyHorizontal() {
        var state = DrawerDrag()
        DrawerMath.update(&state, translation: CGSize(width: 3, height: 20))     // mostly vertical: a scroll
        XCTAssertFalse(state.locked)
        XCTAssertEqual(state.offset, 0)
        DrawerMath.update(&state, translation: CGSize(width: 12, height: 30))    // still vertical-dominant
        XCTAssertFalse(state.locked)
    }

    func testTheDrawerNeverLeapsWhenTheSwipeLocks() {
        // A diagonal start that becomes horizontal after the finger already travelled 40 pt sideways.
        var state = DrawerDrag()
        DrawerMath.update(&state, translation: CGSize(width: 20, height: 30))
        DrawerMath.update(&state, translation: CGSize(width: 40, height: 28))
        XCTAssertTrue(state.locked)
        XCTAssertEqual(state.offset, 0, "at the lock the drawer is exactly where it was — no jump")
        DrawerMath.update(&state, translation: CGSize(width: 55, height: 28))
        XCTAssertEqual(state.offset, 15, "afterwards it follows the finger 1:1")
    }

    func testOffsetNeverDecreasesFasterThanTheFingerMoves() {
        var state = DrawerDrag()
        var previous: CGFloat = 0
        for x in stride(from: CGFloat(0), through: 200, by: 4) {
            DrawerMath.update(&state, translation: CGSize(width: x, height: x * 0.3))
            XCTAssertLessThanOrEqual(state.offset - previous, 4.0001, "no step larger than the finger step")
            previous = state.offset
        }
    }

    func testPositionIsClampedToTheDrawerWidth() {
        XCTAssertEqual(DrawerMath.position(isOpen: false, width: 280, drag: -50), 0)
        XCTAssertEqual(DrawerMath.position(isOpen: false, width: 280, drag: 100), 100)
        XCTAssertEqual(DrawerMath.position(isOpen: false, width: 280, drag: 900), 280)
        XCTAssertEqual(DrawerMath.position(isOpen: true, width: 280, drag: 50), 280)
        XCTAssertEqual(DrawerMath.position(isOpen: true, width: 280, drag: -100), 180)
    }

    func testSettlingUsesProjectionSoAFlickOpensAndASlowShortDragDoesNot() {
        let width: CGFloat = 280
        // Slow, short drag (projection stays under half): stays closed.
        XCTAssertEqual(DrawerMath.settlesOpen(isOpen: false, width: width, translation: CGSize(width: 60, height: 5), predictedEnd: CGSize(width: 90, height: 5)), false)
        // Quick flick: short travel but a long projected end: opens.
        XCTAssertEqual(DrawerMath.settlesOpen(isOpen: false, width: width, translation: CGSize(width: 60, height: 5), predictedEnd: CGSize(width: 220, height: 5)), true)
        // Open drawer dragged a little left: stays open; dragged far left: closes.
        XCTAssertEqual(DrawerMath.settlesOpen(isOpen: true, width: width, translation: CGSize(width: -40, height: 0), predictedEnd: CGSize(width: -60, height: 0)), true)
        XCTAssertEqual(DrawerMath.settlesOpen(isOpen: true, width: width, translation: CGSize(width: -150, height: 0), predictedEnd: CGSize(width: -200, height: 0)), false)
    }

    func testAVerticalDragNeverChangesTheDrawer() {
        XCTAssertNil(DrawerMath.settlesOpen(isOpen: false, width: 280, translation: CGSize(width: 10, height: 90), predictedEnd: CGSize(width: 12, height: 200)))
    }
}
