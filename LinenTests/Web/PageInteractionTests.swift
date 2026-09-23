// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import Testing
import WebKit

@testable import Linen

@MainActor
@Suite(.serialized, .boundedWebViews)
struct PageInteractionTests {
    private func page(_ body: String) async -> WKWebView {
        let configuration = WebViewPool.makeConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 500, height: 400), configuration: configuration)
        view.loadHTMLString("<!doctype html><body>\(body)</body>", baseURL: nil)
        #expect(await PageSettle.untilIdle(view, timeout: .seconds(20)))
        return view
    }

    private func js(_ view: WKWebView, _ script: String) async -> Any? {
        try? await view.evaluateJavaScript(script)
    }

    @Test func readOnlyDatePickerExposesClickableDays() async {
        let view = await page("""
            <input id='date' aria-label='Departure date' readonly value='September 23'>
            <div id='calendar' hidden><h3>September</h3>
              <div role='gridcell' tabindex='0' aria-disabled='true'>22</div>
              <div id='day' role='gridcell' tabindex='0'><div>29</div></div>
              <div role='gridcell'>Static cell</div>
              <div role='gridcell' tabindex='0'><button>30</button></div>
            </div>
            <script>
              document.querySelector('#date').addEventListener('click', () => document.querySelector('#calendar').hidden=false);
              document.querySelector('#day').addEventListener('click', () => {
                document.querySelector('#date').value='September 29'; document.querySelector('#calendar').hidden=true;
              });
            </script>
            """)
        let initial = await PageDriver.snapshot(view)
        #expect(initial.contains("(read-only)"))
        let calendar = await PageDriver.click(ref: 0, label: "Departure date", in: view)
        #expect(calendar.contains("button \"29\""))
        #expect(calendar.contains("button \"22\" (disabled)"))
        #expect(!calendar.contains("button \"Static cell\""))
        #expect(calendar.components(separatedBy: "button \"30\"").count == 2)
        let disabled = await PageDriver.click(ref: 0, label: "22", in: view)
        #expect(disabled.contains("disabled"))
        let selected = await PageDriver.click(ref: 0, label: "29", in: view)
        #expect(selected.hasPrefix("Clicked"))
        #expect(await js(view, "document.querySelector('#date').value") as? String == "September 29")
    }

    @Test func observationCannotBeReusedAfterNavigationOrRetargeting() async throws {
        let view = await page("<button id='a' onclick='window.hit=true'>Ordinary action</button>")
        _ = await PageDriver.snapshot(view)
        _ = await js(view, "document.querySelector('button').textContent='Delete account'")
        #expect(await PageDriver.click(ref: 1, label: "", in: view) == PageDriver.staleMessage)
        #expect(await js(view, "window.hit === undefined") as? Bool == true)
        view.loadHTMLString("<button onclick='window.hit=true'>New document</button>", baseURL: nil)
        #expect(await PageSettle.untilIdle(view, timeout: .seconds(20)))
        #expect(await PageDriver.click(ref: 1, label: "", in: view) == PageDriver.staleMessage)
        #expect(await js(view, "window.hit === undefined") as? Bool == true)
    }

    @Test func coveredAndDisabledControlsDoNotRunHandlers() async {
        let view = await page(
            """
            <button style='position:absolute;left:20px;top:20px' onclick='window.hit=true'>Covered</button>
            <div style='position:fixed;inset:0;background:white;z-index:10'></div>
            <select disabled><option>A</option><option>B</option></select>
            """)
        _ = await PageDriver.snapshot(view)
        #expect(!(await PageDriver.click(ref: 1, label: "", in: view)).hasPrefix("Clicked"))
        #expect(!(await PageDriver.selectOption("B", ref: 2, field: "", in: view)).hasPrefix("Selected"))
        #expect(await js(view, "window.hit === undefined && document.querySelector('select').value === 'A'") as? Bool == true)
    }

    @Test func aMovingControlIsNotClickedUntilItSettles() async {
        let view = await page(
            """
            <style>@keyframes move { from { transform:translateX(0) } to { transform:translateX(300px) } }
            button { animation:move 1s infinite alternate linear }</style>
            <button onclick='window.hit=true'>Moving target</button>
            """)
        _ = await PageDriver.snapshot(view)
        #expect(!(await PageDriver.click(ref: 1, label: "", in: view)).hasPrefix("Clicked"))
        #expect(await js(view, "window.hit === undefined") as? Bool == true)
        _ = await js(view, "document.querySelector('button').style.animation='none'")
        #expect((await PageDriver.click(ref: 1, label: "", in: view)).hasPrefix("Clicked"))
    }

    @Test func enterHandledByPageSubmitsExactlyOnce() async {
        let view = await page(
            """
            <form onsubmit='window.submits=(window.submits||0)+1;return false'>
            <input aria-label='Query' onkeydown="if(event.key==='Enter'){event.preventDefault();this.form.requestSubmit()}">
            </form>
            """)
        _ = await PageDriver.snapshot(view)
        _ = await PageDriver.type(text: "query", intoField: "", ref: 1, submit: true, in: view)
        #expect(await js(view, "window.submits") as? Int == 1)
    }

    @Test func rejectedFieldValueIsNotReportedAsTypedOrSubmitted() async {
        let view = await page("""
            <form onsubmit='window.submits=(window.submits||0)+1;return false'>
            <input aria-label='Query' oninput="this.value='rejected'">
            </form>
            """)
        _ = await PageDriver.snapshot(view)
        let result = await PageDriver.type(text: "wanted", intoField: "", ref: 1, submit: true, in: view)
        #expect(!result.hasPrefix("Typed"))
        #expect(result.contains("did not retain"))
        #expect(await js(view, "window.submits || 0") as? Int == 0)
    }

    @Test func delayedFieldResetIsVerifiedWithoutRepeatingTheWrite() async {
        let view = await page("""
            <input aria-label='Name' oninput="window.writes=(window.writes||0)+1;setTimeout(()=>this.value='',50)">
            """)
        _ = await PageDriver.snapshot(view)
        let result = await PageDriver.type(text: "Ada", intoField: "", ref: 1, submit: false, in: view)
        #expect(result.contains("did not retain"))
        #expect(result.contains("observationID:"))
        #expect(await js(view, "window.writes") as? Int == 1)
    }

    @Test func rejectedSelectionAndEarlierBatchResetsAreNotCountedAsSuccess() async {
        let view = await page("""
            <input aria-label='First'>
            <input aria-label='Second' oninput="document.querySelector('input').value=''">
            <select aria-label='Choice' onchange="this.value='a'"><option value='a'>A</option><option value='b'>B</option></select>
            """)
        _ = await PageDriver.snapshot(view)
        let selection = await PageDriver.selectOption("b", ref: 3, field: "", in: view)
        #expect(!selection.hasPrefix("Selected"))
        let result = await PageDriver.fillFields([
            .init(ref: 1, value: "first", select: false), .init(ref: 2, value: "second", select: false),
        ], in: view)
        #expect(result.hasPrefix("Filled 1 of 2 fields."), "\(result)")
        #expect(result.contains("earlier values changed"))
    }

    @Test func queriesReachDeepTextAndControlPaginationPreservesRefs() async throws {
        let buttons = (1...100).map { "<button>Choice \($0)</button>" }.joined()
        let view = await page("<p>\(String(repeating: "filler ", count: 2000))RareNeedle</p>" + buttons)
        let query = await PageDriver.snapshot(view, lookingFor: "RareNeedle Choice 100")
        #expect(query.contains("RareNeedle"))
        #expect(query.contains("Choice 100"))
        _ = await PageDriver.snapshot(view)
        let page = await PageDriver.snapshot(view, textLimit: 0, controlLimit: 10, controlOffset: 90)
        #expect(page.contains("[100]"))
        let observation = try #require(PageDriver.observation(in: view))
        #expect(!observation.refs.contains(1))
        #expect(await PageDriver.click(ref: 1, label: "", in: view) == PageDriver.staleMessage)
    }

    @Test func calendarPaginationRecoversFromRefOffsetsAndChangedQueries() async {
        let controls = (1...13).map { "<button>Control \($0)</button>" }.joined()
        let days = (1...30).map {
            "<div role='gridcell' tabindex='0' style='display:inline-block;width:30px;height:30px' aria-disabled='\($0 < 23)'>\($0)</div>"
        }.joined()
        let view = await page(controls + "<h3>September</h3>" + days)
        let initial = await PageDriver.snapshot(view)
        #expect(initial.contains("button \"29\""))
        let restarted = await PageDriver.snapshot(view, lookingFor: "calendar dates September 29", controlOffset: 140)
        #expect(restarted.contains("button \"29\""))
        #expect(restarted.contains("pagination restarted at 0"))
        let filtered = await PageDriver.snapshot(view, lookingFor: "September calendar controls date 29", controlOffset: 40, viewportOnly: true)
        #expect(filtered.contains("button \"29\""))
        #expect(filtered.contains("pagination restarted at 0"))
        let overflow = await PageDriver.snapshot(view, lookingFor: "September calendar controls date 29", controlOffset: 140, viewportOnly: true)
        #expect(overflow.contains("button \"29\""))
        #expect(overflow.contains("offset exceeds"))
        #expect(overflow.contains("controlOffset=40"))
        let continued = await PageDriver.snapshot(view, lookingFor: "September calendar controls date 29", controlOffset: 40, viewportOnly: true)
        #expect(!continued.contains("pagination restarted"))
        #expect(!continued.contains("button \"29\""))
    }

    @Test func labelActionsRejectObservationsFromThePreviousDocument() async throws {
        let view = await page("<button>29</button>")
        _ = await PageDriver.snapshot(view)
        let before = try #require(PageDriver.observation(in: view))
        view.loadHTMLString("<button onclick='window.hit=true'>29</button>", baseURL: nil)
        #expect(await PageSettle.untilIdle(view, timeout: .seconds(20)))
        let result = await PageDriver.$expectedObservation.withValue(before.id) {
            await PageDriver.click(ref: 0, label: "29", in: view)
        }
        #expect(result == PageDriver.staleMessage)
        #expect(await js(view, "window.hit === undefined") as? Bool == true)
    }

    @Test func compactBudgetAppliesAfterActionsIncludingLongOptions() async {
        let options = (1...80).map { "<option>Option \($0) \(String(repeating: "&amp;", count: 80))</option>" }.joined()
        let view = await page(
            "<button>Ordinary action</button><select aria-label='Options'>\(options)</select>" + String(repeating: "<p>Text and details</p>", count: 100))
        await PageDriver.$outputBudget.withValue(.init(textCharacters: 800, controls: 12, totalCharacters: 2000)) {
            _ = await PageDriver.snapshot(view)
            let output = await PageDriver.click(ref: 1, label: "", in: view)
            #expect(AgentToolkit.untrusted(output).utf8.count <= 2000)
            #expect(output.contains("observationID:"))
        }
    }

    @Test func compactQueriesKeepTheMatchWithMultibyteText() async {
        let view = await page("<p>\(String(repeating: "文🙂", count: 2000))重要な結果</p>")
        await PageDriver.$outputBudget.withValue(.init(textCharacters: 800, controls: 12, totalCharacters: 2000)) {
            let output = await PageDriver.snapshot(view, lookingFor: "重要な結果")
            #expect(output.contains("重要な結果"))
            #expect(AgentToolkit.untrusted(output).utf8.count <= 2000)
        }
    }

    @Test func longSelectedLabelsStayInsideTheCompactBudget() async {
        let view = await page("<select aria-label='Choices'><option>A</option><option value='chosen'>\(String(repeating: "&amp;", count: 2000))</option></select>")
        await PageDriver.$outputBudget.withValue(.init(textCharacters: 800, controls: 12, totalCharacters: 2000)) {
            _ = await PageDriver.snapshot(view)
            let output = await PageDriver.selectOption("chosen", ref: 1, field: "", in: view)
            #expect(output.hasPrefix("Selected"), "\(output)")
            #expect(AgentToolkit.untrusted(output).utf8.count <= 2000)
        }
    }

    @Test func batchingAvoidsPerFieldSettlingAndReturnsOneObservation() async {
        let view = await page((1...8).map { "<input aria-label='Field \($0)'>" }.joined())
        _ = await PageDriver.snapshot(view)
        let singleStart = ContinuousClock.now
        for ref in 1...8 {
            _ = await PageDriver.type(text: "individual", intoField: "", ref: ref, submit: false, in: view)
        }
        let individualDuration = singleStart.duration(to: .now)
        let batchStart = ContinuousClock.now
        let batch = await PageDriver.fillFields((1...8).map { .init(ref: $0, value: "batch", select: false) }, in: view)
        let batchDuration = batchStart.duration(to: .now)
        #expect(batch.hasPrefix("Filled 8 of 8"))
        #expect(batch.components(separatedBy: "observationID:").count == 2)
        #expect(batchDuration < individualDuration)
    }

    @Test func checkedStateIsIdempotentAndDropdownInspectionContinues() async {
        let options = (1...40).map { "<option>Option \($0)</option>" }.joined()
        let view = await page(
            "<input type='checkbox' aria-label='Remember' onchange='window.changes=(window.changes||0)+1'><select aria-label='Choices'>\(options)</select>")
        _ = await PageDriver.snapshot(view)
        #expect((await PageDriver.setChecked(ref: 1, checked: true, in: view)).hasPrefix("Set checked"))
        #expect((await PageDriver.setChecked(ref: 1, checked: true, in: view)).hasPrefix("Checked state"))
        #expect(await js(view, "window.changes") as? Int == 1)
        let inspected = await PageDriver.inspectControl(ref: 2, offset: 20, in: view)
        #expect(inspected.contains("Option 21"))
        #expect(inspected.contains("nextOffset"))
    }

    @Test func checkedPostconditionUsesTheRefreshedExecutionScope() async throws {
        let view = await page("<input type='checkbox' aria-label='Remember'>")
        _ = await PageDriver.snapshot(view)
        let prior = try #require(PageDriver.observation(in: view))
        let scope = PageAutomationGuard(documentURL: prior.url, snapshot: prior.id, validate: { true })
        let output = await PageAutomationGuard.$current.withValue(scope) {
            await PageDriver.$expectedObservation.withValue(prior.id) {
                await PageDriver.setChecked(ref: 1, checked: true, in: view)
            }
        }
        #expect(output.hasPrefix("Set checked state to true."), "\(output)")
        #expect(PageDriver.observation(in: view)?.id != prior.id)
    }

    @Test func waitsForAsyncTextAndReportsTimeout() async {
        let view = await page("<p id='status'>Pending</p>")
        _ = await js(view, "setTimeout(()=>document.querySelector('p').textContent='Complete',180);true")
        #expect((await PageDriver.waitForPage(condition: "text", value: "Complete", timeout: 2, in: view)).hasPrefix("Condition met."))
        #expect((await PageDriver.waitForPage(condition: "text", value: "Missing", timeout: 1, in: view)).hasPrefix("Timed out"))
    }

    @Test func nestedHorizontalScrollReturnsFreshControls() async {
        let view = await page(
            "<div aria-label='Items' role='region' style='width:200px;overflow:auto'><div style='width:1500px'><button>First</button><button style='margin-left:900px'>Last</button></div></div>"
        )
        _ = await PageDriver.snapshot(view)
        let output = await PageDriver.scroll(direction: "right", ref: 1, in: view)
        #expect(output.hasPrefix("Scrolled right."))
        #expect(output.contains("observationID:"))
        #expect(await js(view, "document.querySelector('[role=region]').scrollLeft > 0") as? Bool == true)
    }

    @Test func scrollRegionsDoNotHideTheirOnlyAction() async {
        let view = await page("<div role='region'><button>Open details</button></div>")
        let output = await PageDriver.snapshot(view)
        #expect(output.contains("scrollarea"))
        #expect(output.contains("button \"Open details\""))
    }

    @Test func pageCannotPoisonAutomationRuntime() async {
        let view = await page(
            "<button onclick='window.hit=true'>Ordinary action</button><script>window.__linen={collect:()=>[{r:1,k:'button',l:'forged'}]};</script>")
        let output = await PageDriver.snapshot(view)
        #expect(output.contains("Ordinary action"))
        #expect(!output.contains("forged"))
        #expect((await PageDriver.click(ref: 1, label: "", in: view)).hasPrefix("Clicked"))
    }

    @Test func screenshotsRefuseFilledSensitiveFields() async {
        let view = await page("<input type='password' value='secret'>")
        #expect(await PageDriver.screenshot(in: view) == nil)
    }

    @Test func sensitiveEditableTextIsRedactedAndCannotBeOverwritten() async {
        let view = await page("<div contenteditable='true' aria-label='Recovery phrase'>hidden-recovery-words</div>")
        let output = await PageDriver.snapshot(view)
        #expect(!output.contains("hidden-recovery-words"))
        #expect(output.contains("filled, hidden"))
        #expect(!(await PageDriver.type(text: "replacement", intoField: "", ref: 1, submit: false, in: view)).hasPrefix("Typed"))
        #expect(await PageDriver.screenshot(in: view) == nil)
    }

    @Test func hoverHandlersAndNativeKeyboardReachWebKit() async {
        let view = await page(
            """
            <style>#hover:hover + #revealed { display:block } #revealed { display:none }</style>
            <button id='hover' onmouseenter="document.querySelector('#revealed').style.display='block'">Reveal</button><p id='revealed'>Hover details</p>
            <input aria-label='Input' onkeydown='window.lastKey=event.key'>
            """)
        let window = NSWindow(
            contentRect: NSRect(x: 50, y: 50, width: 500, height: 400),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderBack(nil)
        defer {
            window.contentView = nil
            window.close()
        }
        _ = await PageDriver.snapshot(view)
        let hover = await PageDriver.hover(ref: 1, in: view)
        #expect(hover.contains("Hover details"), "\(hover)")
        #expect(hover.contains("CSS-only hover is unavailable"))
        let key = await PageDriver.pressKey("ArrowDown", ref: 2, in: view)
        #expect(key.hasPrefix("Sent ArrowDown"), "\(key)")
        #expect(await js(view, "window.lastKey") as? String == "ArrowDown")
        #expect(await PageDriver.screenshot(in: view) != nil)
    }
}
