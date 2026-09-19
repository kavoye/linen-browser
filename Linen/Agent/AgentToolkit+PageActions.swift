// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WebKit

extension AgentToolkit {
    func readPage(lookingFor: String = "", page: String = "", textOffset: Int = 0, controlOffset: Int = 0, scope: String = "", viewportOnly: Bool = false) async -> String {
        let subject = page.isEmpty ? "the page" : "“\(page)”"
        let title = lookingFor.isEmpty
            ? "Read \(subject)"
            : "Read \(subject) for “\(lookingFor)”"
        let step = beginTool(name: "readPage", title: title)
        if let output = cancellationOutput(for: step) {
            return output
        }
        guard let webView = pageSurface(named: page) else {
            let output = onScreenPageDenial(for: page)
            completeTool(step, output: output, failed: true)
            return output
        }
        let access = await authorize(.read, in: webView)
        if let output = cancellationOutput(for: step) {
            return output
        }
        if let output = access.denial {
            completeTool(step, output: output, failed: true)
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
            completeTool(step, output: output, failed: true)
            return output
        }
        updateFinalResearchURL(from: webView)
        let links = links(in: output)
        remember(links: links)
        completeTool(step, output: output, links: links, failed: !output.hasPrefix("PAGE TEXT:"))
        let pageID = pageIdentifier(for: webView)
        return fencedPageOutput("pageID: \(pageID)\n" + output)
    }

    func clickOnPage(ref: Int, label: String) async -> String {
        let step = beginTool(name: "clickOnPage", title: ref > 0 ? "Click [\(ref)]" : "Click “\(label)”")
        if let output = cancellationOutput(for: step) {
            return output
        }
        guard let webView = targetWebView else {
            let output = "No tab is open yet."
            completeTool(step, output: output, failed: true)
            return output
        }
        let access = await authorize(.control, in: webView)
        if let output = cancellationOutput(for: step) {
            return output
        }
        if let output = access.denial {
            completeTool(step, output: output, failed: true)
            return output
        }
        let output = await guardedPageOperation(in: webView, authorization: access.authorization, capability: .control) {
            await PageDriver.click(ref: ref, label: label, in: webView, announced: actsOnVisiblePage)
        }
        if let cancelled = cancellationOutput(for: step) {
            return cancelled
        }
        if let output = postflightDenial(for: access.authorization, in: webView) {
            completeTool(step, output: output, failed: true)
            return output
        }
        updateFinalResearchURL(from: webView)
        remember(links: links(in: output))
        completeTool(step, output: output, failed: !output.hasPrefix("Clicked"))
        return fencedPageOutput(output)
    }

    func typeOnPage(text: String, field: String, ref: Int, submit: Bool) async -> String {
        let step = beginTool(
            name: "typeOnPage",
            title: ref > 0 ? "Type into [\(ref)]" : "Type into “\(field)”",
            detail: text
        )
        if let output = cancellationOutput(for: step) {
            return output
        }
        guard let webView = targetWebView else {
            let output = "No tab is open yet."
            completeTool(step, output: output, failed: true)
            return output
        }
        let access = await authorize(.control, in: webView)
        if let output = cancellationOutput(for: step) {
            return output
        }
        if let output = access.denial {
            completeTool(step, output: output, failed: true)
            return output
        }
        let output = await guardedPageOperation(in: webView, authorization: access.authorization, capability: .control) {
            await PageDriver.type(
            text: text,
            intoField: field,
            ref: ref,
            submit: submit,
            in: webView,
            announced: actsOnVisiblePage
        )
        }
        if let cancelled = cancellationOutput(for: step) {
            return cancelled
        }
        if let output = postflightDenial(for: access.authorization, in: webView) {
            completeTool(step, output: output, failed: true)
            return output
        }
        updateFinalResearchURL(from: webView)
        remember(links: links(in: output))
        completeTool(step, output: output, failed: !output.hasPrefix("Typed"))
        return fencedPageOutput(output)
    }

