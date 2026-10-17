// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

struct AgentProgressMonitorTests {
    @Test func readsThatBringNothingNewAskForTheAnswerThenPause() {
        var monitor = AgentProgressMonitor(policy: .interactive)
        let windows = [
            "Aster desk lamp. Product code AST-4471. Price $129.", "esk lamp. Product code AST-4471. Price $129.",
            "Product code AST-4471. Price $129. Aster desk", "lamp. Product code AST-4471",
        ]
        let decisions = (0..<9).map { index in
            monitor.observe(name: "readPage", arguments: "{\"lookingFor\":\"price \(index)\"}",
                            output: "PAGE TEXT: " + windows[index % windows.count], failed: false)
        }
        #expect(decisions == [.proceed, .proceed, .proceed, .proceed, .answer, .proceed, .proceed, .proceed, .pause])
    }

    @Test func identifiersInsideTheOutputAreNotNewInformation() {
        var monitor = AgentProgressMonitor(policy: .interactive)
        let decisions = (0..<5).map { index in
            monitor.observe(name: "readPage", arguments: "{\"controlOffset\":\(index)}",
                            output: "pageID: 77423B04-20D0-43FC\nobservationID: mvbkt\(index)s0.3skh3vfx\(index)b\nPAGE TEXT: Price $129",
                            failed: false)
        }
        #expect(decisions.last == .answer)
    }

    @Test func anActionBetweenReadsKeepsTheStreakShort() {
        var monitor = AgentProgressMonitor(policy: .interactive)
        var decisions: [AgentProgressMonitor.Decision] = []
        for index in 1...6 {
            decisions.append(monitor.observe(name: "readPage", arguments: "{\"controlOffset\":\(index)}",
                                             output: "PAGE TEXT: page \(index)", failed: false))
            decisions.append(monitor.observe(name: "scrollPage", arguments: "{\"direction\":\"down\",\"step\":\(index)}",
                                             output: "Scrolled to part \(index)", failed: false))
        }
        #expect(decisions.allSatisfy { $0 == .proceed })
    }

    @Test func changedScreenshotsKeepRepeatedVisualActionsMoving() {
        var monitor = AgentProgressMonitor(policy: .interactive)
        for index in 1...8 {
            #expect(monitor.observe(
                name: "clickAtPoint", arguments: "{\"x\":100,\"y\":100}",
                output: "CONTROL: Browser action completed. Updated screenshot captured.",
                failed: false, images: [Data("page-\(index)".utf8)]
            ) == .proceed)
        }
    }

    @Test func unchangedScreenshotsStillRecoverThenPause() {
        var monitor = AgentProgressMonitor(policy: .interactive)
        let decisions = (1...6).map { index in
            monitor.observe(
                name: "clickAtPoint",
                arguments: index.isMultiple(of: 2) ? "{\"x\":100,\"y\":100}" : "{\"y\":100,\"x\":100}",
                output: "CONTROL: Browser action completed. Updated screenshot captured.",
                failed: false, images: [Data("unchanged-page".utf8)]
            )
        }
        #expect(decisions == [.proceed, .proceed, .recover, .proceed, .proceed, .pause])
    }

    @Test func differentCoordinatesAndInputMethodsCannotHideAnUnchangedPage() {
        var monitor = AgentProgressMonitor(policy: .interactive)
        let decisions = (1...6).map { index in
            monitor.observe(name: index.isMultiple(of: 2) ? "clickAtPoint" : "typeAtPointer",
                            arguments: "{\"page\":\"form\",\"x\":\(index * 10),\"y\":100}",
                            output: "Action completed.", failed: false, images: [Data("same-page".utf8)])
        }
        #expect(decisions == [.proceed, .proceed, .recover, .proceed, .proceed, .pause])
    }

    @Test func changingScreenshotsDoNotExcuseConsecutiveFailures() {
        var monitor = AgentProgressMonitor(policy: .interactive)
        let decisions = (1...6).map { index in
            monitor.observe(name: "clickAtPoint", arguments: "{}", output: "Input unverified.",
                            failed: true, images: [Data("page-\(index)".utf8)])
        }
        #expect(decisions == [.proceed, .proceed, .recover, .proceed, .proceed, .pause])
    }

    private func output(_ id: Int, text: String = "Pending", page: String = "same-page") -> String {
        "<page-content untrusted=\"true\">\npageID: \(page)\nPAGE TEXT:\n\(text)\n\nCONTROLS:\n[1] button \"Refresh\"\n\nobservationID: snapshot\(id)\n</page-content>"
    }

    @Test func freshObservationIDsCannotHideRepeatedReads() {
        var monitor = AgentProgressMonitor(policy: .interactive)
        let decisions = (1...6).map { monitor.observe(name: "readPage", arguments: "{}", output: output($0), failed: false) }
        #expect(decisions == [.proceed, .proceed, .recover, .proceed, .proceed, .pause])
    }

    @Test func actionCredentialsAndJSONOrderDoNotHideAStall() {
        var monitor = AgentProgressMonitor(policy: .interactive)
        for index in 1...3 {
            let arguments = index == 2 ? "{\"ref\":1,\"observationID\":\"two\"}" : "{\"observationID\":\"\(index)\",\"ref\":1}"
            #expect(monitor.observe(name: "clickOnPage", arguments: arguments, output: output(index), failed: false)
                == (index == 3 ? .recover : .proceed))
        }
    }

    @Test func changedContentTargetsAndPaginationRemainProgress() {
        var monitor = AgentProgressMonitor(policy: .interactive)
        for index in 1...6 {
            #expect(monitor.observe(name: "readPage", arguments: "{}", output: output(index, text: "Row \(index)"), failed: false) == .proceed)
            #expect(monitor.observe(name: "readPage", arguments: "{\"textOffset\":\(index)}", output: output(index), failed: false) == .proceed)
            #expect(monitor.observe(name: "readPage", arguments: "{}", output: output(index, page: "page\(index)"), failed: false) == .proceed)
        }
    }

    @Test func pageContentThatLooksLikeMetadataIsPreserved() {
        var monitor = AgentProgressMonitor(policy: .interactive)
        for index in 1...6 {
            #expect(monitor.observe(name: "readPage", arguments: "{}", output: output(index, text: "observationID: page-text-\(index)"), failed: false) == .proceed)
        }
    }

    @Test func scopedExecutionPolicyDoesNotChangeUserSettings() {
        AgentExecutionPolicy.$scoped.withValue(.init(maxModelRequests: 7)) {
            #expect(AgentExecutionPolicy.current.maxModelRequests == 7)
        }
        #expect(AgentExecutionPolicy.scoped == nil)
    }
}
