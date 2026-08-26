// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation

@MainActor
@Observable
final class AgentQuestionModel {
    struct Question: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let options: [String]
    }

    struct Ask: Identifiable, Equatable {
        let id = UUID()
        let questions: [Question]
        let spaceID: UUID?
    }

    enum Reply: Equatable {
        case none
        case given(String)
        case skipped

        var text: String? {
            guard case .given(let answer) = self else { return nil }
            return answer
        }

        var isBlank: Bool {
            self == .none
        }
    }

    private(set) var ask: Ask?
    private(set) var index = 0
    private(set) var replies: [Reply] = []

    @ObservationIgnored private var waiting: [UUID: CheckedContinuation<String, Never>] = [:]
    @ObservationIgnored private var settled: [UUID: String] = [:]

    var current: Question? {
        ask?.questions.indices.contains(index) == true ? ask?.questions[index] : nil
    }

    var count: Int {
        ask?.questions.count ?? 0
    }

    var canGoBack: Bool {
        index > 0
    }

    var canGoForward: Bool {
        index + 1 < count
    }

    func ask(inSpace spaceID: UUID?) -> Ask? {
        guard let ask, let spaceID, ask.spaceID == spaceID else { return nil }
        return ask
    }

    func reply(at index: Int) -> Reply {
        replies.indices.contains(index) ? replies[index] : .none
    }

    var currentAnswer: String? {
        reply(at: index).text
    }

    func put(_ questions: [Question], inSpace spaceID: UUID?) async -> String {
        await result(for: present(questions, inSpace: spaceID))
    }

    @discardableResult
    func present(_ questions: [Question], inSpace spaceID: UUID?) -> Ask {
        finish()
        let presented = Ask(questions: questions, spaceID: spaceID)
        ask = presented
        index = 0
        replies = Array(repeating: .none, count: questions.count)
        return presented
    }

    func result(for ask: Ask) async -> String {
        if let answered = settled.removeValue(forKey: ask.id) {
            return answered
        }
        return await withCheckedContinuation { continuation in
            waiting[ask.id] = continuation
        }
    }

    func answer(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, replies.indices.contains(index) else { return }
        let wasAnswered = !replies[index].isBlank
        replies[index] = .given(trimmed)
        if wasAnswered, canGoForward {
            goForward()
            return
        }
        advance()
    }

    func skip() {
        guard replies.indices.contains(index) else { return }
        replies[index] = .skipped
        advance()
    }

    func goBack() {
        guard canGoBack else { return }
        index -= 1
    }

    func goForward() {
        guard canGoForward else { return }
        index += 1
    }

    func dismiss() {
        finish(handingOver: true)
    }

    func abandon() {
        finish()
    }

    private func advance() {
        if let next = replies.indices.first(where: { $0 > index && replies[$0].isBlank }) {
            index = next
            return
        }
        if let first = replies.firstIndex(where: { $0.isBlank }) {
            index = first
            return
        }
        finish()
    }

    private func finish(handingOver: Bool = false) {
        guard let closing = ask else { return }
        let questions = closing.questions
        var transcript = Self.transcript(of: questions, replies: replies)
        if handingOver, replies.contains(where: { $0.isBlank }) {
            let unanswered = questions.enumerated()
                .filter { reply(at: $0.offset).isBlank }
                .map(\.element.text)
            transcript = ([transcript] + [
                "\(Self.handoverMark) for the rest and carry on, without asking again: "
                    + unanswered.joined(separator: " · "),
            ])
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        }
        ask = nil
        index = 0
        replies = []
        if let continuation = waiting.removeValue(forKey: closing.id) {
            continuation.resume(returning: transcript)
        } else {
            settled[closing.id] = transcript
        }
    }

    nonisolated static let questionMark = "Q: "
    nonisolated static let answerMark = "A: "
    nonisolated static let handoverMark = "Choose sensible answers yourself"
    nonisolated static let passedMark = "No preference, you choose from: "

    static func transcript(of questions: [Question], replies: [Reply]) -> String {
        let lines = questions.enumerated().compactMap { index, question -> String? in
            guard replies.indices.contains(index) else { return nil }
            switch replies[index] {
            case .none:
                return nil
            case .given(let answer):
                return "\(questionMark)\(question.text)\n\(answerMark)\(answer)"
            case .skipped:
                guard !question.options.isEmpty else { return nil }
                let choices = question.options.joined(separator: " · ")
                return "\(questionMark)\(question.text)\n\(answerMark)\(passedMark)\(choices)"
            }
        }
        return lines.joined(separator: "\n")
    }
}
