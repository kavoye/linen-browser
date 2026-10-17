// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WebKit

@testable import Linen

nonisolated struct EvalRun: Codable, Sendable {
    struct Metadata: Codable, Sendable {
        let schema: Int
        let date: String
        let revision: String
        let dirty: Bool
        let provider: String
        let model: String
        let effort: String
        let suite: String
        let attempts: Int
        let variants: [String]
        let macOS: String
        let webKit: String
    }

    let metadata: Metadata
    var attempts: [EvalAttempt]
}

nonisolated enum EvalReport {
    struct Summary {
        let variant: String
        let tasks: Int
        let passAt1: Double
        let passAllK: Double
        let skipped: Int
        let generations: Double
        let inputTokens: Double
        let uncachedTokens: Double
        let seconds: Double
    }

    static func metadata(_ configuration: EvalConfiguration, provider: Provider) -> EvalRun.Metadata {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return .init(
            schema: 1,
            date: ISO8601DateFormatter().string(from: .now),
            revision: configuration.revision,
            dirty: configuration.dirty,
            provider: provider.id,
            model: configuration.model ?? provider.defaultModel,
            effort: configuration.effort,
            suite: configuration.suite,
            attempts: configuration.attempts,
            variants: configuration.variants,
            macOS: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            webKit: Bundle(for: WKWebView.self).object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        )
    }

    static func summaries(_ run: EvalRun) -> [Summary] {
        run.metadata.variants.map { variant in
            let attempts = run.attempts.filter { $0.variant == variant }
            let ran = attempts.filter { $0.skipped == nil }
            let byTask = Dictionary(grouping: ran, by: \.task)
            func mean(_ value: (EvalAttempt) -> Double) -> Double {
                ran.isEmpty ? 0 : ran.map(value).reduce(0, +) / Double(ran.count)
            }
            return Summary(
                variant: variant,
                tasks: byTask.count,
                passAt1: mean { $0.passed ? 1 : 0 },
                passAllK: byTask.isEmpty ? 0 : Double(byTask.values.count { $0.allSatisfy(\.passed) }) / Double(byTask.count),
                skipped: Set(attempts.filter { $0.skipped != nil }.map(\.task)).count,
                generations: mean { Double($0.generations) },
                inputTokens: mean { Double($0.inputTokens) },
                uncachedTokens: mean { Double($0.inputTokens - $0.cachedTokens) },
                seconds: mean { Double($0.elapsedMilliseconds) / 1_000 }
            )
        }
    }

    static func markdown(_ run: EvalRun) -> String {
        let meta = run.metadata
        var lines = [
            "# Linen eval: \(meta.suite)",
            "",
            "- Provider: \(meta.provider), model \(meta.model), effort \(meta.effort)",
            "- Revision: \(meta.revision)\(meta.dirty ? " with uncommitted changes" : "")",
            "- Attempts per task: \(meta.attempts). macOS \(meta.macOS), WebKit \(meta.webKit). \(meta.date)",
            "",
            "| Variant | Tasks | pass@1 | pass^\(meta.attempts) | Skipped | Requests | Input tokens | Uncached | Seconds |",
            "| --- | --- | --- | --- | --- | --- | --- | --- | --- |",
        ]
        for summary in summaries(run) {
            lines.append("| \(summary.variant) | \(summary.tasks) | \(percent(summary.passAt1)) | \(percent(summary.passAllK)) | \(summary.skipped) | "
                + "\(format(summary.generations)) | \(format(summary.inputTokens)) | \(format(summary.uncachedTokens)) | \(format(summary.seconds)) |")
        }
        lines += ["", "| Task | Covers | " + meta.variants.joined(separator: " | ") + " |",
                  "| --- | --- | " + meta.variants.map { _ in "---" }.joined(separator: " | ") + " |",
              ]
        let tasks = run.attempts.map(\.task).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        for task in tasks {
            let covers = run.attempts.first { $0.task == task }?.covers.joined(separator: ", ") ?? ""
            let cells = meta.variants.map { variant -> String in
                let attempts = run.attempts.filter { $0.task == task && $0.variant == variant }
                if let skipped = attempts.first?.skipped {
                    return "skipped: \(skipped)"
                }
                let failed = attempts.first { !$0.passed }
                let note = failed.map { attempt in
                    let check = attempt.checks.first { !$0.passed }?.name ?? attempt.status
                    return " (\(check))"
                } ?? ""
                return "\(attempts.count { $0.passed })/\(attempts.count)\(note)"
            }
            lines.append("| \(task) | \(covers) | " + cells.joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func write(_ run: EvalRun, to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(run).write(to: directory.appendingPathComponent("results.json"), options: .atomic)
        try markdown(run).write(to: directory.appendingPathComponent("report.md"), atomically: true, encoding: .utf8)
    }

    static func line(_ attempt: EvalAttempt) -> String {
        if let skipped = attempt.skipped {
            return "EVAL \(attempt.task) [\(attempt.variant) #\(attempt.attempt)] skipped: \(skipped)"
        }
        let failed = attempt.checks.filter { !$0.passed }.map(\.name)
        return "EVAL \(attempt.task) [\(attempt.variant) #\(attempt.attempt)] \(attempt.passed ? "PASS" : "FAIL") "
            + "status=\(attempt.status) requests=\(attempt.generations) tokens=\(attempt.inputTokens) "
            + "seconds=\(attempt.elapsedMilliseconds / 1_000) tools=\(attempt.tools.joined(separator: ","))"
            + (failed.isEmpty ? "" : " failed=\(failed.joined(separator: "; "))")
    }

    private static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }

    private static func format(_ value: Double) -> String {
        value >= 100 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }
}
