import UIKit
import XCTest

/// Smoke walkthrough of the main flows. If SHOT_DIR is set (TEST_RUNNER_SHOT_DIR=... on the host),
/// screenshots are also written there as PNG files.
final class WalkthroughUITests: XCTestCase {
    /// Average brightness (0 = black, 1 = white) of one pixel of the current screen, near the top where only the page background shows.
    private func backgroundBrightness(x: Double = 0.5, y: Double = 0.02) -> CGFloat {
        guard let cg = XCUIScreen.main.screenshot().image.cgImage else { return -1 }
        let rect = CGRect(x: Int(Double(cg.width) * x), y: Int(Double(cg.height) * y), width: 1, height: 1)
        guard let crop = cg.cropping(to: rect) else { return -1 }
        var px = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return -1 }
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (CGFloat(px[0]) + CGFloat(px[1]) + CGFloat(px[2])) / (3 * 255)
    }

    private func shot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SHOT_DIR"] {
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    func testSidebarSettingsAndAppearance() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-didSeeOnboarding", "YES"]
        app.launch()

        // Home opens on an empty chat (no "No chat" screen).
        XCTAssertTrue(app.staticTexts["Chatterly"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["Ask me anything…"].exists)
        shot("1_home")

        // The chat may still be in a mode from an earlier run: leave it so the mode cards are visible.
        let leaveMode = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Tap to leave this mode'")).firstMatch
        if leaveMode.exists { leaveMode.tap() }

        // Mode card -> intro + bordered quick prompts.
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Writing'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Writing Mode ✍️"].waitForExistence(timeout: 5))
        shot("2_mode_writing")

        // Sidebar: full screen with New chat button.
        app.buttons["Menu"].tap()
        XCTAssertTrue(app.buttons["New chat"].waitForExistence(timeout: 5))
        sleep(1)
        shot("3_sidebar")
        // The dimmed (free) zone must cover the status-bar safe area too: top-right pixel is darker than the white page.
        XCTAssertLessThan(backgroundBrightness(x: 0.92, y: 0.01), 0.97, "dim layer should reach the top safe area")
        XCTAssertLessThan(backgroundBrightness(x: 0.92, y: 0.995), 0.97, "dim layer should reach the bottom safe area")

        // Tapping the dimmed 30% closes the drawer.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        sleep(1)
        XCTAssertTrue(app.textFields["Ask me anything…"].isHittable, "drawer should close after tapping the free zone")
        app.buttons["Menu"].tap()
        XCTAssertTrue(app.buttons["sidebar.settings"].waitForExistence(timeout: 5))

        // Settings is a pushed page, not a sheet.
        app.buttons["sidebar.settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        shot("4_settings_light")

        // Switching appearance changes the settings page itself.
        // Tap the far-left edge of the tile (not the icon/text): the whole tile must be clickable.
        app.buttons["Light"].coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.5)).tap()
        sleep(1)
        XCTAssertGreaterThan(backgroundBrightness(), 0.7, "settings should be light")
        app.buttons["Dark"].coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5)).tap()
        sleep(1)
        shot("5_settings_dark")
        XCTAssertLessThan(backgroundBrightness(), 0.3, "settings page did not turn dark")

        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Chatterly"].waitForExistence(timeout: 5))
        shot("6_home_dark")
        XCTAssertLessThan(backgroundBrightness(), 0.3, "home did not turn dark")

        // Reset for other runs.
        app.buttons["Menu"].tap()
        app.buttons["sidebar.settings"].tap()
        app.buttons["System"].tap()
    }

    /// Markdown reply (code block, list, table) renders, and Copy gives visible feedback.
    func testMarkdownReplyAndCopyFeedback() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-didSeeOnboarding", "YES", "-uiTestInMemory", "-uiTestSeedMarkdown"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Chatterly"].waitForExistence(timeout: 10))

        app.buttons["Menu"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Demo: async/await'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        XCTAssertTrue(app.staticTexts["The core idea"].waitForExistence(timeout: 5), "heading should be rendered, not '## The core idea'")
        XCTAssertFalse(app.staticTexts["## The core idea"].exists)
        // A reopened chat must show its newest content right away (no dragging needed to reveal it).
        XCTAssertTrue(app.staticTexts["suspension point"].isHittable, "bottom of a reopened chat should be visible immediately")
        shot("7_markdown")

        // Copy gives visible feedback.
        let copy = app.buttons["Copy"].firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        copy.tap()
        XCTAssertTrue(app.buttons["Copied"].waitForExistence(timeout: 2), "copy button should switch to 'Copied'")
        shot("8_copied")
        // The "Copied to clipboard" toast is not exposed to XCUITest (it is non-interactive); it is checked in the 8_copied screenshot.
    }

    /// Composer: focus glow, expand to 30% of the screen, then full screen, then back.
    func testComposerExpandsToThirdThenFullScreen() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-didSeeOnboarding", "YES", "-uiTestInMemory"]
        app.launch()
        let field = app.textFields["Ask me anything…"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        // Empty chat is kept short: greeting + one subtitle (no third line).
        XCTAssertTrue(app.staticTexts["What would you like to do today?"].exists)
        XCTAssertFalse(app.staticTexts["Explore what I can help with"].exists, "the third text line was removed")
        field.tap()
        sleep(1)
        shot("9_composer_focused")

        app.buttons["Expand input"].tap()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 5), "expanded mode uses a multi-line editor")
        let thirdHeight = app.textViews.firstMatch.frame.height
        let screenHeight = app.frame.height
        XCTAssertGreaterThan(thirdHeight, screenHeight * 0.2)
        XCTAssertLessThan(thirdHeight, screenHeight * 0.4)
        shot("10_composer_third")
        // Expanded: the send button sits below the editor and spans the width (VStack layout).
        let send = app.buttons["Send message"]
        XCTAssertGreaterThan(send.frame.width, app.frame.width * 0.7, "send button should be full width when expanded")
        XCTAssertGreaterThan(send.frame.minY, app.textViews.firstMatch.frame.maxY - 2, "send button should be below the editor")

        app.buttons["Expand input"].tap()
        XCTAssertTrue(app.buttons["Collapse input"].waitForExistence(timeout: 5))
        sleep(1)
        XCTAssertGreaterThan(app.textViews.firstMatch.frame.height, screenHeight * 0.5, "full mode should take most of the screen")
        shot("11_composer_full")

        app.buttons["Collapse input"].tap()
        XCTAssertTrue(app.textFields["Ask me anything…"].waitForExistence(timeout: 5))
    }

    private func launchWithFakeStream() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-didSeeOnboarding", "YES", "-uiTestInMemory", "-uiTestFakeStream"]
        app.launch()
        return app
    }

    /// The reply is typed out progressively (not dumped at once) and ends fully rendered.
    func testReplyIsTypedOutProgressively() throws {
        let app = launchWithFakeStream()
        let field = app.textFields["Ask me anything…"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("Explain async/await")
        app.buttons["Send message"].tap()

        // Shortly after the first characters the end of the reply must not be visible yet.
        let heading = app.staticTexts["The core idea"]
        XCTAssertTrue(heading.waitForExistence(timeout: 8), "reply should start appearing")
        XCTAssertFalse(app.staticTexts["suspension point"].exists, "the end of the reply should not be shown yet")
        shot("12_typing")
        XCTAssertFalse(app.buttons["Copy"].exists, "Copy appears only once the reply is finished")
        sleep(2)
        shot("12b_typing_mid")

        // Eventually everything is there.
        XCTAssertTrue(app.staticTexts["suspension point"].waitForExistence(timeout: 30), "full reply should appear")
        sleep(1)
        shot("13_typed_done")
        XCTAssertFalse(app.buttons["Stop generating"].exists)
        // Copy sits below the finished message, under its last line.
        let copy = app.buttons["Copy"].firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 5), "Copy should appear after the reply finishes")
        XCTAssertGreaterThan(copy.frame.minY, app.staticTexts["suspension point"].frame.maxY - 1, "Copy should be below the message")
        sleep(1)
        XCTAssertTrue(copy.isHittable, "after finishing, the bottom of the reply (incl. Copy) must be visible, not hidden under the composer")
    }

    /// Stopping mid-stream is not an error: partial text stays and a note appears.
    func testStopMidStreamShowsNoteNotError() throws {
        let app = launchWithFakeStream()
        let field = app.textFields["Ask me anything…"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("Hello")
        app.buttons["Send message"].tap()

        let stop = app.buttons["Stop generating"].firstMatch
        XCTAssertTrue(stop.waitForExistence(timeout: 8))
        stop.tap()

        XCTAssertTrue(app.staticTexts["You stopped the response."].waitForExistence(timeout: 5), "a stopped note should appear")
        XCTAssertFalse(app.staticTexts["Unexpected response"].exists, "stopping must not show an API error")
        XCTAssertFalse(app.staticTexts["No reply received"].exists)
        shot("14_stopped")
    }

    /// Regression: the drawer opened once by swipe, was closed, and then never opened again.
    func testSwipeOpensDrawerRepeatedlyAndAfterEveryWayOfClosing() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-didSeeOnboarding", "YES", "-uiTestInMemory"]
        app.launch()
        XCTAssertTrue(app.textFields["Ask me anything…"].waitForExistence(timeout: 10))

        func swipe(from: Double, to: Double) {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: from, dy: 0.45))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: to, dy: 0.45))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        func assertOpen(_ message: String) {
            XCTAssertTrue(app.buttons["sidebar.settings"].waitForExistence(timeout: 3), message)
            sleep(1)
            XCTAssertTrue(app.buttons["sidebar.settings"].isHittable, message)
        }
        func assertClosed(_ message: String) {
            sleep(1)
            // A closed drawer sits behind the content: it may still exist, but must not be tappable.
            XCTAssertFalse(app.buttons["sidebar.settings"].isHittable, message)
            XCTAssertTrue(app.textFields["Ask me anything…"].isHittable, message)
        }

        // 1) swipe open (from the middle of the screen, not only the edge) -> close by tapping the dimmed zone
        swipe(from: 0.35, to: 0.9)
        assertOpen("swipe right from the middle should open the drawer")
        shot("15_swipe_opened")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        assertClosed("tap on the free zone should close")

        // 2) swipe open again -> close by dragging it fully shut (this used to leave the state stuck)
        swipe(from: 0.1, to: 0.85)
        assertOpen("drawer must open again after a tap-close")
        swipe(from: 0.6, to: 0.02)
        assertClosed("dragging it shut should close")

        // 3) after a drag-close it must still open — by swipe, then by the menu button
        swipe(from: 0.1, to: 0.85)
        assertOpen("drawer must open by swipe after a drag-close")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        assertClosed("closed again")
        app.buttons["Menu"].tap()
        assertOpen("menu button must still open it")
    }

    /// Share is not a permanent button any more: it lives in the long-press menu next to Copy.
    func testShareOnlyOnLongPress() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-didSeeOnboarding", "YES", "-uiTestInMemory", "-uiTestSeedMarkdown"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Chatterly"].waitForExistence(timeout: 10))
        app.buttons["Menu"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Demo: async/await'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.staticTexts["The core idea"].waitForExistence(timeout: 5))

        XCTAssertFalse(app.buttons["Share"].exists, "no always-visible share button")

        app.staticTexts["The core idea"].press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["Share"].waitForExistence(timeout: 3), "long press should reveal Share")
        XCTAssertTrue(app.buttons["Copy"].exists)
        shot("16_long_press_menu")
    }
}

