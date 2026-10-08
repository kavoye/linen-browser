// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WebKit

extension AgentToolkit {
    func readArticle(page: String = "", textOffset: Int = 0) async -> String {
        let subject = page.isEmpty ? "the page" : "“\(page)”"
        let step = beginTool(name: "readArticle", title: "Read the article on \(subject)")
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
            guard PageAutomationGuard.allowsExecution else { return PageDriver.staleMessage }
            let article = await ReaderExtractor.article(in: webView)
            guard PageAutomationGuard.allowsExecution else { return PageDriver.staleMessage }
            return Self.articleOutput(article, budget: outputBudget.pageTextCharacters, offset: textOffset)
        }
        if let cancelled = cancellationOutput(for: step) {
            return cancelled
        }
        if let output = postflightDenial(for: access.authorization, in: webView) {
            completeTool(step, output: output, failed: true)
            return output
        }
        completeTool(step, output: output, failed: !output.hasPrefix("ARTICLE:"))
        let pageID = pageIdentifier(for: webView)
        return fencedPageOutput("pageID: \(pageID)\n" + output)
    }

    nonisolated static func articleOutput(_ article: ReaderArticle?, budget: Int, offset: Int) -> String {
        guard let article else {
            return "NO ARTICLE: This page has no main article. Use readPage for its text and controls."
        }
        let body = article.text
        let start = min(max(0, offset), body.count)
        let lower = body.index(body.startIndex, offsetBy: start)
        let upper = body.index(lower, offsetBy: min(max(0, budget), body.distance(from: lower, to: body.endIndex)))
        var lines = ["ARTICLE: \(article.title)"]
        let details = [
            article.siteName.isEmpty ? nil : "Site: \(article.siteName)",
            article.byline.isEmpty ? nil : "By: \(article.byline)",
            "\(article.wordCount) words",
        ].compactMap(\.self)
        lines.append(details.joined(separator: " · "))
        lines.append("URL: \(article.url.absoluteString)")
        if start > 0 {
            lines.append("Continuing from character \(start).")
        }
        lines.append("")
        lines.append(String(body[lower..<upper]))
        if upper < body.endIndex {
            let next = body.distance(from: body.startIndex, to: upper)
            lines.append("")
            lines.append("… \(body.distance(from: upper, to: body.endIndex)) more characters. Call readArticle with textOffset \(next) to continue.")
        }
        return lines.joined(separator: "\n")
    }
}
