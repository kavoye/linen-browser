// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated struct AgentRequestConstraints: Sendable, Equatable {
    private(set) var forbiddenActions: [String] = []
    private(set) var preference: String?
    private(set) var blocksPurchase = false
    private(set) var request = ""
    private(set) var alternatives: [String] = []

    static let none = Self()
    static let refusalPrefix = "The user asked you not to "
    static let purchaseRefusalPrefix = "The user did not ask you to buy anything."

    static func isRefusal(_ output: String) -> Bool {
        output.hasPrefix(refusalPrefix) || output.hasPrefix(purchaseRefusalPrefix)
    }

    private static let anySubmission: Set<String> = ["send", "submit"]
    private static let ignoredVerbs: Set<String> = ["worry", "forget", "need", "know", "ask", "mind", "use", "have", "let", "change", "touch"]

    private init() {}

    init(request: String) {
        self.request = request
        if Self.matches(#"\b(which|compare|cheaper|cheapest|better|best|faster|closer|bigger|smaller|lighter)\b"#, in: request.lowercased()).isEmpty == false {
            alternatives = Self.matches(#"\b(?:the )?([a-z][a-z0-9-]{2,}) or (?:the )?([a-z][a-z0-9-]{2,})\b"#, in: request.lowercased())
                .first.map { $0.filter { !Self.notAlternatives.contains($0) } } ?? []
        }
        let text = request.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
        for groups in Self.matches(#"\b(?:do not|don't|dont|never|without)\s+([a-z]+)(?:\s+(out|up|off)\b)?"#, in: text) {
            let verb = Self.stem(groups[0])
            guard verb.count >= 3, !Self.ignoredVerbs.contains(verb) else { continue }
            let action = groups[1].isEmpty ? verb : verb + " " + groups[1]
            if !forbiddenActions.contains(action) {
                forbiddenActions.append(action)
            }
        }
        blocksPurchase = Self.matches(#"\b(buy|purchase|pay|order|checkout|check out|book)\b"#, in: text).isEmpty
        preference = Self.matches(#"\bmy (usual|favou?rite|preferred|regular|normal|own) ([a-z]+)"#, in: text).first.map { "my " + $0.joined(separator: " ") }
    }

    func refusal(clicking label: String, submits: Bool, isLink: Bool = false) -> String? {
        let words = label.lowercased()
        let labelWords = Self.words(in: words)
        for action in forbiddenActions {
            let named = Self.names(action, in: labelWords)
            if Self.anySubmission.contains(action) ? submits || named : named {
                return Self.refusalPrefix + "\(action). Nothing was clicked; leave “\(label)” for the user and do not try it again. If the rest of the request is done, answer the user now."
            }
        }
        if blocksPurchase, !isLink, Self.matches(#"\b(check ?out|place (?:my |your |the )?order|buy|pay|purchase|complete (?:my |your |the )?order)\b"#, in: words).first != nil {
            return Self.purchaseRefusalPrefix + " Nothing was clicked; leave “\(label)” for the user and do not try it again. If the rest of the request is done, answer the user now."
        }
        return nil
    }

    func uncoveredAlternative(in answer: String) -> (covered: String, missing: String)? {
        guard alternatives.count == 2 else { return nil }
        let words = Set(answer.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        guard words.isDisjoint(with: Self.comparingWords) else { return nil }
        let covered = alternatives.filter { words.contains($0) }
        guard covered.count == 1, let missing = alternatives.first(where: { !covered.contains($0) }) else { return nil }
        return (Self.name(covered[0]), Self.name(missing))
    }

    func incompleteAnswer(_ answer: String, earlier finding: String? = nil) -> String? {
        guard let gap = uncoveredAlternative(in: answer) else { return nil }
        let opening = "The user asked you to compare \(Self.name(alternatives[0])) and \(Self.name(alternatives[1])), but your answer only covers \(gap.covered). "
        guard let finding else { return opening + "Check \(gap.missing) too, then answer about both." }
        return opening + "Earlier you read this about \(gap.missing):\n<page-content untrusted=\"true\">\n\(finding)\n</page-content>\n"
            + "Answer about both now."
    }

    private static func name(_ word: String) -> String {
        word.prefix(1).uppercased() + word.dropFirst()
    }

    private static let comparingWords: Set<String> = [
        "than", "both", "same", "cheaper", "cheapest", "better", "best", "faster", "fastest", "closer", "closest",
        "bigger", "biggest", "smaller", "smallest", "lighter", "lightest", "more", "less", "lower", "higher",
    ]

    private static let notAlternatives: Set<String> = ["not", "this", "that", "these", "those", "one", "other", "another", "either", "neither", "less", "more"]

    var submissionRefusal: String? {
        forbiddenActions.first { Self.anySubmission.contains($0) }.map {
            Self.refusalPrefix + "\($0). The text was not typed or submitted; type it without submitting."
        }
    }

    private static func words(in text: String) -> [String] {
        text.split { !$0.isLetter }.map(String.init)
    }

    private static func names(_ action: String, in labelWords: [String]) -> Bool {
        let parts = action.split(separator: " ").map(String.init)
        if labelWords.contains(parts.joined()) {
            return true
        }
        guard labelWords.count >= parts.count else { return false }
        return (0...(labelWords.count - parts.count)).contains { start in
            parts.indices.allSatisfy { index in
                let word = labelWords[start + index]
                return word == parts[index] || stem(word) == parts[index] || word == parts[index] + "s"
            }
        }
    }

    private static func stem(_ word: String) -> String {
        guard word.hasSuffix("ing"), word.count > 5 else { return word }
        var stem = String(word.dropLast(3))
        if let last = stem.last, stem.dropLast().last == last, !"aeiouls".contains(last) {
            stem.removeLast()
        }
        return stem
    }

    private static func matches(_ pattern: String, in text: String) -> [[String]] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return expression.matches(in: text, range: range).map { match in
            (1..<match.numberOfRanges).map { index in
                Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
            }
        }
    }
}
