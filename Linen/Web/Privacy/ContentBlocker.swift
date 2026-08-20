// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation
import os
import WebKit

@MainActor
@Observable
final class ContentBlocker {
    static let shared = ContentBlocker()

    @ObservationIgnored private(set) var ruleList: WKContentRuleList?

    private(set) var exemptHosts: Set<String> = []

    @ObservationIgnored private var controllers = NSHashTable<WKUserContentController>.weakObjects()

    @ObservationIgnored private var compileTask: Task<Void, Never>?

    private static let identifier = "Linen.trackers"
    private static let exemptDefaultsKey = "content.blockerExceptions"

    @ObservationIgnored private var defaults: UserDefaults = .standard

    func use(defaults: UserDefaults) {
        guard defaults !== self.defaults else { return }
        self.defaults = defaults
        exemptHosts = Set(
            (defaults.stringArray(forKey: Self.exemptDefaultsKey) ?? []).map(Self.normalized)
        )
        refresh()
    }

    private init() {
        exemptHosts = Set(
            defaults.stringArray(forKey: Self.exemptDefaultsKey) ?? []
        )
    }

    // MARK: - Compiling

    func refresh() {
        compileTask?.cancel()
        guard BrowserSettings.shared.blocksTrackers else {
            removeFromAll()
            return
        }
        compileTask = Task { [weak self] in
            await self?.compile()
        }
    }

    private func compile() async {
        guard let json = Self.rulesJSON(exemptHosts: exemptHosts) else { return }
        do {
            let compiled = try await WKContentRuleListStore.default()?
                .compileContentRuleList(forIdentifier: Self.identifier, encodedContentRuleList: json)
            guard !Task.isCancelled, let compiled else { return }
            ruleList = compiled
            for controller in controllers.allObjects {
                controller.remove(compiled)
                controller.add(compiled)
            }
            Pipeline.log.notice("content blocking: \(TrackerList.domains.count, privacy: .public) rules compiled")
        } catch {
            Pipeline.log.error("content blocking: compile failed: \(error, privacy: .public)")
        }
    }

    func apply(to controller: WKUserContentController) {
        controllers.add(controller)
        guard BrowserSettings.shared.blocksTrackers, let ruleList else { return }
        controller.add(ruleList)
    }

    private func removeFromAll() {
        guard let ruleList else { return }
        for controller in controllers.allObjects {
            controller.remove(ruleList)
        }
    }

    // MARK: - Per-website exceptions

    func isExempt(_ host: String) -> Bool {
        exemptHosts.contains(Self.normalized(host))
    }

    func setExempt(_ exempt: Bool, for host: String) {
        let host = Self.normalized(host)
        guard !host.isEmpty else { return }
        let changed = exempt ? exemptHosts.insert(host).inserted : exemptHosts.remove(host) != nil
        guard changed else { return }
        defaults.set(Array(exemptHosts).sorted(), forKey: Self.exemptDefaultsKey)
        refresh()
    }

    func forgetExceptions() {
        guard !exemptHosts.isEmpty else { return }
        exemptHosts = []
        defaults.removeObject(forKey: Self.exemptDefaultsKey)
        refresh()
    }

    static func normalized(_ host: String) -> String {
        var host = host.lowercased()
        if host.hasPrefix("www.") {
            host.removeFirst(4)
        }
        return host
    }

    // MARK: - Rules

    static func rulesJSON(exemptHosts: Set<String>) -> String? {
        var rules: [[String: Any]] = TrackerList.domains.map { domain in
            [
                "trigger": [
                    "url-filter": TrackerList.filter(for: domain),
                    "load-type": ["third-party"],
                ],
                "action": ["type": "block"],
            ]
        }

        if !exemptHosts.isEmpty {
            rules.append([
                "trigger": [
                    "url-filter": ".*",
                    "if-domain": exemptHosts.sorted().map { "*\($0)" },
                ],
                "action": ["type": "ignore-previous-rules"],
            ])
        }

        guard let data = try? JSONSerialization.data(withJSONObject: rules) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
