// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Testing

@testable import Linen

/// Release notes join wrapped lines, and a blank line still has to end a
/// bullet: the paragraph after a list is not part of the list's last item.
struct ChatMarkdownJoinTests {
    @Test func aParagraphAfterABlankLineDoesNotJoinTheLastBullet() throws {
        let source = "- one\n- two\n\n**Full Changelog**: https://example.com/compare"

        let blocks = ChatMarkdownBlock.parse(source, joiningWrappedLines: true)

        #expect(blocks.count == 3)
        let last = try #require(blocks.last)
        #expect(last.kind == .paragraph)
        #expect(last.text.hasPrefix("**Full Changelog**"))
        #expect(!(blocks.dropLast().last?.text.contains("Changelog") ?? true))
    }

    @Test func aWrappedLineStillJoinsItsBullet() {
        let source = "- a bullet that\n  wraps onto the next line"

        let blocks = ChatMarkdownBlock.parse(source, joiningWrappedLines: true)

        #expect(blocks.count == 1)
        #expect(blocks.first?.text == "a bullet that wraps onto the next line")
    }

    /// GitHub's API sends CRLF line endings; the blank line between the list
    /// and the closing paragraph must still count.
    @Test func gitHubLineEndingsBehaveTheSame() throws {
        let source = "- one\r\n- two\r\n\r\nAfter the list"

        let blocks = ChatMarkdownBlock.parse(source, joiningWrappedLines: true)

        #expect(blocks.count == 3)
        let last = try #require(blocks.last)
        #expect(last.kind == .paragraph)
        #expect(last.text == "After the list")
    }
}
