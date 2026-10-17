// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

struct Run: Decodable {
    struct Metadata: Decodable {
        let revision: String
        let dirty: Bool
        let provider: String
        let model: String
        let suite: String
    }

    struct Attempt: Decodable {
        struct Check: Decodable {
            let name: String
            let passed: Bool
            let forbidden: Bool?
        }

        let task: String
        let version: Int
        let tags: [String]
        let variant: String
        let skipped: String?
        let passed: Bool
        let generations: Int
        let inputTokens: Int
        let cachedTokens: Int
        let elapsedMilliseconds: Int
        let checks: [Check]

        var brokeARule: Bool {
            checks.contains { $0.forbidden == true && !$0.passed }
        }
    }

    let metadata: Metadata
    let attempts: [Attempt]
}

struct Side {
    let label: String
    let attempts: [Run.Attempt]

    var byTask: [String: [Run.Attempt]] {
        Dictionary(grouping: attempts.filter { $0.skipped == nil }, by: \.task)
    }

    func violations(_ task: String) -> Int {
        byTask[task]?.count(where: \.brokeARule) ?? 0
    }

    func rate(_ task: String) -> Double? {
        guard let attempts = byTask[task], !attempts.isEmpty else { return nil }
        return Double(attempts.count { $0.passed }) / Double(attempts.count)
    }

    func mean(_ value: (Run.Attempt) -> Double) -> Double {
        let ran = attempts.filter { $0.skipped == nil }
        return ran.isEmpty ? 0 : ran.map(value).reduce(0, +) / Double(ran.count)
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

func load(_ path: String) -> Run {
    var url = URL(fileURLWithPath: path)
    if url.hasDirectoryPath || !path.hasSuffix(".json") {
        url = url.appendingPathComponent("results.json")
    }
    guard let data = try? Data(contentsOf: url) else { fail("Cannot read \(url.path)") }
    do {
        return try JSONDecoder().decode(Run.self, from: data)
    } catch {
        fail("Cannot decode \(url.path): \(error)")
    }
}

func binomialTwoSided(_ successes: Int, _ trials: Int) -> Double {
    guard trials > 0 else { return 1 }
    func choose(_ n: Int, _ k: Int) -> Double {
        (0..<k).reduce(1.0) { $0 * Double(n - $1) / Double($1 + 1) }
    }
    let k = min(successes, trials - successes)
    let tail = (0...k).reduce(0.0) { $0 + choose(trials, $1) } / pow(2, Double(trials))
    return min(1, 2 * tail)
}

var arguments = Array(CommandLine.arguments.dropFirst())
var variants: [String]?
if let index = arguments.firstIndex(of: "--variants"), index + 1 < arguments.count {
    variants = arguments[index + 1].split(separator: ",").map(String.init)
    arguments.removeSubrange(index...index + 1)
}

let baseline: Side
let candidate: Side
var notes: [String] = []
switch (arguments.count, variants) {
case (1, let names?) where names.count == 2:
    let run = load(arguments[0])
    baseline = Side(label: names[0], attempts: run.attempts.filter { $0.variant == names[0] })
    candidate = Side(label: names[1], attempts: run.attempts.filter { $0.variant == names[1] })
case (2, let names):
    let first = load(arguments[0])
    let second = load(arguments[1])
    let variant = names?.first ?? "default"
    baseline = Side(label: "\(first.metadata.revision)\(first.metadata.dirty ? "+" : "")", attempts: first.attempts.filter { $0.variant == variant })
    candidate = Side(label: "\(second.metadata.revision)\(second.metadata.dirty ? "+" : "")", attempts: second.attempts.filter { $0.variant == variant })
    if first.metadata.provider != second.metadata.provider || first.metadata.model != second.metadata.model {
        notes.append("The runs use different models: \(first.metadata.provider)/\(first.metadata.model) and \(second.metadata.provider)/\(second.metadata.model).")
    }
default:
    fail("Usage: eval compare BASELINE CANDIDATE, or eval compare RUN --variants BASELINE,CANDIDATE")
}

let shared = Set(baseline.byTask.keys).intersection(candidate.byTask.keys).filter { task in
    let before = Set(baseline.byTask[task]?.map(\.version) ?? [])
    let after = Set(candidate.byTask[task]?.map(\.version) ?? [])
    if before != after {
        notes.append("\(task) changed version, so it is not compared.")
        return false
    }
    return true
}.sorted()
guard !shared.isEmpty else { fail("The runs share no comparable tasks.") }

print("Baseline \(baseline.label) against candidate \(candidate.label), \(shared.count) tasks.\n")
print("| Task | \(baseline.label) | \(candidate.label) | Change |")
print("| --- | --- | --- | --- |")
var up = 0
var down = 0
var safetyRegressed: [String] = []
for task in shared {
    let before = baseline.rate(task) ?? 0
    let after = candidate.rate(task) ?? 0
    let change = after - before
    let mark = change > 0.001 ? "better" : change < -0.001 ? "worse" : ""
    if change > 0.001 {
        up += 1
    }
    if change < -0.001 {
        down += 1
    }
    if candidate.violations(task) > baseline.violations(task) {
        safetyRegressed.append(task)
    }
    let count = { (side: Side) in "\(side.byTask[task]?.count { $0.passed } ?? 0)/\(side.byTask[task]?.count ?? 0)" }
    print("| \(task) | \(count(baseline)) | \(count(candidate)) | \(mark) |")
}

func line(_ name: String, _ value: (Run.Attempt) -> Double, _ format: String) {
    let before = baseline.mean(value)
    let after = candidate.mean(value)
    let relative = before == 0 ? "" : String(format: " (%+.0f%%)", (after - before) / before * 100)
    print("- \(name): " + String(format: format, before) + " → " + String(format: format, after) + relative)
}
print("")
line("pass@1", { $0.passed ? 100 : 0 }, "%.0f%%")
line("Model requests per attempt", { Double($0.generations) }, "%.1f")
line("Input tokens per attempt", { Double($0.inputTokens) }, "%.0f")
line("Uncached input tokens per attempt", { Double($0.inputTokens - $0.cachedTokens) }, "%.0f")
line("Seconds per attempt", { Double($0.elapsedMilliseconds) / 1_000 }, "%.1f")

let p = binomialTwoSided(up, up + down)
print("\n\(up) tasks better, \(down) worse. Sign test p = \(String(format: "%.3f", p)).")
for note in notes {
    print("Note: \(note)")
}
if !safetyRegressed.isEmpty {
    print("Verdict: REGRESSION. Forbidden actions happened more often in: \(safetyRegressed.joined(separator: ", ")).")
    exit(1)
}
if down > up && p < 0.1 {
    print("Verdict: REGRESSION.")
    exit(1)
}
if up > down && p < 0.1 {
    print("Verdict: IMPROVEMENT.")
} else {
    print("Verdict: NO CLEAR CHANGE. Run more attempts to separate small changes from noise.")
}
