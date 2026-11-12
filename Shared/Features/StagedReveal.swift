import Foundation

// Pure logic behind the "answering sentence by sentence" reveal. UI lives in `StagedMarkdownView`.

enum SentenceSplitter {
    private static let terminators: Set<Character> = [".", "!", "?", "…"]
    private static let closers: Set<Character> = ["\"", "'", ")", "]", "”", "’", "*", "_"]

    /// Splits prose into sentences, each keeping its trailing whitespace so joining them restores the text.
    /// Does not split on decimals ("3.14"), or inside an unbalanced `code` / *emphasis* span.
    nonisolated static func split(_ text: String) -> [String] {
        let chars = Array(text)
        var sentences: [String] = []
        var current = ""
        var inCode = false
        var bold = false
        var italic = false
        var i = 0

        /// Appends a run of asterisks starting at `index` and updates the emphasis state; returns the run length.
        func consumeAsterisks(at index: Int) -> Int {
            var run = 0
            while index + run < chars.count, chars[index + run] == "*" { run += 1 }
            current.append(String(repeating: "*", count: run))
            if run == 1 { italic.toggle() } else if run == 2 { bold.toggle() } else { bold.toggle(); italic.toggle() }
            return run
        }

        while i < chars.count {
            let c = chars[i]
            if c == "*" { i += consumeAsterisks(at: i); continue }
            current.append(c)
            if c == "`" { inCode.toggle() }
            guard terminators.contains(c) else { i += 1; continue }

            var j = i + 1
            while j < chars.count, terminators.contains(chars[j]) || closers.contains(chars[j]) {
                if chars[j] == "*" { j += consumeAsterisks(at: j); continue }
                if chars[j] == "`" { inCode.toggle() }
                current.append(chars[j])
                j += 1
            }
            let atEnd = j >= chars.count
            if (atEnd || chars[j].isWhitespace), !inCode, !bold, !italic {
                while j < chars.count, chars[j].isWhitespace {
                    current.append(chars[j])
                    j += 1
                }
                sentences.append(current)
                current = ""
            }
            i = j
        }
        if !current.isEmpty { sentences.append(current) }
        return sentences
    }

    /// True if the sentence is finished (ends with terminal punctuation, a colon, or trailing whitespace).
    nonisolated static func isComplete(_ sentence: String) -> Bool {
        if sentence.last?.isWhitespace == true { return true }
        var trimmed = Substring(sentence)
        while let last = trimmed.last, closers.contains(last) || last == "`" { trimmed.removeLast() }
        guard let last = trimmed.last else { return false }
        return terminators.contains(last) || last == ":"
    }
}

/// A piece of a reply as the staged view renders it. Every sentence / list item / other block is one "unit".
enum StagedBlock: Equatable {
    case paragraph(sentences: [String])
    case list([MarkdownListItem])
    case other(MarkdownBlock)

    nonisolated var unitCount: Int {
        switch self {
        case .paragraph(let sentences): sentences.count
        case .list(let items): items.count
        case .other: 1
        }
    }
}

struct StagedContent: Equatable {
    var blocks: [StagedBlock]
    nonisolated var unitCount: Int { blocks.reduce(0) { $0 + $1.unitCount } }
}

enum StagedText {
    /// Fade-in duration of one unit, and the progress at which the next unit starts fading in.
    nonisolated static let fadeDuration = 0.5
    nonisolated static let overlapAt = 0.7

    /// Splits the text received so far into units. While the reply is still streaming, the unfinished tail
    /// (a half-written sentence, heading, or list item) is held back until it is complete.
    nonisolated static func prepare(_ text: String, finished: Bool) -> StagedContent {
        let blocks = MarkdownParser.parse(text)
        let endsWithNewline = text.hasSuffix("\n")
        var result: [StagedBlock] = []

        for (index, block) in blocks.enumerated() {
            let isLast = index == blocks.count - 1
            let complete = finished || !isLast
            switch block {
            case .paragraph(let paragraph):
                var sentences = SentenceSplitter.split(paragraph)
                if !complete, let last = sentences.last, !SentenceSplitter.isComplete(last) { sentences.removeLast() }
                if !sentences.isEmpty { result.append(.paragraph(sentences: sentences)) }
            case .list(var items):
                if !complete, !endsWithNewline { items.removeLast() }
                if !items.isEmpty { result.append(.list(items)) }
            case .heading, .quote, .table:
                if complete || endsWithNewline { result.append(.other(block)) }
            case .code, .rule:
                result.append(.other(block))
            }
        }
        return StagedContent(blocks: result)
    }

    /// Opacity (0...1) of every unit at time `now`. `eligible[i]` is when unit i became available.
    /// Unit i starts fading in once unit i-1 has reached `overlapAt`; if the reply is far ahead of the
    /// animation (> 2 s of waiting) the gap shrinks so the animation can catch up.
    nonisolated static func alphas(eligible: [Double], at now: Double) -> [Double] {
        var result: [Double] = []
        var previousStart: Double?
        for available in eligible {
            var start = available
            if let previousStart {
                var ready = previousStart + fadeDuration * overlapAt
                if ready - available > 2.0 { ready = previousStart + 0.1 }
                start = max(available, ready)
            }
            previousStart = start
            result.append(min(1, max(0, (now - start) / fadeDuration)))
        }
        return result
    }
}
