// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WebKit

@testable import Linen

nonisolated final class EvalStore: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    subscript(key: String) -> String? {
        get { lock.withLock { values[key] } }
        set { lock.withLock { values[key] = newValue } }
    }
}

@MainActor
final class EvalContext {
    let site: EvalSite
    var store = EvalStore()
    let browser: BrowserModel
    let toolkit: AgentToolkit
    let tab: BrowserTab
    var answer = ""
    var tools: [String] = []
    var retained: [AnyObject] = []
    var mentioned: [UUID] = []

    init(site: EvalSite, browser: BrowserModel, toolkit: AgentToolkit, tab: BrowserTab) {
        self.site = site
        self.browser = browser
        self.toolkit = toolkit
        self.tab = tab
    }

    func evaluate(_ script: String, in tab: BrowserTab? = nil) async -> Any? {
        try? await (tab ?? browser.activeTab ?? self.tab).webView.evaluateJavaScript(script)
    }

    func load(_ path: String, in tab: BrowserTab? = nil) async {
        let target = tab ?? self.tab
        _ = target.load(site.url(path))
        _ = await PageSettle.untilIdle(target.webView, timeout: .seconds(30))
    }
}

nonisolated struct EvalCheck: Sendable {
    let name: String
    var forbidden = false
    let check: @MainActor @Sendable (EvalContext) async -> Bool

    static func answer(_ tokens: String...) -> Self {
        .init(name: "answer mentions \(tokens.joined(separator: ", "))") { context in
            tokens.allSatisfy { token in
                let spelled = Int(token).flatMap { $0 <= 20 ? numberWords[$0] : nil }
                return context.answer.localizedCaseInsensitiveContains(token)
                    || spelled.map { context.answer.range(of: "\\b\($0)\\b", options: [.regularExpression, .caseInsensitive]) != nil } == true
            }
        }
    }

    private static let numberWords = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
                                      "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty",
                                  ]

    static func request(_ name: String, _ matches: @escaping @Sendable (EvalRequest) -> Bool) -> Self {
        .init(name: name) { context in context.site.requests.contains(where: matches) }
    }

    static func never(_ name: String, _ matches: @escaping @Sendable (EvalRequest) -> Bool) -> Self {
        .init(name: name, forbidden: true) { context in !context.site.requests.contains(where: matches) }
    }

    static func page(_ name: String, _ script: String) -> Self {
        .init(name: name) { context in await context.evaluate(script) as? Bool == true }
    }

    static func browser(_ name: String, _ holds: @escaping @MainActor @Sendable (BrowserModel) -> Bool) -> Self {
        .init(name: name) { context in holds(context.browser) }
    }

    static func stored(_ key: String, _ expected: String) -> Self {
        .init(name: "\(key) is \(expected)") { context in
            context.store[key]?.trimmingCharacters(in: .whitespaces).localizedCaseInsensitiveCompare(expected) == .orderedSame
        }
    }

    static func used(_ tool: String) -> Self {
        .init(name: "used \(tool)") { context in context.tools.contains(tool) }
    }

    static func notUsed(_ tool: String) -> Self {
        .init(name: "did not use \(tool)") { context in !context.tools.contains(tool) }
    }

    static func remembers(_ subject: String, _ value: String) -> Self {
        .init(name: "remembers \(subject) as \(value)") { context in
            context.browser.memory.fact(about: subject)?.value.localizedCaseInsensitiveCompare(value) == .orderedSame
        }
    }

    static func remembersValue(_ value: String) -> Self {
        .init(name: "remembers \(value)") { context in
            context.browser.memory.facts.contains { $0.value.localizedCaseInsensitiveContains(value) || $0.subject.localizedCaseInsensitiveContains(value) }
        }
    }

    static func remembersExactly(_ value: String) -> Self {
        .init(name: "remembers exactly \(value)") { context in
            context.browser.memory.facts.contains { fact in
                fact.value.components(separatedBy: ", ").contains { $0.caseInsensitiveCompare(value) == .orderedSame }
            }
        }
    }

    static let noTools = Self(name: "answered without tools") { context in context.tools.isEmpty }
}

nonisolated struct EvalSearchHit: Sendable {
    let title: String
    let path: String
    let snippet: String
}

nonisolated struct EvalTask: Sendable {
    let id: String
    var version = 1
    var family = ""
    var covers: [String] = []
    var requires: Set<String> = []
    var tags: Set<String> = []
    let instruction: String
    let routes: [String: EvalSite.Handler]
    var stateful: (@Sendable (EvalStore) -> [String: EvalSite.Handler])?
    var start = "/"
    var setup: (@MainActor @Sendable (EvalContext) async throws -> Void)?
    var consent: AgentActionConsent.Decision = .allowOnce
    var siteAccess: AssistantAccessPolicy = .control
    var answers: [String] = []
    var search: [EvalSearchHit] = []
    var upload: (name: String, contents: String)?
    var maxRequests = 15
    var timeout: Duration = .seconds(180)
    let checks: [EvalCheck]

    func inSuite(_ suite: String) -> Self {
        var task = self
        if task.family.isEmpty {
            task.family = suite
        }
        return task
    }

    func instruction(on site: EvalSite) -> String {
        instruction.replacingOccurrences(of: "{site}", with: site.url("").absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }
}
