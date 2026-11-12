import SwiftUI

// MARK: - Parser (pure, unit-tested)

struct MarkdownListItem: Equatable {
    var indent: Int
    var marker: String
    var text: String
}

enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case code(language: String?, code: String)
    case list([MarkdownListItem])
    case quote(String)
    case table([[String]])
    case rule
}

/// Small block-level Markdown parser for chat replies: headings, fenced code, lists, quotes, tables, rules.
/// Inline formatting (bold, italic, `code`, links) is handled later by `InlineMarkdown`.
/// An unterminated code fence (a reply still streaming) is returned as an open code block.
enum MarkdownParser {
    static func parse(_ text: String) -> [MarkdownBlock] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var i = 0

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: "\n")))
                paragraph = []
            }
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flushParagraph()
                let fence = String(trimmed.prefix(3))
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    code.append(lines[i])
                    i += 1
                }
                i += 1 // closing fence (or end of input)
                blocks.append(.code(language: language.isEmpty ? nil : language, code: code.joined(separator: "\n")))
                continue
            }

            if trimmed.isEmpty { flushParagraph(); i += 1; continue }

            if let heading = parseHeading(trimmed) {
                flushParagraph(); blocks.append(heading); i += 1; continue
            }

            if isRule(trimmed) {
                flushParagraph(); blocks.append(.rule); i += 1; continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                var quoted: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    var l = lines[i].trimmingCharacters(in: .whitespaces)
                    l.removeFirst()
                    quoted.append(l.trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                blocks.append(.quote(quoted.joined(separator: "\n")))
                continue
            }

            if trimmed.hasPrefix("|") {
                flushParagraph()
                var rows: [[String]] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    let cells = splitRow(lines[i])
                    if !cells.allSatisfy(isSeparatorCell) { rows.append(cells) }
                    i += 1
                }
                blocks.append(.table(rows))
                continue
            }

            if parseListItem(line) != nil {
                flushParagraph()
                var items: [MarkdownListItem] = []
                while i < lines.count, let item = parseListItem(lines[i]) {
                    items.append(item)
                    i += 1
                }
                blocks.append(.list(items))
                continue
            }

            paragraph.append(trimmed)
            i += 1
        }
        flushParagraph()
        return blocks
    }

    // MARK: Helpers

    private static func parseHeading(_ trimmed: String) -> MarkdownBlock? {
        let hashes = trimmed.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let rest = trimmed.dropFirst(hashes)
        guard rest.first == " " else { return nil }
        return .heading(level: hashes, text: rest.trimmingCharacters(in: .whitespaces))
    }

    private static func isRule(_ trimmed: String) -> Bool {
        let compact = trimmed.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3, let first = compact.first, "-*_".contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    private static let listRegex = try! NSRegularExpression(pattern: #"^(\s*)([-*+]|\d+[.)])\s+(.*)$"#)

    static func parseListItem(_ line: String) -> MarkdownListItem? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = listRegex.firstMatch(in: line, range: range), match.numberOfRanges == 4,
              let indentRange = Range(match.range(at: 1), in: line),
              let markerRange = Range(match.range(at: 2), in: line),
              let textRange = Range(match.range(at: 3), in: line) else { return nil }
        let indent = line[indentRange].reduce(0) { $0 + ($1 == "\t" ? 2 : 1) } / 2
        let rawMarker = String(line[markerRange])
        let isBullet = "-*+".contains(rawMarker)
        let marker = isBullet ? (indent == 0 ? "•" : "◦") : (rawMarker.dropLast() + ".")
        return MarkdownListItem(indent: indent, marker: String(marker), text: String(line[textRange]))
    }

    private static func splitRow(_ line: String) -> [String] {
        var cells = line.trimmingCharacters(in: .whitespaces).components(separatedBy: "|").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        if cells.first == "" { cells.removeFirst() }
        if cells.last == "" { cells.removeLast() }
        return cells
    }

    private static func isSeparatorCell(_ cell: String) -> Bool {
        let core = cell.trimmingCharacters(in: CharacterSet(charactersIn: ": "))
        return core.count >= 1 && core.allSatisfy { $0 == "-" }
    }
}

// MARK: - Inline styling

