import SwiftUI
import XCTest
@testable import AIChat

final class MarkdownParserTests: XCTestCase {
    func testHeadingAndParagraph() {
        let blocks = MarkdownParser.parse("## The core idea\n\nasync marks a function.")
        XCTAssertEqual(blocks, [.heading(level: 2, text: "The core idea"), .paragraph("async marks a function.")])
    }

    func testFencedCodeKeepsNewlinesAndIndentation() {
        let md = "Intro\n\n```swift\nfunc a() {\n    print(1)\n}\n```\n\nOutro"
        let blocks = MarkdownParser.parse(md)
        XCTAssertEqual(blocks, [
            .paragraph("Intro"),
            .code(language: "swift", code: "func a() {\n    print(1)\n}"),
            .paragraph("Outro"),
        ])
    }

    func testUnterminatedFenceWhileStreamingIsAnOpenCodeBlock() {
        let blocks = MarkdownParser.parse("```python\nprint('hi')")
        XCTAssertEqual(blocks, [.code(language: "python", code: "print('hi')")])
    }

    func testFenceWithoutLanguage() {
        XCTAssertEqual(MarkdownParser.parse("```\nx\n```"), [.code(language: nil, code: "x")])
    }

    func testBulletAndNumberedLists() {
        let blocks = MarkdownParser.parse("- one\n- two\n  - nested\n\n1. first\n2. second")
        XCTAssertEqual(blocks, [
            .list([
                MarkdownListItem(indent: 0, marker: "•", text: "one"),
                MarkdownListItem(indent: 0, marker: "•", text: "two"),
                MarkdownListItem(indent: 1, marker: "◦", text: "nested"),
            ]),
            .list([
                MarkdownListItem(indent: 0, marker: "1.", text: "first"),
                MarkdownListItem(indent: 0, marker: "2.", text: "second"),
            ]),
        ])
    }

    func testQuoteRuleAndTable() {
        let md = "> wise words\n\n---\n\n| A | B |\n|---|---|\n| 1 | 2 |"
        XCTAssertEqual(MarkdownParser.parse(md), [
            .quote("wise words"),
            .rule,
            .table([["A", "B"], ["1", "2"]]),
        ])
    }

    func testHashWithoutSpaceIsNotAHeading() {
        XCTAssertEqual(MarkdownParser.parse("#hashtag"), [.paragraph("#hashtag")])
    }

    func testEmptyInput() {
        XCTAssertEqual(MarkdownParser.parse(""), [])
    }
}

final class SentenceSplitterTests: XCTestCase {
    func testSplitsOnTerminatorsAndKeepsWhitespace() {
        let parts = SentenceSplitter.split("Hello world. How are you? Fine!")
        XCTAssertEqual(parts, ["Hello world. ", "How are you? ", "Fine!"])
        XCTAssertEqual(parts.joined(), "Hello world. How are you? Fine!")
    }

    func testDoesNotSplitDecimalsOrUnbalancedMarkup() {
        XCTAssertEqual(SentenceSplitter.split("Pi is 3.14 roughly. Next").count, 2)
        XCTAssertEqual(SentenceSplitter.split("**Note. Both parts** stay together. Then more").count, 2)
        XCTAssertEqual(SentenceSplitter.split("Call `a.b()` now. Done.").count, 2)
    }

    func testKeepsNewlinesAndClosingMarkers() {
        XCTAssertEqual(SentenceSplitter.split("**Done.** Next\nLine two."), ["**Done.** ", "Next\nLine two."])
    }

    func testCompleteness() {
        XCTAssertTrue(SentenceSplitter.isComplete("Done. "))
        XCTAssertTrue(SentenceSplitter.isComplete("Done."))
        XCTAssertTrue(SentenceSplitter.isComplete("Key points:"))
        XCTAssertTrue(SentenceSplitter.isComplete("\"Quoted.\""))
        XCTAssertFalse(SentenceSplitter.isComplete("Half writ"))
    }
}

final class StagedRevealTests: XCTestCase {
    func testStreamingHoldsBackUnfinishedSentenceUntilFinished() {
        XCTAssertEqual(StagedText.prepare("One. Two", finished: false).blocks, [.paragraph(sentences: ["One. "])])
        XCTAssertEqual(StagedText.prepare("One. Two", finished: true).blocks, [.paragraph(sentences: ["One. ", "Two"])])
        XCTAssertEqual(StagedText.prepare("Half writ", finished: false).unitCount, 0)
    }

    func testHeadingWaitsForItsNewlineWhileStreaming() {
        XCTAssertEqual(StagedText.prepare("## Title", finished: false).unitCount, 0)
        XCTAssertEqual(StagedText.prepare("## Title\n", finished: false).unitCount, 1)
        XCTAssertEqual(StagedText.prepare("## Title", finished: true).unitCount, 1)
    }

    func testListItemsAreUnitsAndLastOneIsHeldBack() {
        let streaming = StagedText.prepare("- a\n- b\n- c", finished: false)
        XCTAssertEqual(streaming.unitCount, 2)
        XCTAssertEqual(StagedText.prepare("- a\n- b\n- c\n", finished: false).unitCount, 3)
    }

    func testCodeBlocksAreAlwaysShownEvenWhenOpen() {
        let content = StagedText.prepare("Intro.\n\n```swift\nlet a = 1", finished: false)
        XCTAssertEqual(content.unitCount, 2)
    }

    func testUnitCountMatchesFullReply() {
        let content = StagedText.prepare(DemoDataProbe.sample, finished: true)
        XCTAssertGreaterThan(content.unitCount, 8)
    }

    // MARK: Timing

    func testFirstUnitFadesInOverHalfASecond() {
        let a = StagedText.alphas(eligible: [100], at: 100.25)
        XCTAssertEqual(a[0], 0.5, accuracy: 0.001)
        XCTAssertEqual(StagedText.alphas(eligible: [100], at: 101)[0], 1)
        XCTAssertEqual(StagedText.alphas(eligible: [100], at: 99)[0], 0)
    }

    func testNextUnitStartsWhenPreviousReachesSeventyPercent() {
        // Both available at t=100: unit 0 starts at 100, unit 1 at 100 + 0.5 * 0.7 = 100.35.
        let before = StagedText.alphas(eligible: [100, 100], at: 100.34)
        XCTAssertEqual(before[1], 0, accuracy: 0.001)
        XCTAssertEqual(before[0], 0.68, accuracy: 0.001)
        let after = StagedText.alphas(eligible: [100, 100], at: 100.60)
        XCTAssertEqual(after[1], 0.5, accuracy: 0.001)
    }

    func testAnimationCatchesUpWhenFarBehindTheNetwork() {
        // 20 units all available at t=100 would take 20 * 0.35 = 7 s; the gap shrinks once units wait > 2 s.
        let eligible = [Double](repeating: 100, count: 20)
        let alphas = StagedText.alphas(eligible: eligible, at: 104)
        XCTAssertGreaterThan(alphas.filter { $0 > 0 }.count, 12)
    }

    func testLaterArrivalsAreNotStartedEarly() {
        let a = StagedText.alphas(eligible: [100, 105], at: 103)
        XCTAssertEqual(a[0], 1)
        XCTAssertEqual(a[1], 0)
    }
}

private enum DemoDataProbe {
    static let sample = """
    ## The core idea

    `async` marks a function as suspending. `await` marks a suspension point. Execution may pause there.

    ```swift
    let a = 1
    ```

    Key points:

    - First point
    - Second point
    1. Step one
    2. Step two

    > A quote.

    Final sentence here. And one more.
    """
}

