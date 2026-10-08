// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WebKit

extension AgentToolkit {
    static let watchLimit = 20

    var pageWatches: PageWatchCenter {
        browserContext.pageWatches
    }

    func watchPage(condition rawCondition: String, everyMinutes: Int, outcomeID: String? = nil) async -> String {
        let condition = rawCondition.trimmingCharacters(in: .whitespacesAndNewlines)
        let view = targetWebView
        let place = view?.url?.displayHost ?? "this page"
        let step = beginTool(name: "watchPage", title: "Watch \(place)", detail: condition)
        if let output = cancellationOutput(for: step) {
            return output
        }
        func fail(_ output: String) -> String {
            completeTool(step, output: output, failed: true)
            return output
        }
        guard !browserContext.profile.isPrivate else {
            return fail("Private windows can’t watch pages. Tell the person to ask again in a regular window.")
        }
        guard let view, view.url.map(PageWatchLoader.canWatch) == true else {
            return fail("Open the page to watch first. Only websites can be watched.")
        }
        let access = await authorize(.read, in: view)
        if let denial = access.denial ?? postflightDenial(for: access.authorization, in: view) {
            return fail(denial)
        }
        guard let url = view.url, PageWatchLoader.canWatch(url) else {
            return fail("Open the page to watch first. Only websites can be watched.")
        }
        let center = pageWatches
        if let existing = center.watches.first(where: { $0.url == url && $0.condition == condition }) {
            return fail("Already watching this page for that. Watch ID: \(existing.id.uuidString)")
        }
        guard center.watches.count < Self.watchLimit else {
            return fail("Linen watches up to \(Self.watchLimit) pages. Ask the person which watch to stop first.")
        }
        guard await NotificationBridge.shared.requestAlerts() else {
            return fail("Notifications for Linen are turned off in System Settings, so a watch could never alert the person. Tell them to turn them on in System Settings > Notifications.")
        }
        let started = await center.start(
            url: url, title: view.title ?? "", condition: condition, everyMinutes: everyMinutes
        )
        if let output = cancellationOutput(for: step) {
            if case .watching(let watch) = started {
                center.stop(watch.id)
            }
            return output
        }
        switch started {
        case .watching(let watch):
            if let outcomeID {
                _ = taskLedger.confirm(id: outcomeID, url: watch.url.absoluteString, proof: "Watch \(watch.id.uuidString) started")
            }
            let output = """
                Watching \(watch.place) every \(Self.describe(watch.interval)). Watch ID: \(watch.id.uuidString)
                Waiting for: \(watch.condition.isEmpty ? "any change to the main content" : watch.condition)
                Now: \(watch.state ?? "")
                The person gets one notification when it happens, and then the watch ends. \
                It also ends after 30 days, or after the page can’t be read three times in a row.
                """
            completeTool(step, output: output)
            return output
        case .alreadyMet(let verdict):
            return fail("No watch was set: the page already shows it. \(verdict.message)")
        case .unreadable:
            return fail("Linen couldn’t read this page in the background, so it can’t watch it.")
        case .noModel:
            return fail("Watching pages needs Apple Intelligence, which isn’t available on this Mac.")
        }
    }

    func listWatches() -> String {
        let step = beginTool(name: "listWatches", title: "List Watched Pages")
        if let output = cancellationOutput(for: step) {
            return output
        }
        let watches = pageWatches.watches
        guard !watches.isEmpty else {
            let output = "No pages are being watched."
            completeTool(step, output: output)
            return output
        }
        let output = watches.map(Self.describe).joined(separator: "\n")
        completeTool(step, output: output)
        return output
    }

    func stopWatch(matching reference: String) -> String {
        let step = beginTool(name: "stopWatch", title: "Stop watching a page", detail: reference)
        if let output = cancellationOutput(for: step) {
            return output
        }
        let center = pageWatches
        let matches = center.matching(reference)
        guard let watch = matches.first else {
            let output = "No watch matches. Use listWatches to see them."
            completeTool(step, output: output, failed: true)
            return output
        }
        guard matches.count == 1 else {
            let output = "More than one watch matches. Pass a watch ID:\n"
                + matches.map(Self.describe).joined(separator: "\n")
            completeTool(step, output: output, failed: true)
            return output
        }
        center.stop(watch.id)
        let output = "Stopped watching \(watch.title.isEmpty ? watch.place : watch.title)."
        completeTool(step, output: output)
        return output
    }

    private static func describe(_ watch: PageWatch) -> String {
        let condition = watch.condition.isEmpty ? "any change" : watch.condition
        let state = watch.state.map { " Last seen: \($0)." } ?? ""
        return "[\(watch.id.uuidString)] \(watch.title) (\(watch.place)), every \(describe(watch.interval)), "
            + "waiting for: \(condition).\(state)"
    }

    private static func describe(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        guard minutes >= 60 else { return "\(minutes) minutes" }
        let hours = minutes / 60
        return hours == 1 ? "hour" : "\(hours) hours"
    }
}