enum InlineMarkdown {
    /// Bold / italic / links via Foundation's Markdown parser; inline `code` gets a monospaced chip look.
    /// `alpha` < 1 fades the whole text (used by the staged reveal).
    static func attributed(_ text: String, size: CGFloat = 16, alpha: Double = 1) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        var result = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
        let codeRuns = result.runs.compactMap { run in
            run.inlinePresentationIntent?.contains(.code) == true ? run.range : nil
        }
        for range in codeRuns {
            result[range].font = .system(size: size - 1.5, design: .monospaced)
            result[range].backgroundColor = Color.primary.opacity(0.12 * alpha)
        }
        if alpha < 1 { result.foregroundColor = Color.primary.opacity(alpha) }
        return result
    }
}

// MARK: - Syntax highlighting

enum CodeTheme {
    static let background = Color(red: 0.10, green: 0.11, blue: 0.14)
    static let header = Color.white.opacity(0.07)
    static let text = Color(red: 0.90, green: 0.93, blue: 0.96)
    static let muted = Color(red: 0.55, green: 0.59, blue: 0.64)
    static let keyword = Color(red: 1.00, green: 0.48, blue: 0.45)
    static let type = Color(red: 0.82, green: 0.66, blue: 1.00)
    static let string = Color(red: 0.65, green: 0.84, blue: 1.00)
    static let number = Color(red: 0.47, green: 0.75, blue: 1.00)
    static let comment = Color(red: 0.55, green: 0.59, blue: 0.64)
}

/// Lightweight, language-agnostic highlighter (keywords, types, strings, numbers, comments).
enum SyntaxHighlighter {
    private static let plainLanguages: Set<String> = ["text", "txt", "plain", "plaintext", "output", "console"]
    private static let hashCommentLanguages: Set<String> = ["python", "py", "sh", "bash", "zsh", "shell", "ruby", "rb", "yaml", "yml", "toml", "r"]

