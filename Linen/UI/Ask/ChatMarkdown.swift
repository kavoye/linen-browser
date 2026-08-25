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
        }
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

        for line in source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
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
