// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated enum ExtensionCompatibility {
    struct Report: Equatable, Sendable {
        var namespaces: [String] = []
        var members: [String] = []

        var isEmpty: Bool {
            namespaces.isEmpty && members.isEmpty
        }

        var names: [String] {
            namespaces + members
        }

        var summaries: [String] {
            var events: [String: [String]] = [:]
            for member in members {
                let parts = member.split(separator: ".", maxSplits: 1)
                guard parts.count == 2 else { continue }
                events[String(parts[0]), default: []].append(String(parts[1]))
            }
            let grouped = events.keys.sorted().map { namespace in
                "\(namespace): \((events[namespace] ?? []).sorted().joined(separator: ", "))"
            }
            return namespaces + grouped
        }
    }

    static let unsupportedMembers: Set<String> = [
        "runtime.onSuspend",
        "runtime.onUpdateAvailable",
        "tabs.onZoomChange",
        "webNavigation.onCreatedNavigationTarget",
        "webNavigation.onHistoryStateUpdated",
        "webNavigation.onReferenceFragmentUpdated",
        "webNavigation.onTabReplaced",
    ]

    static let membersMeasuredThroughMacOS = 26

    static func membersAreKnown(
        on version: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
    ) -> Bool {
        version.majorVersion <= membersMeasuredThroughMacOS
    }

    private static let usage = try? NSRegularExpression(
        pattern: #"(?<![\w$./-])(?:chrome|browser)\.([A-Za-z_$][\w$]*)\.([A-Za-z_$][\w$]*)"#
    )

    static func report(forPackageAt url: URL, accepting accepted: Set<String>) -> Report {
        let dropped = declaredPermissions(at: url).subtracting(accepted)
        guard membersAreKnown() else {
            return Report(namespaces: dropped.sorted())
        }
        var members: Set<String> = []
        for script in backgroundScripts(at: url) {
            guard let source = try? String(contentsOf: script, encoding: .utf8) else { continue }
            collect(from: source, into: &members)
        }
        return Report(namespaces: dropped.sorted(), members: members.sorted())
    }

    static func report(scanning source: String) -> Report {
        var members: Set<String> = []
        collect(from: source, into: &members)
        return Report(members: members.sorted())
    }

    static func declaredPermissions(at package: URL) -> Set<String> {
        guard let root = manifest(at: package),
              let declared = root["permissions"] as? [String]
        else { return [] }
        return Set(declared)
    }

    static func backgroundScripts(at package: URL) -> [URL] {
        guard let root = manifest(at: package),
              let background = root["background"] as? [String: Any]
        else { return [] }

        var names: [String] = []
        if let worker = background["service_worker"] as? String {
            names.append(worker)
        }
        if let scripts = background["scripts"] as? [String] {
            names.append(contentsOf: scripts)
        }
        if let page = background["page"] as? String {
            names.append(page)
        }
        return names.map { package.appendingPathComponent($0) }
    }

    private static func manifest(at package: URL) -> [String: Any]? {
        let url = package.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func collect(from source: String, into members: inout Set<String>) {
        guard let usage else { return }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        usage.enumerateMatches(in: source, range: range) { match, _, _ in
            guard let match,
                  let namespaceRange = Range(match.range(at: 1), in: source),
                  let memberRange = Range(match.range(at: 2), in: source)
            else { return }
            let name = "\(String(source[namespaceRange])).\(String(source[memberRange]))"
            if unsupportedMembers.contains(name) {
                members.insert(name)
            }
        }
    }
}
