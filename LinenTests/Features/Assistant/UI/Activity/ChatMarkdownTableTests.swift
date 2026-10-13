// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Testing

@testable import Linen

/// A table is only a table when the line under its first row rules the
/// columns off. Everything else that carries a pipe stays prose.
struct ChatMarkdownTableTests {
    private func read(_ source: String) -> ChatMarkdownTable? {
        for block in ChatMarkdownBlock.parse(source) {
            if case .table(let table) = block.kind {
                return table
            }
        }
        return nil
    }

    @Test func aRuledTableIsRead() throws {
        let source = """
            | Engine | Kind |
            | --- | --- |
            | DuckDuckGo | private |
            | Google | familiar |
            """

        let table = try #require(read(source))

        #expect(table.header == ["Engine", "Kind"])
        #expect(table.rows.count == 2)
        #expect(table.cell(row: 1, column: 0) == "Google")
    }

    @Test func theRuleSaysWhichWayAColumnLeans() throws {
        let source = """
            | Left | Middle | Right |
            |:--- |:---:| ---:|
            | a | b | c |
            """

        let table = try #require(read(source))

        #expect(table.alignments == [.leading, .centre, .trailing])
    }

    /// A row that is short or long is not a reason to lose the table.
    @Test func aRaggedRowIsReadAsFarAsItGoes() throws {
        let source = """
            | One | Two | Three |
            | --- | --- | --- |
            | a | b |
            """

        let table = try #require(read(source))

        #expect(table.cell(row: 0, column: 1) == "b")
        #expect(table.cell(row: 0, column: 2).isEmpty)
        #expect(table.cell(row: 9, column: 9).isEmpty)
    }

    @Test func proseWithAPipeStaysProse() {
        #expect(read("run `a | b` to pipe it") == nil)
        #expect(read("| just | one row |") == nil)
    }

    /// A table sits among the rest of the answer, and what follows it has to
    /// be read as its own block rather than swallowed.
    @Test func whatFollowsATableIsReadAfterIt() {
        let blocks = ChatMarkdownBlock.parse("""
            | A | B |
            | --- | --- |
            | 1 | 2 |

            After the table.
            """)

        #expect(blocks.count == 2)
        #expect(blocks.last?.text == "After the table.")
        if case .paragraph = blocks.last?.kind {} else {
            Issue.record("the line after a table is a paragraph")
        }
    }
}
