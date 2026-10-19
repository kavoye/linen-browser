// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WebKit

extension AgentToolkit {
    func readPage(lookingFor: String = "", page: String = "", textOffset: Int = 0, controlOffset: Int = 0, scope: String = "", viewportOnly: Bool = false) async -> String {
        let step = beginTool(name: "readPage")
        if let output = cancellationOutput(for: step) {
            return output
        }
        guard let (webView, note) = readableSurface(named: page) else {
            let output = onScreenPageDenial(for: page)
            completeTool(step, failed: true)
            return output
        }
        let access = await authorize(.read, in: webView)
        if let output = cancellationOutput(for: step) {
            return output
        }
        if let output = access.denial {
            completeTool(step, failed: true)
            return output
        }
        let output = await guardedPageOperation(in: webView, authorization: access.authorization, capability: .read) {
            await PageDriver.readRenderedPage(
            webView,
            lookingFor: lookingFor,
            maxTextLength: outputBudget.pageTextCharacters,
            controlLimit: outputBudget.controlLimit,
            textOffset: textOffset, controlOffset: controlOffset, scope: scope, viewportOnly: viewportOnly
        )
        }
        if let cancelled = cancellationOutput(for: step) {
            return cancelled
        }
        if let output = postflightDenial(for: access.authorization, in: webView) {
            completeTool(step, failed: true)
            return output
        }
        let links = links(in: output)
        remember(links: links)
        completeTool(step, failed: !output.hasPrefix("PAGE TEXT:"))
        let pageID = pageIdentifier(for: webView)
        let request = [page, lookingFor, String(textOffset), String(controlOffset), scope, String(viewportOnly)].joined(separator: "\u{1F}")
        return note + fencedPageOutput("pageID: \(pageID)\n" + unchangedRead(output, page: pageID, request: request))
    }

    static let unchangedReadNote = "Nothing changed since your last read of this page. Act on a control below, or answer the user."

