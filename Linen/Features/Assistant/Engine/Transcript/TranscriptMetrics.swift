// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation

enum TranscriptMetrics {
    static func text(in segments: [Transcript.Segment]) -> String {
        segments.compactMap { segment in
            if case .text(let text) = segment {
                return text.content
            }
            return nil
        }.joined()
    }

    static func milliseconds(since instant: ContinuousClock.Instant) -> Int {
        let components = instant.duration(to: .now).components
        return max(0, Int(components.seconds * 1_000 + components.attoseconds / 1_000_000_000_000_000))
    }

    static func estimatedTokens(in transcript: Transcript) -> Int {
        var prose = 0
        var machine = 0
        var images = 0
        for entry in transcript {
            switch entry {
            case .instructions(let value):
                prose += text(in: value.segments).count
            case .prompt(let value):
                prose += text(in: value.segments).count
                images += value.segments.filter {
                    if case .image = $0 {
                        return true
                    }
                    return false
                }.count
            case .response(let value):
                prose += text(in: value.segments).count
            case .reasoning(let value):
                prose += text(in: value.segments).count
            case .toolCalls(let calls):
                machine += calls.reduce(0) { partial, call in
                    partial + call.toolName.count + call.arguments.jsonString.count
                }
            case .toolOutput(let value):
                machine += text(in: value.segments).count
            }
        }
        let estimate = prose / 4 + machine / 3 + images * 1_600
        return prose + machine + images == 0 ? 0 : max(1, estimate)
    }

    static func contextBreakdown(in transcript: Transcript, budget: ContextBudget, toolTokens: Int? = nil) -> ContextBreakdown {
        var breakdown = ContextBreakdown(reservedTokens: max(0, budget.windowTokens - budget.inputTokens))
        func add(_ category: ContextBreakdown.Category, _ tokens: Int) {
            breakdown.tokens[category, default: 0] += tokens
        }
        add(.availableTools, toolTokens ?? budget.toolSchemaTokens)
        for entry in transcript {
            switch entry {
            case .instructions(let value):
                add(.instructions, text(in: value.segments).count / 4)
            case .prompt(let value):
                add(.messages, text(in: value.segments).count / 4)
                add(.images, value.segments.count {
                    if case .image = $0 {
                        return true
                    }
                    return false
                } * 1_600)
            case .response(let value):
                add(.messages, text(in: value.segments).count / 4)
            case .reasoning(let value):
                add(.reasoning, text(in: value.segments).count / 4)
            case .toolCalls(let calls):
                add(.toolActivity, calls.reduce(0) { $0 + $1.toolName.count + $1.arguments.jsonString.count } / 3)
            case .toolOutput(let value):
                add(.toolActivity, text(in: value.segments).count / 3)
            }
        }
        return breakdown
    }

    static func isContextWindowError(_ error: any Error) -> Bool {
        AgentContextCompactor.isContextWindowError(error)
    }
}

extension LanguageModelSession.Usage {
    var eventValues: [String: String] {
        guard totalTokenCount > 0 || input.cachedTokenCount > 0 || output.reasoningTokenCount > 0 else {
            return [:]
        }
        return [
            "input_tokens": input.totalTokenCount,
            "output_tokens": output.totalTokenCount,
            "cached_tokens": input.cachedTokenCount,
            "reasoning_tokens": output.reasoningTokenCount,
            "total_tokens": totalTokenCount,
        ]
        .mapValues(String.init)
    }
}