    func fillFields(_ fields: [PageDriver.FieldValue]) async -> String {
        let step = beginTool(name: "fillFields", title: "Fill fields")
        if let cancelled = cancellationOutput(for: step) {
            return cancelled
        }
        guard let webView = targetWebView else {
            completeTool(step, output: "No page is open.", failed: true)
            return "No page is open."
        }
        let access = await authorize(.control, in: webView)
        if let cancelled = cancellationOutput(for: step) {
            return cancelled
        }
        if let denial = access.denial {
            completeTool(step, output: denial, failed: true)
            return denial
        }
        let output = await guardedPageOperation(in: webView, authorization: access.authorization, capability: .control) {
            await PageDriver.fillFields(fields, in: webView, announced: actsOnVisiblePage)
        }
        if let cancelled = cancellationOutput(for: step) {
            return cancelled
        }
        if let denial = postflightDenial(for: access.authorization, in: webView) {
            completeTool(step, output: denial, failed: true)
            return denial
        }
        remember(links: links(in: output))
        completeTool(step, output: output, failed: !output.hasPrefix("Filled \(fields.count) of \(fields.count) fields."))
        return fencedPageOutput(output)
    }

    func selectOption(_ option: String, ref: Int, field: String) async -> String {
        let step = beginTool(
            name: "selectOption",
            title: ref > 0 ? "Choose “\(option)” in [\(ref)]" : "Choose “\(option)” in “\(field)”"
        )
        if let output = cancellationOutput(for: step) {
            return output
        }
        guard let webView = targetWebView else {
            let output = "No tab is open yet."
            completeTool(step, output: output, failed: true)
            return output
        }
        let access = await authorize(.control, in: webView)
        if let output = cancellationOutput(for: step) {
            return output
        }
        if let output = access.denial {
            completeTool(step, output: output, failed: true)
            return output
        }
        let output = await guardedPageOperation(in: webView, authorization: access.authorization, capability: .control) {
            await PageDriver.selectOption(
            option,
            ref: ref,
            field: field,
            in: webView,
            announced: actsOnVisiblePage
        )
        }
        if let cancelled = cancellationOutput(for: step) {
            return cancelled
        }
        if let output = postflightDenial(for: access.authorization, in: webView) {
            completeTool(step, output: output, failed: true)
            return output
        }
        updateFinalResearchURL(from: webView)
        remember(links: links(in: output))
        completeTool(step, output: output, failed: !output.hasPrefix("Selected"))
        return fencedPageOutput(output)
    }

    func scrollPage(direction: String) async -> String {
        let step = beginTool(name: "scrollPage", title: "Scroll \(direction)")
        if let output = cancellationOutput(for: step) {
            return output
        }
        guard let webView = targetWebView else {
            let output = "No tab is open yet."
            completeTool(step, output: output, failed: true)
            return output
        }
        let access = await authorize(.control, in: webView)
        if let output = cancellationOutput(for: step) {
            return output
        }
        if let output = access.denial {
            completeTool(step, output: output, failed: true)
            return output
        }
        let output = await guardedPageOperation(in: webView, authorization: access.authorization, capability: .control) {
            await PageDriver.scroll(direction: direction, in: webView)
        }
        if let cancelled = cancellationOutput(for: step) {
            return cancelled
        }
        if let output = postflightDenial(for: access.authorization, in: webView) {
            completeTool(step, output: output, failed: true)
            return output
        }
        completeTool(step, output: output, failed: !output.hasPrefix("Scrolled") && !output.hasPrefix("Already at"))
        return fencedPageOutput(output)
    }

    func goBack() async -> String {
        let step = beginTool(name: "goBack", title: "Go Back")
        if let output = cancellationOutput(for: step) {
            return output
        }
        guard let webView = targetWebView else {
            let output = "No tab is open yet."
            completeTool(step, output: output, failed: true)
            return output
        }
        let access = await authorize(.control, in: webView)
        if let output = cancellationOutput(for: step) {
            return output
        }
        if let output = access.denial {
            completeTool(step, output: output, failed: true)
            return output
        }
        let output = await guardedPageOperation(in: webView, authorization: access.authorization, capability: .control) {
            await PageDriver.goBack(in: webView)
        }
        if let cancelled = cancellationOutput(for: step) {
            return cancelled
        }
        if let output = postflightDenial(for: access.authorization, in: webView) {
            completeTool(step, output: output, failed: true)
            return output
        }
        updateFinalResearchURL(from: webView)
        completeTool(step, output: output, failed: output.hasPrefix("There is no"))
        return fencedPageOutput(output)
    }

}
