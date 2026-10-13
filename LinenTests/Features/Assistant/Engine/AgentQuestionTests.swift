// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

@MainActor
struct AgentQuestionTests {
    private let space = UUID()

    private func questions(_ texts: [String]) -> [AgentQuestionModel.Question] {
        texts.map { AgentQuestionModel.Question(text: $0, options: []) }
    }

    @Test func everyAnswerComesBackAsOneResult() async {
        let model = AgentQuestionModel()
        let asked = model.present(questions(["Which city?", "Which day?"]), inSpace: space)

        #expect(model.current != nil)
        #expect(model.count == 2)
        model.answer("Lisbon")
        #expect(model.index == 1)
        model.answer("Friday")

        #expect(await model.result(for: asked) == "Q: Which city?\nA: Lisbon\nQ: Which day?\nA: Friday")
        #expect(model.ask == nil)
    }

    @Test func aSkippedQuestionIsNeverOfferedAgain() async {
        let model = AgentQuestionModel()
        let asked = model.present(questions(["Which city?", "Which day?"]), inSpace: space)

        model.skip()
        #expect(model.index == 1)
        model.answer("Friday")

        #expect(await model.result(for: asked) == "Q: Which day?\nA: Friday")
    }

    @Test func skippingAChoiceHandsItToTheAgent() async {
        let model = AgentQuestionModel()
        let budget = AgentQuestionModel.Question(
            text: "What is your budget?",
            options: ["Low-cost", "Moderate", "Flexible"]
        )
        let asked = model.present([budget], inSpace: space)

        model.skip()

        let result = await model.result(for: asked)
        #expect(result.contains("Q: What is your budget?"))
        #expect(result.contains("No preference, you choose from: Low-cost · Moderate · Flexible"))
    }

    @Test func skippingAnOpenQuestionSaysNothingAtAll() async {
        let model = AgentQuestionModel()
        let asked = model.present(questions(["Which city?"]), inSpace: space)

        model.skip()

        #expect(await model.result(for: asked).isEmpty, "an open question passed over adds nothing")
    }

    @Test func steppingBackFillsTheGapItLeft() async {
        let model = AgentQuestionModel()
        let asked = model.present(questions(["Which city?", "Which day?"]), inSpace: space)

        model.goForward()
        #expect(model.index == 1)
        model.answer("Friday")
        #expect(model.index == 0, "the unanswered question comes back around")
        model.answer("Lisbon")

        #expect(await model.result(for: asked) == "Q: Which city?\nA: Lisbon\nQ: Which day?\nA: Friday")
    }

    @Test func changingAnAnswerStepsOnRatherThanClosing() async {
        let model = AgentQuestionModel()
        let first = model.present(questions(["Which city?", "Which day?"]), inSpace: space)

        model.answer("Lisbon")
        model.answer("Friday")
        #expect(model.ask == nil, "both answered closes it")
        _ = await model.result(for: first)

        let second = model.present(questions(["Which city?", "Which day?"]), inSpace: space)
        #expect(model.current?.text == "Which city?")

        model.answer("Lisbon")
        model.answer("Friday")
        _ = await model.result(for: second)
    }

    @Test func anAnsweredQuestionRemembersWhatWasChosen() async {
        let model = AgentQuestionModel()
        let asked = model.present(questions(["Which city?", "Which day?"]), inSpace: space)

        model.answer("Lisbon")
        #expect(model.index == 1)
        model.goBack()

        #expect(model.currentAnswer == "Lisbon")
        #expect(model.reply(at: 1) == .none)

        model.answer("Porto")
        #expect(model.reply(at: 0) == .given("Porto"), "the answer is replaced, not added to")
        #expect(model.index == 1, "a correction steps on instead of closing")

        model.answer("Friday")
        #expect(await model.result(for: asked) == "Q: Which city?\nA: Porto\nQ: Which day?\nA: Friday")
    }

    @Test func closingTheCardHandsTheRestToTheAgent() async {
        let model = AgentQuestionModel()
        let asked = model.present(questions(["Which city?", "Which day?"]), inSpace: space)

        model.answer("Lisbon")
        model.dismiss()

        let result = await model.result(for: asked)
        #expect(result.contains("Q: Which city?\nA: Lisbon"))
        #expect(result.contains("Choose sensible answers yourself"))
        #expect(result.contains("Which day?"), "the agent is told which ones are its to pick")
        #expect(model.ask == nil)
    }

    @Test func closingWithEverythingAnsweredHandsOverNothing() async {
        let model = AgentQuestionModel()
        let asked = model.present(questions(["Which city?"]), inSpace: space)

        model.answer("Lisbon")

        #expect(await model.result(for: asked) == "Q: Which city?\nA: Lisbon")
    }

    @Test func aQuestionOnlyShowsInTheSpaceThatAskedIt() async {
        let model = AgentQuestionModel()
        let asked = model.present(questions(["Which city?"]), inSpace: space)

        #expect(model.ask(inSpace: space) != nil)
        #expect(model.ask(inSpace: UUID()) == nil)
        #expect(model.ask(inSpace: nil) == nil)

        model.dismiss()
        _ = await model.result(for: asked)
    }

    @Test func cancellingTheTurnReleasesTheWaitingTool() async {
        let model = AgentQuestionModel()
        let asked = model.present(questions(["Which city?"]), inSpace: space)

        model.abandon()

        #expect(await model.result(for: asked).isEmpty)
        #expect(model.ask == nil)
    }

    @Test func askingAgainReplacesTheCardWaitingBefore() async {
        let model = AgentQuestionModel()
        let first = model.present(questions(["Which city?"]), inSpace: space)
        #expect(model.current?.text == "Which city?")

        let second = model.present(questions(["Which day?"]), inSpace: space)
        #expect(model.current?.text == "Which day?")

        #expect(await model.result(for: first).isEmpty)
        model.answer("Friday")
        #expect(await model.result(for: second) == "Q: Which day?\nA: Friday")
    }

    @Test func aQuestionStillWaitingHandsBackWhatItHasWhenAwaited() async {
        let model = AgentQuestionModel()
        let asked = model.present(questions(["Which city?"]), inSpace: space)

        async let result = model.result(for: asked)
        #expect(await waitUntil { model.ask != nil })
        model.answer("Lisbon")

        #expect(await result == "Q: Which city?\nA: Lisbon")
    }

    @Test func anAnswerWithNothingWaitingIsIgnored() {
        let model = AgentQuestionModel()
        model.answer("Lisbon")
        #expect(model.ask == nil)
    }
}
