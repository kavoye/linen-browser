// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

nonisolated struct AgentAskedExchange: Identifiable, Equatable {
    enum Answer: Equatable {
        case given(String)
        case passed
        case handedOver([String])
    }

    let id: Int
    let question: String
    let answer: Answer

    static func read(_ transcript: String) -> [AgentAskedExchange] {
        var found: [AgentAskedExchange] = []
        var question: String?
        for line in transcript.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = String(line)
            if let asked = text.after(AgentQuestionModel.questionMark) {
                question = asked
            } else if let answer = text.after(AgentQuestionModel.answerMark), let asked = question {
                let reply: Answer = answer.hasPrefix(AgentQuestionModel.passedMark)
                    ? .passed
                    : .given(answer)
                found.append(AgentAskedExchange(id: found.count, question: asked, answer: reply))
                question = nil
            } else if text.hasPrefix(AgentQuestionModel.handoverMark) {
                let rest = text
                    .split(separator: ":", maxSplits: 1)
                    .last
                    .map(String.init)?
                    .split(separator: "·")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty } ?? []
                found.append(
                    AgentAskedExchange(
                        id: found.count,
                        question: String(localized: "Left to the assistant"),
                        answer: .handedOver(rest)
                    )
                )
            }
        }
        return found
    }
}

private extension String {
    nonisolated func after(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}

struct AgentAskedList: View {
    let exchanges: [AgentAskedExchange]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(exchanges) { exchange in
                if exchange.id > 0 {
                    Divider().opacity(0.4)
                }
                row(exchange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Theme.Wash.faint,
            in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
        )
    }

    @ViewBuilder
    private func row(_ exchange: AgentAskedExchange) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: exchange.question)
                .font(Theme.Font.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            switch exchange.answer {
            case .given(let answer):
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 3)
                    Text(verbatim: answer)
                        .font(Theme.Font.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .passed:
                Text("No preference — the assistant chose")
                    .font(Theme.Font.body)
                    .foregroundStyle(.secondary)
            case .handedOver(let questions):
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(questions, id: \.self) { question in
                        Text(verbatim: question)
                            .font(Theme.Font.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .textSelection(.enabled)
    }
}
