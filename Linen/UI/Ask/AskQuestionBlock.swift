// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct AskQuestionBlock: View {
    let questions: AgentQuestionModel
    let placement: AskSurface.Placement
    var takesFocus = true

    @State private var draft = ""
    @State private var writingOwnAnswer = false
    @FocusState private var writing: Bool

    private var trimmed: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var contentInset: CGFloat {
        placement.rowInset + 6
    }

    var body: some View {
        if let question = questions.current {
            VStack(alignment: .leading, spacing: 0) {
                header(question)

                ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                    OptionRow(
                        number: index + 1,
                        label: option,
                        isChosen: questions.currentAnswer == option
                    ) {
                        answer(option)
                    }
                    .padding(.horizontal, contentInset - OptionRow.bleed)
                    RowSeparator(inset: contentInset)
                }

                ownAnswerRow
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .task(id: questions.index) {
                let chosen = questions.currentAnswer
                let isOwnWords = chosen.map { !question.options.contains($0) } ?? false
                draft = isOwnWords ? (chosen ?? "") : ""
                writingOwnAnswer = question.options.isEmpty || isOwnWords
                guard takesFocus, writingOwnAnswer, draft.isEmpty else { return }
                try? await Task.sleep(for: .milliseconds(80))
                writing = true
            }
        }
    }

    private func header(_ question: AgentQuestionModel.Question) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(verbatim: question.text)
                .font(Theme.Font.rowTitle)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if questions.count > 1 {
                HStack(spacing: 4) {
                    StepButton(symbol: "chevron.left", isEnabled: questions.canGoBack) {
                        questions.goBack()
                    }
                    Text("\(questions.index + 1) of \(questions.count)")
                        .font(Theme.Font.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    StepButton(symbol: "chevron.right", isEnabled: questions.canGoForward) {
                        questions.goForward()
                    }
                }
                .fixedSize()
            }

            StepButton(symbol: "xmark", isEnabled: true) { questions.dismiss() }
        }
        .padding(.horizontal, contentInset)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var ownAnswerRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "pencil")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.tight, style: .continuous)
                        .fill(Theme.Wash.hairline)
                )

            if writingOwnAnswer {
                TextField(text: $draft) {
                    Text("Something else\u{2026}")
                }
                .textFieldStyle(.plain)
                .font(.system(size: placement.textSize))
                .focused($writing)
                .onSubmit { answer(draft) }
            } else {
                Text("Something else")
                    .font(.system(size: placement.textSize))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { beginWriting() }
            }

            Spacer(minLength: 8)

            if writingOwnAnswer, !trimmed.isEmpty {
                Button { answer(draft) } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .help("Send")
            } else {
                Button("Skip") { questions.skip() }
                    .buttonStyle(.plain)
                    .font(Theme.Font.label)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                            .strokeBorder(Theme.Wash.strong, lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, contentInset)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }

    private func beginWriting() {
        writingOwnAnswer = true
        writing = true
    }

    private func answer(_ text: String) {
        let answer = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { return }
        draft = ""
        writing = false
        questions.answer(answer)
    }
}

private struct OptionRow: View {
    let number: Int
    let label: String
    let isChosen: Bool
    let action: () -> Void

    static let bleed: CGFloat = 8

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Group {
                    if isChosen {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Text(number, format: .number)
                            .font(Theme.Font.caption)
                            .monospacedDigit()
                            .foregroundStyle(
                                hovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)
                            )
                    }
                }
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.tight, style: .continuous)
                        .fill(isChosen ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.Wash.hairline))
                )

                Text(verbatim: label)
                    .font(Theme.Font.rowTitle)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .opacity(hovering ? 1 : 0)
            }
            .padding(.horizontal, Self.bleed)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.hover, style: .continuous)
                    .fill(hovering ? Theme.Wash.hairline : .clear)
                    .padding(1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.quick, value: hovering)
    }
}

private struct StepButton: View {
    let symbol: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isEnabled ? AnyShapeStyle(.secondary) : AnyShapeStyle(.quaternary))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}
