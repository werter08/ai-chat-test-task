import UIKit
import XCTest

/// Smoke walkthrough of the main flows. If SHOT_DIR is set (TEST_RUNNER_SHOT_DIR=... on the host),
/// screenshots are also written there as PNG files.
final class WalkthroughUITests: XCTestCase {
    /// Average brightness (0 = black, 1 = white) of one pixel of the current screen, near the top where only the page background shows.
    private func backgroundBrightness() -> CGFloat {
        guard let cg = XCUIScreen.main.screenshot().image.cgImage else { return -1 }
        let rect = CGRect(x: cg.width / 2, y: Int(Double(cg.height) * 0.02), width: 1, height: 1)
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
        shot("3_sidebar")

        // Settings is a pushed page, not a sheet.
        app.buttons["sidebar.settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        shot("4_settings_light")

        // Switching appearance changes the settings page itself.
        app.buttons["System"].tap()   // start from a known state (system = light on this simulator)
        sleep(1)
        XCTAssertGreaterThan(backgroundBrightness(), 0.7, "settings should be light")
        app.buttons["Dark"].tap()
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
}
