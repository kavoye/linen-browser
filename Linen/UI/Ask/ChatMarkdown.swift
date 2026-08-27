// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct ChatMarkdown: View {
    let text: String
    var fontSize: CGFloat = 13
    var spacing: CGFloat = 7
    var joinsWrappedLines = false
    var onOpenLink: ((URL) -> Void)?

    private var blocks: [ChatMarkdownBlock] {
        ChatMarkdownBlock.parse(text, joiningWrappedLines: joinsWrappedLines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(blocks) { block in
                row(block)
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            guard let onOpenLink else { return .systemAction }
            onOpenLink(url)
            return .handled
        })
    }

    @ViewBuilder
    private func row(_ block: ChatMarkdownBlock) -> some View {
        switch block.kind {
        case .heading(let level):
            inline(block.text)
                .font(.system(size: fontSize + (level <= 2 ? 1 : 0), weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)

        case .paragraph:
            inline(block.text)
                .font(.system(size: fontSize))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

        case .bullet(let depth, let mark):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(verbatim: mark)
                    .font(.system(size: fontSize))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()

                inline(block.text)
                    .font(.system(size: fontSize))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, CGFloat(depth) * 14)

        case .code:
            Text(verbatim: block.text)
                .font(.system(size: fontSize - 1, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Theme.Wash.faint, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))

        case .rule:
            RowSeparator()
                .padding(.vertical, 2)

        case .table(let table):
            grid(table)
        }
    }

    private func grid(_ table: ChatMarkdownTable) -> some View {
        Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 0) {
            GridRow {
                ForEach(table.header.indices, id: \.self) { column in
                    cell(table.header[column], in: table, at: column)
                        .font(.system(size: fontSize, weight: .semibold))
                }
            }

            rule(across: table.header.count)

            ForEach(table.rows.indices, id: \.self) { row in
                GridRow {
                    ForEach(table.header.indices, id: \.self) { column in
                        cell(table.cell(row: row, column: column), in: table, at: column)
                            .font(.system(size: fontSize))
                    }
                }

                if row < table.rows.count - 1 {
                    rule(across: table.header.count)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rule(across columns: Int) -> some View {
        Rectangle()
            .fill(Theme.Wash.hairline)
            .frame(height: 1)
            .gridCellUnsizedAxes(.horizontal)
            .gridCellColumns(max(1, columns))
    }

    private func cell(_ text: String, in table: ChatMarkdownTable, at column: Int) -> some View {
        inline(text)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: table.frameAlignment(at: column))
            .padding(.vertical, 8)
            .gridColumnAlignment(table.alignment(at: column))
    }

    private func inline(_ source: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        guard let parsed = try? AttributedString(markdown: source, options: options) else {
            return Text(verbatim: source)
        }
        return Text(parsed)
    }
}

struct ChatMarkdownBlock: Identifiable {
    enum Kind: Equatable {
        case heading(Int)
        case paragraph
        case bullet(depth: Int, mark: String)
        case code
        case rule
        case table(ChatMarkdownTable)
    }

    var id = 0
    let kind: Kind
    let text: String

    static func parse(_ source: String, joiningWrappedLines: Bool = false) -> [ChatMarkdownBlock] {
        var blocks: [ChatMarkdownBlock] = []
        var paragraph: [String] = []
        var code: [String] = []
        var fenced = false
        let join = joiningWrappedLines ? " " : "\n"

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(ChatMarkdownBlock(kind: .paragraph, text: paragraph.joined(separator: join)))
            paragraph = []
        }

        func continuesLastBullet(with line: String) -> Bool {
            guard joiningWrappedLines, paragraph.isEmpty, let last = blocks.last else { return false }
            guard case .bullet = last.kind else { return false }
            blocks.removeLast()
            blocks.append(ChatMarkdownBlock(kind: last.kind, text: last.text + " " + line))
            return true
        }

        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var index = 0
        while index < lines.count {
            let line = lines[index]
            defer { index += 1 }
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if fenced {
                    blocks.append(ChatMarkdownBlock(kind: .code, text: code.joined(separator: "\n")))
                    code = []
                } else {
                    flushParagraph()
                }
                fenced.toggle()
                continue
            }

            if fenced {
                code.append(line)
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                blocks.append(ChatMarkdownBlock(kind: .rule, text: ""))
                continue
            }

            if let heading = heading(in: trimmed) {
                flushParagraph()
                blocks.append(heading)
                continue
            }

            if let bullet = bullet(in: line) {
                flushParagraph()
                blocks.append(bullet)
                continue
            }

            if let table = table(at: index, in: lines) {
                flushParagraph()
                blocks.append(ChatMarkdownBlock(kind: .table(table.value), text: ""))
                index = table.last
                continue
            }

            if continuesLastBullet(with: trimmed) {
                continue
            }

            paragraph.append(trimmed)
        }

        if fenced, !code.isEmpty {
            blocks.append(ChatMarkdownBlock(kind: .code, text: code.joined(separator: "\n")))
        }
        flushParagraph()
        return blocks.enumerated().map { offset, block in
            var stamped = block
            stamped.id = offset
            return stamped
        }
    }

    private static func table(at index: Int, in lines: [String]) -> (value: ChatMarkdownTable, last: Int)? {
        guard index + 1 < lines.count else { return nil }
        let header = lines[index].trimmingCharacters(in: .whitespaces)
        guard header.contains("|") else { return nil }
        let ruled = lines[index + 1].trimmingCharacters(in: .whitespaces)
        guard rulesColumns(ruled) else { return nil }

        let headings = cells(in: header)
        let alignments = cells(in: ruled).map(alignment(of:))
        guard headings.count > 1, alignments.count == headings.count else { return nil }

        var rows: [[String]] = []
        var cursor = index + 2
        while cursor < lines.count {
            let row = lines[cursor].trimmingCharacters(in: .whitespaces)
            guard row.contains("|") else { break }
            rows.append(cells(in: row))
            cursor += 1
        }
        let table = ChatMarkdownTable(header: headings, rows: rows, alignments: alignments)
        return (table, cursor - 1)
    }

    private static func cells(in line: String) -> [String] {
        var text = Substring(line)
        if text.hasPrefix("|") {
            text = text.dropFirst()
        }
        if text.hasSuffix("|") {
            text = text.dropLast()
        }
        return text.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func rulesColumns(_ line: String) -> Bool {
        guard line.contains("|"), line.contains("-") else { return false }
        let parts = cells(in: line)
        guard !parts.isEmpty else { return false }
        return parts.allSatisfy { part in
            part.contains("-") && part.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }

    private static func alignment(of ruled: String) -> ChatMarkdownTable.Side {
        switch (ruled.hasPrefix(":"), ruled.hasSuffix(":")) {
        case (true, true):
            .centre
        case (false, true):
            .trailing
        default:
            .leading
        }
    }

    private static func heading(in line: String) -> ChatMarkdownBlock? {
        var level = 0
        var rest = Substring(line)
        while rest.first == "#", level < 6 {
            level += 1
            rest = rest.dropFirst()
        }
        guard level > 0, rest.first == " " else { return nil }
        return ChatMarkdownBlock(
            kind: .heading(level),
            text: String(rest.drop(while: { $0 == " " }))
        )
    }

    private static func bullet(in line: String) -> ChatMarkdownBlock? {
        let indent = line.prefix { $0 == " " || $0 == "\t" }.count
        let depth = min(indent / 2, 3)
        var rest = Substring(line.trimmingCharacters(in: .whitespaces))

        if let first = rest.first, first == "-" || first == "*" || first == "+" {
            rest = rest.dropFirst()
            guard rest.first == " " else { return nil }
            return ChatMarkdownBlock(
                kind: .bullet(depth: depth, mark: "•"),
                text: String(rest.drop(while: { $0 == " " }))
            )
        }

        let digits = rest.prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        rest = rest.dropFirst(digits.count)
        guard rest.first == "." || rest.first == ")" else { return nil }
        rest = rest.dropFirst()
        guard rest.first == " " else { return nil }
        return ChatMarkdownBlock(
            kind: .bullet(depth: depth, mark: "\(digits)."),
            text: String(rest.drop(while: { $0 == " " }))
        )
    }
}

struct ChatMarkdownTable: Equatable {
    enum Side: Equatable {
        case leading
        case centre
        case trailing
    }

    let header: [String]
    let rows: [[String]]
    let alignments: [Side]

    func cell(row: Int, column: Int) -> String {
        guard rows.indices.contains(row), rows[row].indices.contains(column) else { return "" }
        return rows[row][column]
    }

    func alignment(at column: Int) -> HorizontalAlignment {
        switch side(at: column) {
        case .leading:
            .leading
        case .centre:
            .center
        case .trailing:
            .trailing
        }
    }

    func frameAlignment(at column: Int) -> Alignment {
        switch side(at: column) {
        case .leading:
            .leading
        case .centre:
            .center
        case .trailing:
            .trailing
        }
    }

    private func side(at column: Int) -> Side {
        alignments.indices.contains(column) ? alignments[column] : .leading
    }
}
