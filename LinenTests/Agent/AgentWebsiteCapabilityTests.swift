// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation
import Testing
import WebKit

@testable import Linen

@MainActor
@Suite(.serialized, .boundedWebViews)
struct AgentWebsiteCapabilityTests {
    @Test(arguments: [false, true])
    func uploadUsesOnlyFilesReturnedByTheChooser(cancelled: Bool) async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("linen-upload-\(UUID().uuidString).txt")
        try Data("A user-selected document".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        var services = AgentToolkit.Services.live
        var selections = 0
        services.chooseFiles = { _ in
            selections += 1
            return cancelled ? nil : [file]
        }
        let fixture = try await ComputerWorkflowFixture(services: services)
        defer { fixture.close() }
        _ = try await fixture.tab.webView.evaluateJavaScript("document.body.innerHTML='<input type=file aria-label=Document>'")
        _ = await fixture.toolkit.readPage()
        let observation = try #require(PageDriver.observations.object(forKey: fixture.tab.webView))
        let ref = try #require(observation.refs.first)
        let output = try await ChooseFilesOnPageTool(toolkit: fixture.toolkit).call(arguments: .init(page: nil, observationID: observation.id, ref: ref))
        #expect(selections == 1)
        #expect(output.contains(cancelled ? "cancelled" : "selected 1 files"))
        #expect(try await fixture.tab.webView.evaluateJavaScript("document.querySelector('input').files.length") as? Int == (cancelled ? 0 : 1))
        #expect(!output.contains(file.path))
    }

