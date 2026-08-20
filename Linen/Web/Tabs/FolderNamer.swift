// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation
import os

enum FolderNamer {
    static var isAvailable: Bool {
        UtilityModelSource.isAvailable
    }

    @Generable
    struct Suggestion {
        @Guide(description: "A 1-2 word label for this group of pages, in Title Case - \"Some Word\", never \"SOME WORD\". No punctuation, no quotes.")
        var name: String
    }

    private static let instructions = """
        You name folders of browser tabs. Given the page titles in a folder, \
        reply with the shortest label a person would use for that group: \
        the shared topic, product, or task. One or two words in Title Case - \
        capitalize the first letter of each word and lowercase the rest, \
        like "Trip Planning". Never answer in all capitals. \
        Never echo a full page title, never mention "tabs" or "folder".
        """

    static func suggestName(forTitles titles: [String]) async -> String? {
        guard let model = UtilityModelSource.make() else { return nil }
        let usable = titles
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != BrowserTab.placeholderTitle }
            .prefix(6)
        guard !usable.isEmpty else { return nil }

        let prompt = "Pages in this folder:\n" + usable.map { "- \($0)" }.joined(separator: "\n")

        do {
            let session = LanguageModelSession(model: model, instructions: instructions)
            let response = try await session.respond(to: prompt, generating: Suggestion.self)
            return sanitize(response.content.name)
        } catch {
            Pipeline.log.error("folder naming failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    static func sanitize(_ raw: String) -> String? {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”.,:;-–-"))
        name = name.replacingOccurrences(of: "\n", with: " ")
        guard !name.isEmpty, name.count <= 28, name.split(separator: " ").count <= 3 else { return nil }
        return unshouted(name)
    }

    private static func unshouted(_ name: String) -> String {
        guard !name.contains(where: \.isLowercase) else { return name }
        return name
            .split(separator: " ")
            .map { $0.count > 3 ? $0.localizedCapitalized : String($0) }
            .joined(separator: " ")
    }
}
