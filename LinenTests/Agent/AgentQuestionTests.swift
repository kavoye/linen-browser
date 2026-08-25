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

        async let asked = model.put(questions(["Which city?", "Which day?"]), inSpace: space)
        #expect(await waitUntil { model.current != nil })

        #expect(model.count == 2)
        model.answer("Lisbon")
        #expect(model.index == 1)
        model.answer("Friday")

        #expect(await asked == "Which city? Lisbon\nWhich day? Friday")
        #expect(model.ask == nil)
    }

    @Test func aSkippedQuestionIsNeverOfferedAgain() async {
        let model = AgentQuestionModel()

        async let asked = model.put(questions(["Which city?", "Which day?"]), inSpace: space)
        #expect(await waitUntil { model.current != nil })

        model.skip()
        #expect(model.index == 1)
        model.answer("Friday")

        #expect(await asked == "Q: Which day?\\nA: Friday")
    }

    @Test func skippingAChoiceHandsItToTheAgent() async {
        let model = AgentQuestionModel()
        let budget = AgentQuestionModel.Question(
            text: "What is your budget?",
            options: ["Low-cost", "Moderate", "Flexible"]
        )

        async let asked = model.put([budget], inSpace: space)
        #expect(await waitUntil { model.current != nil })

        model.skip()

        let result = await asked
        #expect(result.contains("Q: What is your budget?"))
        #expect(result.contains("No preference, you choose from: Low-cost · Moderate · Flexible"))
    }

    @Test func skippingAnOpenQuestionSaysNothingAtAll() async {
        let model = AgentQuestionModel()

        async let asked = model.put(questions(["Which city?"]), inSpace: space)
        #expect(await waitUntil { model.current != nil })

        model.skip()

        #expect(await asked.isEmpty, "an open question passed over adds nothing")
    }

    @Test func steppingBackFillsTheGapItLeft() async {
        let model = AgentQuestionModel()

        async let asked = model.put(questions(["Which city?", "Which day?"]), inSpace: space)
        #expect(await waitUntil { model.current != nil })

        model.goForward()
        #expect(model.index == 1)
        model.answer("Friday")
        #expect(model.index == 0, "the unanswered question comes back around")
        model.answer("Lisbon")

        #expect(await asked == "Which city? Lisbon\nWhich day? Friday")
    }

    @Test func changingAnAnswerStepsOnRatherThanClosing() async {
        let model = AgentQuestionModel()

        async let asked = model.put(questions(["Which city?", "Which day?"]), inSpace: space)
        #expect(await waitUntil { model.current != nil })

        model.answer("Lisbon")
        model.answer("Friday")
        #expect(model.ask == nil, "both answered closes it")

        async let second = model.put(questions(["Which city?", "Which day?"]), inSpace: space)
        #expect(await waitUntil { model.current?.text == "Which city?" })
        _ = await asked

        model.answer("Lisbon")
        model.answer("Friday")
        _ = await second
    }

    @Test func anAnsweredQuestionRemembersWhatWasChosen() async {
        let model = AgentQuestionModel()

        async let asked = model.put(questions(["Which city?", "Which day?"]), inSpace: space)
        #expect(await waitUntil { model.current != nil })

        model.answer("Lisbon")
        #expect(model.index == 1)
        model.goBack()

        #expect(model.currentAnswer == "Lisbon")
        #expect(model.reply(at: 1) == .none)

        model.answer("Porto")
        #expect(model.reply(at: 0) == .given("Porto"), "the answer is replaced, not added to")
        #expect(model.index == 1, "a correction steps on instead of closing")

        model.answer("Friday")
        #expect(await asked == "Which city? Porto\nWhich day? Friday")
    }

    @Test func closingTheCardHandsTheRestToTheAgent() async {
        let model = AgentQuestionModel()

        async let asked = model.put(questions(["Which city?", "Which day?"]), inSpace: space)
        #expect(await waitUntil { model.current != nil })

        model.answer("Lisbon")
        model.dismiss()

        let result = await asked
        #expect(result.contains("Q: Which city?\\nA: Lisbon"))
        #expect(result.contains("Choose sensible answers yourself"))
        #expect(result.contains("Which day?"), "the agent is told which ones are its to pick")
        #expect(model.ask == nil)
    }

    @Test func closingWithEverythingAnsweredHandsOverNothing() async {
        let model = AgentQuestionModel()

        async let asked = model.put(questions(["Which city?"]), inSpace: space)
        #expect(await waitUntil { model.current != nil })

        model.answer("Lisbon")

        #expect(await asked == "Q: Which city?\\nA: Lisbon")
    }

    @Test func aQuestionOnlyShowsInTheSpaceThatAskedIt() async {
        let model = AgentQuestionModel()

        async let asked = model.put(questions(["Which city?"]), inSpace: space)
        #expect(await waitUntil { model.current != nil })

        #expect(model.ask(inSpace: space) != nil)
        #expect(model.ask(inSpace: UUID()) == nil)
        #expect(model.ask(inSpace: nil) == nil)

        model.dismiss()
        _ = await asked
    }

    @Test func cancellingTheTurnReleasesTheWaitingTool() async {
        let model = AgentQuestionModel()

        async let asked = model.put(questions(["Which city?"]), inSpace: space)
        #expect(await waitUntil { model.current != nil })
        model.abandon()

        #expect(await asked.isEmpty)
        #expect(model.ask == nil)
    }

    @Test func askingAgainReplacesTheCardWaitingBefore() async {
        let model = AgentQuestionModel()

        async let first = model.put(questions(["Which city?"]), inSpace: space)
        #expect(await waitUntil { model.current?.text == "Which city?" })

        async let second = model.put(questions(["Which day?"]), inSpace: space)
        #expect(await waitUntil { model.current?.text == "Which day?" })

        #expect(await first.isEmpty)
        model.answer("Friday")
        #expect(await second == "Q: Which day?\\nA: Friday")
    }

    @Test func anAnswerWithNothingWaitingIsIgnored() {
        let model = AgentQuestionModel()
        model.answer("Lisbon")
        #expect(model.ask == nil)
    }
}

@MainActor
struct AgentAskedExchangeTests {
    @Test func everyQuestionAndAnswerIsReadBack() {
        let read = AgentAskedExchange.read("Q: Which city?\nA: Lisbon\nQ: Which day?\nA: Friday")

        #expect(read.count == 2)
        #expect(read.first?.question == "Which city?")
        #expect(read.first?.answer == .given("Lisbon"))
        #expect(read.last?.answer == .given("Friday"))
    }

    @Test func theHandoverBecomesItsOwnRow() {
        let read = AgentAskedExchange.read(
            "Q: Which city?\nA: Lisbon\n"
                + "Choose sensible answers yourself for the rest and carry on, "
                + "without asking again: Which day? · What budget?"
        )

        #expect(read.count == 2)
        #expect(read.last?.answer == .handedOver(["Which day?", "What budget?"]))
    }

    @Test func anAnswerHoldingAColonSurvivesBeingReadBack() {
        let read = AgentAskedExchange.read("Q: Which time?\nA: 10:30, or later")

        #expect(read.first?.answer == .given("10:30, or later"))
    }
}