    @Test func aFinishedDownloadIsVerifiedAndOtherTabsAreExcluded() async throws {
        let fixture = try await ComputerWorkflowFixture()
        defer { fixture.close() }
        let server = try await HTTPFixtureServer.start(routes: [
            "/": .html("<a href='/file'>Download document</a>"),
            "/file": .download(Data("Test document".utf8), filename: "document.txt"),
        ])
        let url = try server.url()
        fixture.tab.load(url)
        #expect(await waitUntil { fixture.tab.committedURL == url && !fixture.tab.isLoading })
        fixture.tab.assistantAccess.pageChanged(url: url)
        fixture.tab.assistantAccess.set(.control)
        let downloads = fixture.browser.downloads
        let foreign = downloads.beginItem(source: try server.url("/file"), sourceTabID: UUID())
        _ = try await fixture.tab.webView.evaluateJavaScript("document.querySelector('a').click()")
        #expect(await waitUntil { downloads.items.contains { $0.sourceTabID == fixture.tab.id && $0.state == .finished } })
        let item = try #require(downloads.items.first { $0.sourceTabID == fixture.tab.id })
        let recorded = fixture.toolkit.taskLedger.add(id: "download", requirement: "Download the document")
        #expect(recorded)
        let output = await fixture.toolkit.inspectDownloads(page: nil, downloadID: item.id.uuidString, outcomeID: "download")
        #expect(output.contains("finished"))
        #expect(!output.contains(foreign.uuidString))
        #expect(fixture.toolkit.taskLedger.completion == .verified)
        try FileManager.default.removeItem(at: #require(item.destination))
        let missing = await fixture.toolkit.inspectDownloads(page: nil, downloadID: item.id.uuidString, outcomeID: "download")
        #expect(missing.contains("Verification failed"))
        #expect(fixture.toolkit.taskLedger.completion == .unverified)
    }

    @Test func verificationRequiresTheCurrentURLAndFreshVisibleText() async throws {
        let fixture = try await ComputerWorkflowFixture()
        defer { fixture.close() }
        let toolkit = fixture.toolkit
        let acceptedOutcome1 = toolkit.taskLedger.add(id: "saved", requirement: "Save the record")
        #expect(acceptedOutcome1)
        let url = try #require(fixture.tab.webView.url?.absoluteString)
        _ = try await fixture.tab.webView.evaluateJavaScript("document.querySelector('#status').textContent='Saved record 42'")
        let verified = await toolkit.verifyOutcome(id: "saved", page: nil, expectedURL: url, expectedText: "Saved record 42")
        #expect(verified.contains("Outcome verified"))
        #expect(toolkit.taskLedger.completion == .verified)

        _ = try await fixture.tab.webView.evaluateJavaScript("document.querySelector('#status').textContent='Save failed'")
        let missing = await toolkit.verifyOutcome(id: "saved", page: nil, expectedURL: url, expectedText: "Saved record 42")
        #expect(missing.contains("Verification failed"))
        #expect(toolkit.taskLedger.completion == .unverified)
        let wrongURL = await toolkit.verifyOutcome(id: "saved", page: nil, expectedURL: url + "other", expectedText: "Save failed")
        #expect(wrongURL.contains("URL does not match"))
    }

    @Test func embeddedSitePermissionIsSeparateAndFrameActionsAreScoped() async throws {
        let fixture = try await ComputerWorkflowFixture()
        defer { fixture.close() }
        let child = try await HTTPFixtureServer.start(routes: ["/": .html("""
            <p id="result">Embedded private record</p>
            <button onclick="document.querySelector('#result').textContent='Embedded saved record'">Save embedded record</button>
            """),
        ])
        let childURL = try child.url()
        let encoded = try #require(PageDriver.jsonString(childURL.absoluteString))
        _ = try await fixture.tab.webView.evaluateJavaScript("const frame=document.createElement('iframe');frame.src=\(encoded);document.body.append(frame)")
        #expect(await waitUntil { !PageFrameRegistry.shared.targets(in: fixture.tab.webView).isEmpty })
        let target = try #require(PageFrameRegistry.shared.targets(in: fixture.tab.webView).first)
        let access = try #require(fixture.toolkit.embeddedAccess(for: childURL, in: fixture.tab.webView))
        #expect(access.effectivePolicy == .ask)
        access.set(.deny)
        let read = ReadFrameTool(toolkit: fixture.toolkit)
        let arguments = ReadFrameTool.Arguments(page: nil, frameID: target.id, lookingFor: nil, textOffset: nil, controlOffset: nil)
        let denied = try await read.call(arguments: arguments)
        #expect(!denied.contains("Embedded private record"))

        access.set(.control)
        let output = try await read.call(arguments: arguments)
        #expect(output.contains("Embedded private record"))
        let observation = try #require(PageDriver.observations.object(forKey: fixture.tab.webView))
        let ref = try #require(observation.refs.first)
        let action = ActInFrameTool(toolkit: fixture.toolkit)
        let clicked = try await action.call(arguments: .init(page: nil, frameID: target.id, observationID: observation.id,
            ref: ref, action: "click", text: nil, checked: nil))
        #expect(clicked.contains("Clicked"))
        #expect(clicked.contains("Embedded saved record"))
        #expect(!fixture.toolkit.lastToolFailed)
        let acceptedOutcome2 = fixture.toolkit.taskLedger.add(id: "frame", requirement: "Save embedded record")
        #expect(acceptedOutcome2)
        let verified = await fixture.toolkit.verifyOutcome(id: "frame", page: nil, frameID: target.id,
            expectedURL: childURL.absoluteString, expectedText: "Embedded saved record")
        #expect(verified.contains("Outcome verified"))

        _ = try await fixture.tab.webView.evaluateJavaScript("document.querySelector('iframe').remove()")
        #expect(await waitUntil { !(await PageFrameRegistry.shared.isLive(target, in: fixture.tab.webView)) })
        let stale = try await read.call(arguments: arguments)
        #expect(!stale.contains("Embedded saved record"))
    }

    @Test func doubleClickAndDragToolsChangeThePage() async throws {
        let fixture = try await ComputerWorkflowFixture()
        defer { fixture.close() }
        _ = try await fixture.tab.webView.evaluateJavaScript("""
            document.querySelector('button').addEventListener('dblclick', e => { if(e.isTrusted) window.doubleHit=true; });
            const box = document.createElement('div'); box.id = 'drag-box';
            box.style = 'position:absolute;left:40px;top:180px;width:60px;height:40px;background:blue';
            document.body.append(box);
            let origin;
            box.addEventListener('mousedown', e => { origin = e.clientX; });
            document.addEventListener('mousemove', e => {
              if(origin !== undefined && e.buttons===1) box.style.left = (40 + e.clientX - origin) + 'px';
            });
            document.addEventListener('mouseup', () => { origin = undefined; });
            """)
        _ = await fixture.toolkit.screenshotPage()
        let frame = try #require(fixture.toolkit.computerObservation)
        let x = Int(60 * frame.pixels.width / frame.geometry.width)
        let y = Int(110 * frame.pixels.height / frame.geometry.height)
        let double = DoubleClickAtPointTool(toolkit: fixture.toolkit)
        _ = try await double.call(arguments: .init(page: nil, x: x, y: y))
        #expect(try await fixture.tab.webView.evaluateJavaScript("window.doubleHit === true") as? Bool == true)
        _ = await fixture.toolkit.screenshotPage()
        let drag = DragOnPageTool(toolkit: fixture.toolkit)
        let dragY = Int(200 * frame.pixels.height / frame.geometry.height)
        let distance = Int(30 * frame.pixels.width / frame.geometry.width)
        let result = try await drag.call(arguments: .init(page: nil, path: [.init(x: x, y: dragY), .init(x: x + distance, y: dragY)]))
        #expect(result.contains("Drag events dispatched"))
        #expect(try await fixture.tab.webView.evaluateJavaScript("document.querySelector('#drag-box').style.left === '70px'") as? Bool == true)
        let invalid = try await drag.call(arguments: .init(page: nil, path: []))
        #expect(invalid.contains("2–50"))
    }

    @Test func htmlDragTransfersDataToADropTarget() async throws {
        let fixture = try await ComputerWorkflowFixture()
        defer { fixture.close() }
        _ = try await fixture.tab.webView.evaluateJavaScript("""
            document.body.innerHTML = `<div id="source" draggable="true"
              style="position:absolute;left:40px;top:180px;width:60px;height:40px">Record</div>
              <div id="destination" style="position:absolute;left:160px;top:180px;width:100px;height:40px">Drop here</div>`;
            document.querySelector('#source').addEventListener('dragstart', e => e.dataTransfer.setData('text/plain','Record 42'));
            document.querySelector('#destination').addEventListener('dragover', e => e.preventDefault());
            document.querySelector('#destination').addEventListener('drop', e => {
              e.preventDefault(); e.currentTarget.textContent = e.dataTransfer.getData('text/plain');
            });
            """)
        _ = await fixture.toolkit.screenshotPage()
        let frame = try #require(fixture.toolkit.computerObservation)
        let start = DragOnPageTool.Point(x: Int(60 * frame.pixels.width / frame.geometry.width),
            y: Int(200 * frame.pixels.height / frame.geometry.height))
        let end = DragOnPageTool.Point(x: Int(180 * frame.pixels.width / frame.geometry.width), y: start.y)
        let output = try await DragOnPageTool(toolkit: fixture.toolkit).call(arguments: .init(page: nil, path: [start, end]))
        #expect(output.contains("Drag events dispatched"))
        #expect(try await fixture.tab.webView.evaluateJavaScript("document.querySelector('#destination').textContent") as? String == "Record 42")
    }
}

@MainActor
struct AgentFileSelectionTests {
    @Test func framePortsUseTheSecurityOriginsDefaultPort() throws {
        #expect(PageFrameRegistry.portMatches(url: try #require(URL(string: "https://example.com/frame")), securityPort: 0))
        #expect(PageFrameRegistry.portMatches(url: try #require(URL(string: "http://example.com/frame")), securityPort: 0))
        #expect(!PageFrameRegistry.portMatches(url: try #require(URL(string: "https://example.com:8443/frame")), securityPort: 0))
        #expect(PageFrameRegistry.portMatches(url: try #require(URL(string: "https://example.com:8443/frame")), securityPort: 8443))
    }
    @Test func cancellationResumesTheWaitingTool() async {
        let selection = PageFileSelection(origin: "https://example.com", observationID: "a", validate: { true })
        var cancelledPanel = false
        selection.cancelPanel = { cancelledPanel = true }
        let wait = Task { await selection.wait() }
        wait.cancel()
        #expect(await wait.value == nil)
        #expect(cancelledPanel)
    }

    @Test func aCompletedSelectionCanOnlyResolveOnce() async {
        let selection = PageFileSelection(origin: "https://example.com", observationID: "a", validate: { true })
        selection.finish(2)
        selection.finish(9)
        #expect(await selection.wait() == 2)
    }
}
