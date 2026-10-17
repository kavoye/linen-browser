// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WebKit

extension PageDriver {
    nonisolated struct FormControl: Equatable, Sendable {
        let ref: Int
        let label: String
        let kind: String
        let value: String
        var options: [String] = []
    }

    nonisolated struct PendingValue: Equatable, Sendable {
        let ref: Int
        let label: String
        let value: String
        let tool: String
    }

    private static var heldSubmissions: [String] = []

    static func requestValueRefusal(ref: Int, retry: String, in webView: WKWebView, constraints: AgentRequestConstraints) async -> String? {
        guard !constraints.request.isEmpty, let object = await evaluateJSON(scripted("""
            const el = window.__linenRefs[\(ref) - 1];
            const form = el?.form || el?.closest?.('form');
            if (!form) return JSON.stringify({ controls: [] });
            const controls = Array.from(form.querySelectorAll('select, input[type=number]')).filter(c => R.visible(c) && !R.disabled(c)).map(c => ({
              r: c.__linenRef || 0, l: R.labelOf(c, c.tagName === 'SELECT' ? 'select' : 'field'),
              k: c.tagName === 'SELECT' ? 'select' : 'number',
              v: c.tagName === 'SELECT' ? R.norm(c.options[c.selectedIndex]?.text || '') : String(c.value),
              o: c.tagName === 'SELECT' ? Array.from(c.options).map(o => R.norm(o.text)) : []
            }));
            return JSON.stringify({ controls, form: (form.action || '') + '|' + location.href });
            """), in: webView) else { return nil }
        let controls = (object["controls"] as? [[String: Any]] ?? []).compactMap { entry -> FormControl? in
            guard let ref = entry["r"] as? Int, ref > 0, let kind = entry["k"] as? String else { return nil }
            return FormControl(ref: ref, label: entry["l"] as? String ?? "", kind: kind, value: entry["v"] as? String ?? "",
                               options: entry["o"] as? [String] ?? [])
        }
        let pending = pendingValues(request: constraints.request, controls: controls)
        let key = (object["form"] as? String ?? "") + "|" + pending.map { "\($0.ref)=\($0.value)" }.joined(separator: ",")
        guard !pending.isEmpty, !heldSubmissions.contains(key) else { return nil }
        heldSubmissions = Array((heldSubmissions + [key]).suffix(20))
        let steps = pending.map { "“\($0.label)” to \($0.value) (\($0.tool) with ref \($0.ref))" }.joined(separator: ", ")
        return "Nothing was done yet. The request gives values this form is not set to: \(steps). Set them first, then \(retry)."
    }

    nonisolated static func pendingValues(request: String, controls: [FormControl]) -> [PendingValue] {
        let text = request.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
        var used: Set<String> = []
        var pending: [PendingValue] = []
        for control in controls where control.kind == "select" {
            let matches = Set(control.options.filter { option in
                (option.count > 1 || Int(option) != nil) && mentions(option.lowercased(), in: text) || Int(option).map { number in numberWords[number].map { mentions($0, in: text) } ?? false } == true
            })
            guard matches.count == 1, let match = matches.first else { continue }
            used.insert(match)
            if let number = Int(match), let word = numberWords[number] {
                used.insert(word)
            }
            if control.value != match {
                pending.append(PendingValue(ref: control.ref, label: control.label, value: match, tool: "selectOption"))
            }
        }
        let fields = controls.filter { $0.kind == "number" }
        guard fields.count == 1, let field = fields.first else { return pending }
        let money = field.label.lowercased().range(of: #"price|cost|budget|amount"#, options: .regularExpression) != nil
        let numbers = numbersIn(text, money: money).filter { !used.contains($0.text) && (money || $0.value < 1000) }
        guard Set(numbers.map(\.value)).count == 1, let number = numbers.first?.value, field.value != String(number) else { return pending }
        return pending + [PendingValue(ref: field.ref, label: field.label, value: String(number), tool: "typeOnPage")]
    }

    nonisolated private static let numberWords = [
        1: "one", 2: "two", 3: "three", 4: "four", 5: "five", 6: "six", 7: "seven", 8: "eight", 9: "nine", 10: "ten",
    ]

    nonisolated private static func mentions(_ phrase: String, in text: String) -> Bool {
        guard !phrase.isEmpty else { return false }
        let pattern = #"(?<![\w:$])"# + NSRegularExpression.escapedPattern(for: phrase) + #"(?![\w:])"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    nonisolated private static func numbersIn(_ text: String, money: Bool) -> [(text: String, value: Int)] {
        let digits = money ? #"(?<![\w:.,])\$?(\d+)(?![\w:.,]\d)"# : #"(?<![\w:.,$])(\d+)(?![\w:]|[.,]\d)"#
        var found: [(String, Int)] = []
        if let expression = try? NSRegularExpression(pattern: digits) {
            for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range(at: 1), in: text), let value = Int(text[range]) {
                    found.append((String(text[range]), value))
                }
            }
        }
        guard !money else { return found }
        for (value, word) in numberWords where mentions(word, in: text) {
            found.append((word, value))
        }
        return found
    }
}
