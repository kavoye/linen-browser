// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation
import os

enum TabOrganizer {
    static var isAvailable: Bool {
        UtilityModelSource.isAvailable
    }

    @Generable
    struct Grouping {
        @Guide(
            description: "One line per group of clearly related tabs: a 1-2 word Title Case name, "
                + "a colon, then the tab numbers separated by commas - like \"Trip Planning: 2, 5\". "
                + "Leave a tab out rather than force it into a group."
        )
        var groups: [String]
    }

    struct Plan: Equatable {
        struct Folder: Equatable {
            let name: String
            let tabIDs: [UUID]
        }

        let folders: [Folder]
    }

    private static let instructions = """
        You organize browser tabs into folders. Given a numbered list of open \
        tab titles, group only the tabs that clearly belong together - a \
        shared site, topic, or task. Two tabs are the smallest group. A tab \
        that fits nowhere stays ungrouped; never invent a miscellaneous \
        group. Answer one line per group: the group's name, a colon, then \
        the numbers of its tabs from the list, separated by commas - like \
        "Trip Planning: 2, 5". Name each group with one or two Title Case \
        words. Never answer in all capitals.
        """

    enum Outcome {
        case plan(Plan)
        case empty
        case failed
    }

    static func propose(for tabs: [(id: UUID, title: String)]) async -> Outcome {
        guard let model = UtilityModelSource.make(), tabs.count >= 2 else { return .failed }
        let list = tabs.enumerated()
            .map { "\($0.offset + 1). \($0.element.title)" }
            .joined(separator: "\n")

        do {
            let session = LanguageModelSession(model: model, instructions: instructions)
            let response = try await session.respond(to: "Open tabs:\n\(list)", generating: Grouping.self)
            let plan = plan(from: groups(in: response.content.groups), tabs: tabs)
            return plan.folders.isEmpty ? .empty : .plan(plan)
        } catch {
            Pipeline.log.error("tab organizing failed: \(String(describing: error), privacy: .public)")
            return .failed
        }
    }

    static func groups(in lines: [String]) -> [(name: String, numbers: [Int])] {
        lines.compactMap { line in
            guard let colon = line.lastIndex(of: ":") else { return nil }
            let name = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let numbers = line[line.index(after: colon)...]
                .split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard !name.isEmpty, numbers.count >= 2 else { return nil }
            return (name, numbers)
        }
    }

    static func plan(
        from groups: [(name: String, numbers: [Int])],
        tabs: [(id: UUID, title: String)]
    ) -> Plan {
        var claimed = Set<Int>()
        var folders: [Plan.Folder] = []
        for group in groups {
            let numbers = Set(group.numbers)
                .sorted()
                .filter { (1...tabs.count).contains($0) && !claimed.contains($0) }
            guard numbers.count >= 2 else { continue }
            claimed.formUnion(numbers)
            folders.append(Plan.Folder(
                name: FolderNamer.sanitize(group.name) ?? String(localized: "New Folder"),
                tabIDs: numbers.map { tabs[$0 - 1].id }
            ))
        }
        return Plan(folders: folders)
    }
}
