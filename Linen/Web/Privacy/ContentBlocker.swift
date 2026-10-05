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

    private let identifier = "Linen.trackers." + UUID().uuidString
    private let settings: BrowserSettings
    private let persists: Bool
    private let ruleStore: WKContentRuleListStore?
    private let temporaryDirectory: URL?
    private var sessionEnded = false
    private(set) var isCompiling = false
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

    init(
        defaults: UserDefaults = .standard,
        settings: BrowserSettings = .shared,
        persists: Bool = true,
        ruleStore: WKContentRuleListStore? = nil
    ) {
        self.defaults = defaults
        self.settings = settings
        self.persists = persists
        if let ruleStore {
            self.ruleStore = ruleStore
            temporaryDirectory = nil
        } else if persists {
            self.ruleStore = .default()
            temporaryDirectory = nil
        } else {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("Linen-private-rules-" + UUID().uuidString, isDirectory: true)
            temporaryDirectory = directory
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                self.ruleStore = WKContentRuleListStore(url: directory)
            } catch {
                self.ruleStore = nil
            }
        }
        exemptHosts = Set(
            defaults.stringArray(forKey: Self.exemptDefaultsKey) ?? []
        )
    }

    deinit {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    // MARK: - Compiling

    func refresh() {
        guard !sessionEnded else { return }
        let previous = compileTask
        previous?.cancel()
        guard settings.blocksTrackers else {
            removeFromAll()
            return
        }
        compileTask = Task { [weak self] in
            await previous?.value
            guard !Task.isCancelled else { return }
            await self?.compile()
        }
    }

    func waitForPendingCompilation() async {
        await compileTask?.value
    }

    func endPrivateSession() async {
        guard !persists else { return }
        sessionEnded = true
        compileTask?.cancel()
        await compileTask?.value
        compileTask = nil
        removeFromAll()
        ruleList = nil
        exemptHosts = []
        if let ruleStore {
            try? await ruleStore.removeContentRuleList(forIdentifier: identifier)
        }
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    private func compile() async {
        guard let ruleStore, !sessionEnded,
              let json = Self.rulesJSON(exemptHosts: exemptHosts) else { return }
        isCompiling = true
        defer { isCompiling = false }
        do {
            let compiled: WKContentRuleList? = try await ruleStore
                .compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json)
            // WebKit retains the live rule object; the private compiled cache is unnecessary.
            // Remove it before checking cancellation, which does not cancel WebKit's compilation.
            if !persists {
                try await ruleStore.removeContentRuleList(forIdentifier: identifier)
            }
            guard !Task.isCancelled, !sessionEnded, let compiled else { return }
            ruleList = compiled
            for controller in controllers.allObjects {
                controller.remove(compiled)
                controller.add(compiled)
            }
            Pipeline.log.notice("content blocking: \(TrackerList.domains.count, privacy: .public) rules compiled")
        } catch {
            if !persists {
                try? await ruleStore.removeContentRuleList(forIdentifier: identifier)
            }
            Pipeline.log.error("content blocking: compile failed")
        }
    }

    func apply(to controller: WKUserContentController) {
        controllers.add(controller)
        guard settings.blocksTrackers, let ruleList else { return }
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
        if persists {
            defaults.set(Array(exemptHosts).sorted(), forKey: Self.exemptDefaultsKey)
        }
        refresh()
    }

    func forgetExceptions() {
        guard !exemptHosts.isEmpty else { return }
        exemptHosts = []
        if persists {
            defaults.removeObject(forKey: Self.exemptDefaultsKey)
        }
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

        rules.append([
            "trigger": [
                "url-filter": ".*",
                "resource-type": ["document"],
                "load-context": ["top-frame"],
            ],
            "action": ["type": "ignore-previous-rules"],
        ])

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
