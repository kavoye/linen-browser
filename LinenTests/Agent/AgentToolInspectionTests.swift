// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation
import Testing

@testable import Linen

@MainActor
struct AgentToolInspectionTests {
    @Test func matchesRepeatedStepsAfterRelaunchWithoutPersistingActivityDetails() throws {
        let database = AppDatabase.temporary()
        let log = ConversationLog(database: database)
        let tab = UUID()
        let task = log.beginTask("Fill the trip form", tabID: tab)
        let first = try #require(log.beginTool(taskID: task, name: "clickOnPage", title: "Click control"))
        log.completeTool(taskID: task, stepID: first, detail: "private first detail")
        let second = try #require(log.beginTool(taskID: task, name: "clickOnPage", title: "Click control"))
        log.completeTool(taskID: task, stepID: second, detail: "private second detail")

        let firstCall = Transcript.ToolCall(id: "first", toolName: "clickOnPage", arguments: GeneratedContent(properties: [
            "selector": GeneratedContent("#origin")
        ]))
        let progressCall = Transcript.ToolCall(id: "progress", toolName: "updateProgress", arguments: GeneratedContent(properties: [
            "message": GeneratedContent("Working")
        ]))
        let secondCall = Transcript.ToolCall(id: "second", toolName: "clickOnPage", arguments: GeneratedContent(properties: [
            "selector": GeneratedContent("#destination")
        ]))
        let entries: [Transcript.Entry] = [
            .toolCalls(.init([firstCall, progressCall, secondCall])),
            .toolOutput(.init(id: "first", toolName: "clickOnPage", segments: [.text(.init(content: "Opened origin"))])),
            .toolOutput(.init(id: "second", toolName: "clickOnPage", segments: [.text(.init(content: "Opened destination"))])),
        ]
        log.saveCheckpoint(AgentCheckpoint(transcript: Transcript(entries: entries)), taskID: task)
        log.saveBlocking()

        let reopened = ConversationLog(database: database)
        let trace = try #require(reopened.latestTrace(forTab: tab))
        #expect(trace.steps.allSatisfy { $0.detail == nil && $0.links.isEmpty })
        let details = AgentToolInspection.forTrace(trace)
        #expect(details[first]?.result == "Opened origin")
        #expect(details[second]?.result == "Opened destination")
        #expect(details[first]?.input?.contains("#origin") == true)
        #expect(details[second]?.input?.contains("#destination") == true)
    }

    @Test func hidesTypedValueAndPageTextInFieldInspection() throws {
        let log = ConversationLog(database: .temporary())
        let tab = UUID()
        let task = log.beginTask("Fill a field", tabID: tab)
        let step = try #require(log.beginTool(taskID: task, name: "typeOnPage", title: "Fill field"))
        log.completeTool(taskID: task, stepID: step, detail: "private@example.test")

        let call = Transcript.ToolCall(id: "typed", toolName: "typeOnPage", arguments: GeneratedContent(properties: [
            "field": GeneratedContent("Destination"),
            "text": GeneratedContent("private@example.test")
        ]))
        let output = Transcript.ToolOutput(
            id: call.id, toolName: call.toolName,
            segments: [.text(.init(content: "Typed into Destination. PAGE TEXT: private@example.test"))]
        )
        log.saveCheckpoint(AgentCheckpoint(transcript: Transcript(entries: [
            .toolCalls(.init([call])), .toolOutput(output),
        ])), taskID: task)

        let trace = try #require(log.latestTrace(forTab: tab))
        let details = try #require(AgentToolInspection.forTrace(trace)[step])
        #expect(details.input?.contains("[hidden]") == true)
        #expect(details.input?.contains("private@example.test") == false)
        #expect(details.result == "Typed into Destination.")
    }

    @Test func hidesExpectedControlValueInOutcomeInspection() throws {
        let log = ConversationLog(database: .temporary())
        let tab = UUID()
        let task = log.beginTask("Check a saved field", tabID: tab)
        let step = try #require(log.beginTool(taskID: task, name: "verifyTaskOutcome", title: "Verify result"))
        let call = Transcript.ToolCall(id: "verify", toolName: "verifyTaskOutcome", arguments: GeneratedContent(properties: [
            "outcomeID": GeneratedContent("contact"),
            "expectedValue": GeneratedContent("private@example.test"),
            "expectedText": GeneratedContent("private@example.test"),
        ]))
        log.saveCheckpoint(AgentCheckpoint(transcript: Transcript(entries: [
            .toolCalls(.init([call])),
        ])), taskID: task)

        let trace = try #require(log.latestTrace(forTab: tab))
        let details = try #require(AgentToolInspection.forTrace(trace)[step])
        #expect(details.input?.contains("[hidden]") == true)
        #expect(details.input?.contains("private@example.test") == false)
    }
}
