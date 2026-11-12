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

final class StreamingMarkdownTests: XCTestCase {
    func testClosesOpenItalicBoldAndInlineCode() {
        XCTAssertEqual(StreamingMarkdown.closeOpenMarkers("a *suspendi"), "a *suspendi*")
        XCTAssertEqual(StreamingMarkdown.closeOpenMarkers("a **bol"), "a **bol**")
        XCTAssertEqual(StreamingMarkdown.closeOpenMarkers("use `aw"), "use `aw`")
        XCTAssertEqual(StreamingMarkdown.closeOpenMarkers("**a** and *b"), "**a** and *b*")
    }

    func testBalancedTextIsUnchanged() {
        for text in ["plain", "*i* **b** `c`", "## Title\n\nbody"] {
            XCTAssertEqual(StreamingMarkdown.closeOpenMarkers(text), text)
        }
    }

    func testListBulletsAndCodeFencesAreNotTreatedAsEmphasis() {
        XCTAssertEqual(StreamingMarkdown.closeOpenMarkers("* one\n* two"), "* one\n* two")
        XCTAssertEqual(StreamingMarkdown.closeOpenMarkers("```swift\nlet a = 2 * 3"), "```swift\nlet a = 2 * 3")
        XCTAssertEqual(StreamingMarkdown.closeOpenMarkers("```\nx * y\n```\ndone *it"), "```\nx * y\n```\ndone *it*")
    }
}

