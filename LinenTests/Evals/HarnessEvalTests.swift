// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

nonisolated enum EvalSuites {
    static let suites: [(name: String, tasks: [EvalTask])] = [
        ("tools", ToolTasks.all), ("flows", FlowTasks.all), ("memory", MemoryTasks.all),
    ].map { name, tasks in (name, tasks.map { $0.inSuite(name) }) }

    static let all: [String: [EvalTask]] = Dictionary(uniqueKeysWithValues: suites.map { ($0.name, $0.tasks) })
        .merging(["all": suites.flatMap(\.tasks)]) { first, _ in first }
}

@MainActor
struct HarnessEvalTests {
    @Test(.boundedWebViews, .enabled(if: EvalConfiguration.isEnabled))
    func evaluate() async throws {
        let configuration = EvalConfiguration.fromEnvironment()
        guard let suite = EvalSuites.all[configuration.suite] else { throw EvalError.unknownSuite(configuration.suite) }
        let variants = try configuration.variants.map { name in
            guard let variant = EvalVariant.all[name] else { throw EvalError.unknownVariant(name) }
            return variant
        }
        let provider = try configuration.provider()
        let tasks = suite.filter { configuration.taskIDs?.contains($0.id) ?? true }
        let runner = EvalRunner(configuration: configuration, provider: provider)
        var run = EvalRun(metadata: EvalReport.metadata(configuration, provider: provider), attempts: [])
        for attempt in 1...configuration.attempts {
            for task in tasks {
                let order = attempt.isMultiple(of: 2) ? variants.reversed() : variants
                for variant in order {
                    let result = try await variant.apply { try await runner.run(task, variant: variant, attempt: attempt) }
                    FileHandle.standardError.write(Data((EvalReport.line(result) + "\n").utf8))
                    run.attempts.append(result)
                    if let output = configuration.output {
                        try EvalReport.write(run, to: output)
                    }
                }
            }
        }
        FileHandle.standardError.write(Data(("\n" + EvalReport.markdown(run)).utf8))
    }
}