    private static let keywords = try! NSRegularExpression(pattern: #"\b(func|let|var|if|else|for|while|return|import|class|struct|enum|protocol|extension|guard|switch|case|default|try|await|async|throws|throw|catch|do|in|is|as|nil|true|false|self|super|static|private|public|internal|final|override|init|def|lambda|pass|from|with|None|True|False|elif|except|finally|raise|yield|const|function|new|this|null|undefined|export|typeof|interface|type|package|go|defer|chan|map|range|select|void|int|string|bool|float|double|fun|val|object|when|abstract|extends|implements|using|namespace|fn|mut|impl|pub|use|mod|match|loop|break|continue|where|some|any|actor|await|inout|weak|lazy|and|or|not|print)\b"#)
    private static let types = try! NSRegularExpression(pattern: #"\b[A-Z][A-Za-z0-9_]*\b"#)
    private static let numbers = try! NSRegularExpression(pattern: #"\b\d+(\.\d+)?\b"#)
    private static let strings = try! NSRegularExpression(pattern: #""(\\.|[^"\\\n])*"|'(\\.|[^'\\\n])*'"#)
    private static let slashComments = try! NSRegularExpression(pattern: #"//[^\n]*|/\*[\s\S]*?(\*/|$)"#)
    private static let hashComments = try! NSRegularExpression(pattern: #"#[^\n]*"#)

    static func highlight(_ code: String, language: String?) -> AttributedString {
        var out = AttributedString(code)
        out.foregroundColor = CodeTheme.text
        let lang = language?.lowercased() ?? ""
        guard !plainLanguages.contains(lang), !code.isEmpty else { return out }

        // Later passes paint over earlier ones: numbers/types/keywords < strings < comments.
        paint(types, CodeTheme.type, in: code, on: &out)
        paint(numbers, CodeTheme.number, in: code, on: &out)
        paint(keywords, CodeTheme.keyword, in: code, on: &out)
        paint(strings, CodeTheme.string, in: code, on: &out)
        paint(slashComments, CodeTheme.comment, in: code, on: &out)
        if hashCommentLanguages.contains(lang) { paint(hashComments, CodeTheme.comment, in: code, on: &out) }
        return out
    }

    private static func paint(_ regex: NSRegularExpression, _ color: Color, in code: String, on out: inout AttributedString) {
        let full = NSRange(code.startIndex..., in: code)
        for match in regex.matches(in: code, range: full) {
            if let range = Range(match.range, in: out) {
                out[range].foregroundColor = color
            }
        }
    }
}

// MARK: - Views

/// Renders a full assistant reply as styled blocks.
struct MarkdownView: View {
    let text: String

    var body: some View {
        let blocks = MarkdownParser.parse(text)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                BlockView(block: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BlockView: View {
    let block: MarkdownBlock

    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(InlineMarkdown.attributed(text, size: headingSize(level)))
                .font(.system(size: headingSize(level), weight: level <= 2 ? .bold : .semibold, design: .rounded))
                .padding(.top, level <= 2 ? 4 : 0)
        case .paragraph(let text):
            Text(InlineMarkdown.attributed(text))
                .font(.system(size: 16))
                .lineSpacing(3)
        case .code(let language, let code):
            CodeBlockView(language: language, code: code)
        case .list(let items):
            ListBlockView(items: items, alphas: nil)
        case .quote(let text):
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(Color.accentColor.opacity(0.7)).frame(width: 3)
                Text(InlineMarkdown.attributed(text))
                    .font(.system(size: 15).italic())
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .table(let rows):
            TableBlockView(rows: rows)
        case .rule:
            Divider().padding(.vertical, 4)
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: 24
        case 2: 20
        case 3: 18
        default: 16
        }
    }
}

struct CodeBlockView: View {
    let language: String?
    let code: String
    @Environment(Toast.self) private var toast
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text((language ?? "code").lowercased())
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(CodeTheme.muted)
                Spacer()
                Button(action: copy) {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(copied ? Color.green : CodeTheme.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy code")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(CodeTheme.header)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(SyntaxHighlighter.highlight(code, language: language))
                    .font(.system(size: 13, design: .monospaced))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .background(CodeTheme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func copy() {
        Clipboard.copy(code)
        toast.show("Code copied")
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}

private struct TableBlockView: View {
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            grid
        }
    }

    private var grid: some View {
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                tableRow(rowIndex)
            }
        }
        .overlay(border)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.border, lineWidth: 1)
    }

    @ViewBuilder
    private func tableRow(_ rowIndex: Int) -> some View {
        let row = rows[rowIndex]
        GridRow {
            ForEach(row.indices, id: \.self) { column in
                cell(row[column], isHeader: rowIndex == 0)
            }
        }
        Divider().gridCellUnsizedAxes(.horizontal)
    }

    private func cell(_ text: String, isHeader: Bool) -> some View {
        let background: Color = isHeader ? Theme.fill : Color.clear
        let weight: Font.Weight = isHeader ? .semibold : .regular
        return Text(InlineMarkdown.attributed(text, size: 14))
            .font(.system(size: 14, weight: weight))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(minWidth: 70, alignment: .leading)
            .background(background)
    }
}

struct ListBlockView: View {
    let items: [MarkdownListItem]
    /// Optional per-item opacity (staged reveal). Items with opacity 0 are not laid out.
    let alphas: [Double]?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items.indices, id: \.self) { index in
                let alpha = alphas?[index] ?? 1
                if alpha > 0 {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(items[index].marker)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                            .frame(minWidth: 18, alignment: .trailing)
                        Text(InlineMarkdown.attributed(items[index].text))
                            .font(.system(size: 16))
                            .lineSpacing(3)
                    }
                    .padding(.leading, CGFloat(items[index].indent) * 16)
                    .opacity(alpha)
                }
            }
        }
    }
}

/// Renders a reply that is being revealed sentence by sentence: every unit fades from 0 to 1; units that have
/// not started yet are not laid out. `alphas` is indexed by unit, in reading order.
struct StagedMarkdownView: View {
    let content: StagedContent
    let alphas: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                entry.view
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private struct Entry {
        let view: AnyView
    }

    private var entries: [Entry] {
        var result: [Entry] = []
        var unit = 0
        for block in content.blocks {
            let count = block.unitCount
            let slice = (0..<count).map { unit + $0 < alphas.count ? alphas[unit + $0] : 0 }
            unit += count
            switch block {
            case .paragraph(let sentences):
                guard slice.contains(where: { $0 > 0 }) else { continue }
                var text = AttributedString()
                for (sentence, alpha) in zip(sentences, slice) where alpha > 0 {
                    text += InlineMarkdown.attributed(sentence, alpha: alpha)
                }
                result.append(Entry(view: AnyView(Text(text).font(.system(size: 16)).lineSpacing(3))))
            case .list(let items):
                guard slice.contains(where: { $0 > 0 }) else { continue }
                result.append(Entry(view: AnyView(ListBlockView(items: items, alphas: slice))))
            case .other(let other):
                guard let alpha = slice.first, alpha > 0 else { continue }
                result.append(Entry(view: AnyView(BlockView(block: other).opacity(alpha))))
            }
        }
        return result
    }
}