    func unchangedRead(_ output: String, page: String, request: String = "") -> String {
        let content = request + "\n" + output.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix("observationID:") }.joined(separator: "\n")
        let missed = output.contains(" is not on this page.")
        if missed, lastMiss == page {
            repeatedRead = true
        }
        lastMiss = missed ? page : nil
        defer { lastReads[page] = content }
        guard lastReads[page] == content, let controls = output.range(of: "CONTROLS:\n") else { return output }
        repeatedRead = true
        return Self.unchangedReadNote + "\n\n" + output[controls.lowerBound...]
    }

    func clickOnPage(ref: Int, label: String) async -> String {
        let step = beginTool(name: "clickOnPage")
        if let output = cancellationOutput(for: step) {
            return output
        }
        guard let webView = targetWebView else {
            let output = "No tab is open yet."
            completeTool(step, failed: true)
            return output
        }
        let access = await authorize(.control, in: webView)
        if let output = cancellationOutput(for: step) {
            return output
        }
        if let output = access.denial {
            completeTool(step, failed: true)
            return output
        }
        let output = await guardedPageOperation(in: webView, authorization: access.authorization, capability: .control) {
            await PageDriver.click(ref: ref, label: label, in: webView, announced: true, constraints: requestConstraints)
        }
        if let cancelled = cancellationOutput(for: step) {
            return cancelled
        }
        if let output = postflightDenial(for: access.authorization, in: webView) {
            completeTool(step, failed: true)
            return output
        }
        if AgentRequestConstraints.isRefusal(output) {
            refusedActions += 1
            completeTool(step, failed: true)
            return output
        }
        remember(links: links(in: output))
        completeTool(step, failed: !output.hasPrefix("Clicked"))
        guard !output.hasPrefix("Clicked"), Self.namesAKey(label) else { return fencedPageOutput(output) }
        return Self.keyHint + "\n" + fencedPageOutput(output)
    }

    static let keyHint = "To press a key such as Escape, use pressKey."

    nonisolated static func namesAKey(_ text: String) -> Bool {
        let words = Set(text.lowercased().split { !$0.isLetter }.map(String.init))
        return !words.isDisjoint(with: ["escape", "esc", "enter", "return", "tab", "key", "backspace", "arrowdown", "arrowup", "pagedown", "pageup"])
    }

    func typeOnPage(text: String, field: String, ref: Int, submit: Bool) async -> String {
        let step = beginTool(name: "typeOnPage")
        if let output = cancellationOutput(for: step) {
            return output
        }
        guard let webView = targetWebView else {
            let output = "No tab is open yet."
            completeTool(step, failed: true)
            return output
        }
        let access = await authorize(.control, in: webView)
        if let output = cancellationOutput(for: step) {
            return output
        }
        if let output = access.denial {
            completeTool(step, failed: true)
            return output
        }
        let output = await guardedPageOperation(in: webView, authorization: access.authorization, capability: .control) {
            await PageDriver.type(
            text: text,
            intoField: field,
            ref: ref,
            submit: submit,
            in: webView,
            announced: true,
            constraints: requestConstraints
        )
        }
        if let cancelled = cancellationOutput(for: step) {
            return cancelled
        }
        if let output = postflightDenial(for: access.authorization, in: webView) {
            completeTool(step, failed: true)
            return output
        }
        if AgentRequestConstraints.isRefusal(output) {
            refusedActions += 1
            completeTool(step, failed: true)
            return output
        }
        remember(links: links(in: output))
        completeTool(step, failed: !output.hasPrefix("Typed"))
        if text.isEmpty, !submit, output.hasPrefix("Typed") {
            return "The text was empty, so the field is now empty. " + Self.keyHint + "\n" + fencedPageOutput(output)
        }
        guard !output.hasPrefix("Typed"), Self.namesAKey(text) else { return fencedPageOutput(output) }
        return Self.keyHint + "\n" + fencedPageOutput(output)
    }

    func fillFields(_ fields: [PageDriver.FieldValue]) async -> String {
        let step = beginTool(name: "fillFields")
        if let cancelled = cancellationOutput(for: step) {
            return cancelled
        }
        guard let webView = targetWebView else {
            completeTool(step, failed: true)
            return "No page is open."
        }
        let access = await authorize(.control, in: webView)
        if let cancelled = cancellationOutput(for: step) {
            return cancelled
        }
        if let denial = access.denial {
            completeTool(step, failed: true)
            return denial
        }
        let output = await guardedPageOperation(in: webView, authorization: access.authorization, capability: .control) {
            await PageDriver.fillFields(fields, in: webView, announced: true)
        }
        if let cancelled = cancellationOutput(for: step) {
            return cancelled
        }
        if let denial = postflightDenial(for: access.authorization, in: webView) {
            completeTool(step, failed: true)
            return denial
        }
        remember(links: links(in: output))
        completeTool(step, failed: !output.hasPrefix("Filled \(fields.count) of \(fields.count) fields."))
        return fencedPageOutput(output)
    }

    func selectOption(_ option: String, ref: Int, field: String) async -> String {
        let step = beginTool(name: "selectOption")
        if let output = cancellationOutput(for: step) {
            return output
        }
        guard let webView = targetWebView else {
            let output = "No tab is open yet."
            completeTool(step, failed: true)
            return output
        }
        let access = await authorize(.control, in: webView)
        if let output = cancellationOutput(for: step) {
            return output
        }
        if let output = access.denial {
            completeTool(step, failed: true)
            return output
        }
        let output = await guardedPageOperation(in: webView, authorization: access.authorization, capability: .control) {
            await PageDriver.selectOption(
            option,
            ref: ref,
            field: field,
            in: webView,
            announced: true
        )
        }
        if let cancelled = cancellationOutput(for: step) {
            return cancelled
        }
        if let output = postflightDenial(for: access.authorization, in: webView) {
            completeTool(step, failed: true)
            return output
        }
        remember(links: links(in: output))
        completeTool(step, failed: !output.hasPrefix("Selected"))
        return fencedPageOutput(output)
    }

    func scrollPage(direction: String) async -> String {
        let step = beginTool(name: "scrollPage")
        if let output = cancellationOutput(for: step) {
            return output
        }
        guard let webView = targetWebView else {
            let output = "No tab is open yet."
            completeTool(step, failed: true)
            return output
        }
        let access = await authorize(.control, in: webView)
        if let output = cancellationOutput(for: step) {
            return output
        }
        if let output = access.denial {
            completeTool(step, failed: true)
            return output
        }
        let output = await guardedPageOperation(in: webView, authorization: access.authorization, capability: .control) {
            await PageDriver.scroll(direction: direction, in: webView)
        }
        if let cancelled = cancellationOutput(for: step) {
            return cancelled
        }
        if let output = postflightDenial(for: access.authorization, in: webView) {
            completeTool(step, failed: true)
            return output
        }
        completeTool(step, failed: !output.hasPrefix("Scrolled") && !output.hasPrefix("Already at"))
        return fencedPageOutput(output)
    }

    func goBack() async -> String {
        let step = beginTool(name: "goBack")
        if let output = cancellationOutput(for: step) {
            return output
        }
        guard let webView = targetWebView else {
            let output = "No tab is open yet."
            completeTool(step, failed: true)
            return output
        }
        let access = await authorize(.control, in: webView)
        if let output = cancellationOutput(for: step) {
            return output
        }
        if let output = access.denial {
            completeTool(step, failed: true)
            return output
        }
        let output = await guardedPageOperation(in: webView, authorization: access.authorization, capability: .control) {
            await PageDriver.goBack(in: webView)
        }
        if let cancelled = cancellationOutput(for: step) {
            return cancelled
        }
        if let output = postflightDenial(for: access.authorization, in: webView) {
            completeTool(step, failed: true)
            return output
        }
        completeTool(step, failed: output.hasPrefix("There is no"))
        return fencedPageOutput(output)
    }

}
