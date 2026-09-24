// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import Testing
import WebKit

@testable import Linen

@MainActor
@Suite(.serialized, .boundedWebViews)
struct PageComputerInputTests {
    private func page(_ html: String) async -> (WKWebView, NSWindow) {
        let config = WebViewPool.makeConfiguration()
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 500, height: 400), configuration: config)
        let foreground = ProcessInfo.processInfo.environment["LINEN_COMPUTER_FOREGROUND_TEST"] == "1"
        let window = NSWindow(contentRect: NSRect(x: 50, y: 50, width: 500, height: 400),
                              styleMask: foreground ? [.titled, .closable] : [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderBack(nil)
        window.title = "Linen computer input verification"
        view.loadHTMLString("<!doctype html><body style='margin:0'>\(html)</body>", baseURL: nil)
        #expect(await PageSettle.untilIdle(view))
        if foreground {
            #expect(await waitUntil(timeout: .seconds(60)) { NSApp.isActive && window.isKeyWindow })
        }
        return (view, window)
    }

    private func point(_ x: Double, _ y: Double, frame: PageComputerFrame, type: String = "click") -> OpenAIJSON {
        ["type": .string(type), "button": "left", "x": .number(x * frame.pixels.width / frame.geometry.width), "y": .number(y * frame.pixels.height / frame.geometry.height)]
    }

    @Test func nativeClickTypeKeyAndScrollReachThePage() async throws {
        let (view, window) = await page("""
            <button style='position:absolute;left:20px;top:20px;width:120px;height:40px' onclick='window.clicks=(window.clicks||0)+1'>Choose</button>
            <input id='query' aria-label='Query' style='position:absolute;left:20px;top:90px;width:160px;height:40px' onkeydown='window.lastKey=event.key'>
            <div style='position:absolute;top:200px;height:100px;width:300px;overflow:auto' id='scroll'><div style='height:2000px'>Items</div></div>
            <script>window.events=[];for(const type of ['mousedown','mouseup','click'])
              document.addEventListener(type,e=>window.events.push([type,e.clientX,e.clientY,e.target.tagName,e.isTrusted]));</script>
            """)
        defer { window.close() }
        var (frame, _) = try await PageDriver.computerFrame(in: view)
        try await PageDriver.computerAction(point(60, 40, frame: frame), frame: frame, in: view)
        #expect(view.subviews.contains { $0.identifier?.rawValue == "assistant-pointer" })
        #expect(await PageSettle.untilIdle(view))
        let clicks = try await view.evaluateJavaScript("window.clicks || 0") as? Int
        let events = try await view.evaluateJavaScript("JSON.stringify(window.events)") as? String
        #expect(clicks == 1, "Fixture input events: \(events ?? "missing")")
        (frame, _) = try await PageDriver.computerFrame(in: view)
        try await PageDriver.computerAction(point(60, 110, frame: frame), frame: frame, in: view)
        try await PageDriver.computerAction(["type": "type", "text": "penguin"], frame: frame, in: view)
        #expect(await PageSettle.untilIdle(view))
        #expect(try await view.evaluateJavaScript("document.querySelector('#query').value") as? String == "penguin")
        try await PageDriver.computerAction(["type": "keypress", "keys": ["ENTER"]], frame: frame, in: view)
        #expect(await PageSettle.untilIdle(view))
        #expect(try await view.evaluateJavaScript("window.lastKey") as? String == "Enter")
        var scroll = point(80, 250, frame: frame, type: "scroll")
        scroll["scroll_x"] = 0
        scroll["scroll_y"] = 150
        try await PageDriver.computerAction(scroll, frame: frame, in: view)
        #expect(try await view.evaluateJavaScript("document.querySelector('#scroll').scrollTop") as? Int == 150)
    }

    @Test func framesRejectNavigationMutationResizeAndAnotherPage() async throws {
        let (view, window) = await page("<button>Choose</button>")
        defer { window.close() }
        let (frame, _) = try await PageDriver.computerFrame(in: view)
        _ = try await view.evaluateJavaScript("document.querySelector('button').textContent='Changed'")
        await #expect(throws: PageComputerFailure.self) { try await PageDriver.validateComputerFrame(frame, in: view, checkRevision: true) }
        view.setFrameSize(CGSize(width: 450, height: 400))
        await #expect(throws: PageComputerFailure.self) { try await PageDriver.validateComputerFrame(frame, in: view, checkRevision: false) }
        view.setFrameSize(frame.geometry)
        view.loadHTMLString("<p>New document</p>", baseURL: nil)
        #expect(await PageSettle.untilIdle(view))
        await #expect(throws: PageComputerFailure.self) { try await PageDriver.validateComputerFrame(frame, in: view, checkRevision: false) }
    }

    @Test func coordinateClickSurvivesUnrelatedPageChangesButRejectsChangedTarget() async throws {
        let (view, window) = await page("""
            <button id='date' style='position:absolute;left:20px;top:20px;width:100px;height:50px'
                onclick='window.selected=true'>29</button>
            <p id='carousel' style='position:absolute;left:250px;top:200px'>First slide</p>
            """)
        defer { window.close() }

        let (frame, _) = try await PageDriver.computerFrame(in: view)
        let action = point(60, 45, frame: frame)
        _ = try await view.evaluateJavaScript("document.querySelector('#carousel').textContent='Second slide'")
        try await PageDriver.validateComputerAction(action, frame: frame, in: view)
        try await PageDriver.computerAction(action, frame: frame, in: view)
        #expect(try await view.evaluateJavaScript("window.selected === true") as? Bool == true)

        let (fresh, _) = try await PageDriver.computerFrame(in: view)
        _ = try await view.evaluateJavaScript("document.querySelector('#date').style.background='red'")
        await #expect(throws: PageComputerFailure.stale) {
            try await PageDriver.validateComputerAction(action, frame: fresh, in: view)
        }
    }

    @Test func coordinateClickRejectsTargetChangedDuringPointerPreview() async throws {
        let (view, window) = await page("""
            <button id='target' style='position:absolute;left:20px;top:20px;width:120px;height:40px'
              onclick='window.clicked=true'>Choose</button>
            """)
        defer { window.close() }
        let (frame, _) = try await PageDriver.computerFrame(in: view)
        let action = point(60, 40, frame: frame)
        let click = Task { try await PageDriver.computerAction(action, frame: frame, in: view) }
        #expect(await waitUntil(timeout: .seconds(2)) {
            view.subviews.contains { $0.identifier?.rawValue == "assistant-pointer" }
        })
        _ = try await view.evaluateJavaScript("document.querySelector('#target').textContent='Changed'")
        await #expect(throws: PageComputerFailure.stale) { try await click.value }
        #expect(try await view.evaluateJavaScript("window.clicked === true") as? Bool == false)
    }

    @Test(arguments: ["", "L", "Lviv"])
    func namedClickSendsMouseDownToPopupOption(value: String) async throws {
        let (view, window) = await page("""
            <input id='city' aria-label='City' value='\(value)'>
            <div id='choice' role='option' style='position:absolute;left:20px;top:60px;width:140px;height:44px'>Lviv</div>
            <script>document.querySelector('#choice').addEventListener('mousedown', event => {
              if (event.isTrusted) { document.querySelector('#city').value='Lviv'; window.selected = true; event.currentTarget.remove(); }
            }); document.querySelector('#city').focus();</script>
            """)
        defer { window.close() }
        _ = await PageDriver.snapshot(view)
        let result = await PageDriver.click(ref: 0, label: "Lviv", in: view)
        #expect(result.hasPrefix("Clicked"))
        #expect(try await view.evaluateJavaScript("window.selected === true") as? Bool == true)
        #expect(try await view.evaluateJavaScript("document.querySelector('#city').value") as? String == "Lviv")
    }

    @Test(arguments: ["", "Lviv"])
    func namedClickDoesNotConfirmOptionThatStaysOpen(value: String) async throws {
        let (view, window) = await page("""
            <input id='city' aria-label='City' value='\(value)'>
            <div role='option' style='position:absolute;left:20px;top:60px;width:140px;height:44px'>Lviv</div>
            <script>document.querySelector('#city').focus();</script>
            """)
        defer { window.close() }
        _ = await PageDriver.snapshot(view)
        let result = await PageDriver.click(ref: 0, label: "Lviv", in: view)
        #expect(result.contains("not confirmed"))
    }

    @Test func selectedOptionCanRemainVisibleWithoutAFocusedInput() async throws {
        let (view, window) = await page("""
            <div id='choice' role='option' aria-selected='false' style='width:140px;height:44px'>Lviv</div>
            <script>document.querySelector('#choice').addEventListener('mousedown', event => {
              if (event.isTrusted) event.currentTarget.setAttribute('aria-selected', 'true');
            });</script>
            """)
        defer { window.close() }
        _ = await PageDriver.snapshot(view)
        let result = await PageDriver.click(ref: 0, label: "Lviv", in: view)
        #expect(result.hasPrefix("Clicked"))
        #expect(try await view.evaluateJavaScript("document.querySelector('#choice').getAttribute('aria-selected')") as? String == "true")
    }

    @Test func printableKeysHavePhysicalCodesAndShiftedCharacters() async throws {
        let (view, window) = await page("""
            <input aria-label='Query'><script>window.keys=[];
            for (const type of ['keydown','keyup']) document.addEventListener(type,e=>{
              e.preventDefault(); keys.push({type:e.type,key:e.key,code:e.code,shift:e.shiftKey,
                alt:e.altKey,ctrl:e.ctrlKey,meta:e.metaKey,trusted:e.isTrusted});
            }); document.querySelector('input').focus();</script>
            """)
        defer { window.close() }
        let (frame, _) = try await PageDriver.computerFrame(in: view)
        for letter in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" {
            let key = String(letter)
            try await expectKey([key], key: key.lowercased(), code: "Key\(key)", frame: frame, in: view)
            try await expectKey(["SHIFT", key], key: key, code: "Key\(key)", shift: true, frame: frame, in: view)
        }
        let symbols = [
            ("0", ")", "Digit0"), ("1", "!", "Digit1"), ("2", "@", "Digit2"), ("3", "#", "Digit3"), ("4", "$", "Digit4"),
            ("5", "%", "Digit5"), ("6", "^", "Digit6"), ("7", "&", "Digit7"), ("8", "*", "Digit8"), ("9", "(", "Digit9"),
            ("-", "_", "Minus"), ("=", "+", "Equal"), ("[", "{", "BracketLeft"), ("]", "}", "BracketRight"),
            ("\\", "|", "Backslash"), (";", ":", "Semicolon"), ("'", "\"", "Quote"),
            (",", "<", "Comma"), (".", ">", "Period"), ("/", "?", "Slash"), ("`", "~", "Backquote"),
        ]
        for (plain, shifted, code) in symbols {
            try await expectKey([plain], key: plain, code: code, frame: frame, in: view)
            try await expectKey(["SHIFT", plain], key: shifted, code: code, shift: true, frame: frame, in: view)
            try await expectKey([shifted], key: shifted, code: code, shift: true, frame: frame, in: view)
        }
        try await expectKey([" "], key: " ", code: "Space", frame: frame, in: view)
        try await expectKey(["ALT", "B"], key: "b", code: "KeyB", alt: true, frame: frame, in: view)
        try await expectKey(["SHIFT", "LEFT"], key: "ArrowLeft", code: "ArrowLeft", shift: true, frame: frame, in: view)
        try await expectKey(["OPTION", "RIGHT"], key: "ArrowRight", code: "ArrowRight", alt: true, frame: frame, in: view)
    }

    private func expectKey(_ keys: [String], key: String, code: String, shift: Bool = false, alt: Bool = false,
                           frame: PageComputerFrame, in view: WKWebView) async throws {
        _ = try await view.evaluateJavaScript("window.keys=[]")
        try await PageDriver.computerAction(["type": "keypress", "keys": .array(keys.map(OpenAIJSON.string))], frame: frame, in: view)
        let events = try #require(try await view.evaluateJavaScript("window.keys") as? [[String: Any]])
        #expect(events.compactMap { $0["type"] as? String } == ["keydown", "keyup"])
        for event in events {
            #expect(event["key"] as? String == key, "Keys: \(keys), event: \(event)")
            #expect(event["code"] as? String == code, "Keys: \(keys), event: \(event)")
            #expect(event["shift"] as? Bool == shift)
            #expect(event["alt"] as? Bool == alt)
            #expect(event["ctrl"] as? Bool == false)
            #expect(event["meta"] as? Bool == false)
            #expect(event["trusted"] as? Bool == true)
        }
    }

    @Test func keypressInsertsTextAndSelectAllReplacesOnlyPageText() async throws {
        let (view, window) = await page("<input aria-label='Query'><script>document.querySelector('input').focus();</script>")
        defer { window.close() }
        let (frame, _) = try await PageDriver.computerFrame(in: view)
        for keys: [OpenAIJSON] in [["B"], ["SHIFT", "Z"], ["SHIFT", "1"], ["?"], ["SPACE"]] {
            try await PageDriver.computerAction(["type": "keypress", "keys": .array(keys)], frame: frame, in: view)
        }
        #expect(try await view.evaluateJavaScript("document.querySelector('input').value") as? String == "bZ!? ")
        for modifier: OpenAIJSON in ["CMD", "CTRL"] {
            try await PageDriver.computerAction(["type": "keypress", "keys": [modifier, "A"]], frame: frame, in: view)
            #expect(try await view.evaluateJavaScript("(()=>{const e=document.querySelector('input');return e.selectionStart===0&&e.selectionEnd===e.value.length;})()") as? Bool == true)
            try await PageDriver.computerAction(["type": "type", "text": "Replacement"], frame: frame, in: view)
            #expect(try await view.evaluateJavaScript("document.querySelector('input').value") as? String == "Replacement")
        }
        try await PageDriver.computerAction(["type": "keypress", "keys": ["BACKSPACE"]], frame: frame, in: view)
        #expect(try await view.evaluateJavaScript("document.querySelector('input').value") as? String == "Replacemen")
    }

    @Test func unsupportedKeysAndSystemChordsEmitNoKeyboardEvents() async throws {
        let (view, window) = await page("""
            <input aria-label='Query' value='Untouched'><script>window.keys=0;
            for(const type of ['keydown','keyup']) document.addEventListener(type,()=>window.keys++);
            document.querySelector('input').focus();</script>
            """)
        defer { window.close() }
        let (frame, _) = try await PageDriver.computerFrame(in: view)
        let unsupported: [[OpenAIJSON]] = [
            ["é"], ["ſ"], ["🙂"], ["F99"], ["SHIFT"], ["A", "B"],
            ["CMD", "V"], ["CTRL", "L"], ["CTRL", "SHIFT", "A"], ["META", "ALT", "A"],
        ]
        for keys in unsupported {
            await #expect(throws: PageComputerFailure.self) {
                try await PageDriver.computerAction(["type": "keypress", "keys": .array(keys)], frame: frame, in: view)
            }
        }
        #expect(try await view.evaluateJavaScript("window.keys") as? Int == 0)
        #expect(try await view.evaluateJavaScript("document.querySelector('input').value") as? String == "Untouched")
        try await PageDriver.computerAction(["type": "type", "text": "é🙂"], frame: frame, in: view)
        #expect(try await view.evaluateJavaScript("document.querySelector('input').value.includes('é🙂')") as? Bool == true)
    }

    @Test func pageCanHandleSelectAllWithoutAnExtraKeypress() async throws {
        let (view, window) = await page("""
            <input aria-label='Query' value='Original'><script>window.keys=[];
            for(const type of ['keydown','keyup']) document.addEventListener(type,e=>{
              keys.push([e.type,e.key,e.code,e.metaKey,e.ctrlKey,e.isTrusted]);
            }); const input=document.querySelector('input'); input.focus(); input.setSelectionRange(2,2);
            input.addEventListener('keydown',e=>e.preventDefault());</script>
            """)
        defer { window.close() }
        let (frame, _) = try await PageDriver.computerFrame(in: view)
        for modifier: OpenAIJSON in ["CMD", "CTRL"] {
            _ = try await view.evaluateJavaScript("window.keys=[]")
            try await PageDriver.computerAction(["type": "keypress", "keys": [modifier, "A"]], frame: frame, in: view)
            #expect(try await view.evaluateJavaScript("JSON.stringify(window.keys)") as? String
                    == "[[\"keydown\",\"a\",\"KeyA\",true,false,true],[\"keyup\",\"a\",\"KeyA\",true,false,true]]")
            #expect(try await view.evaluateJavaScript("input.selectionStart===2&&input.selectionEnd===2&&input.value==='Original'") as? Bool == true)
        }
    }

    @Test func selectAllStopsIfAKeyHandlerFocusesASensitiveField() async throws {
        let (view, window) = await page("""
            <input aria-label='Query'><input type='password'><script>
            document.querySelector('input').focus(); document.addEventListener('keydown',e=>{
              if(e.metaKey) document.querySelector('[type=password]').focus();
            });</script>
            """)
        defer { window.close() }
        let (frame, _) = try await PageDriver.computerFrame(in: view)
        await #expect(throws: PageComputerFailure.sensitive) {
            try await PageDriver.computerAction(["type": "keypress", "keys": ["CMD", "A"]], frame: frame, in: view)
        }
    }

    @Test(arguments: [false, true])
    func nativePointerActionsAndModifiersReachPageHandlers(reorderWindow: Bool) async throws {
        let (view, window) = await page("""
            <div id='target' style='position:absolute;left:20px;top:20px;width:250px;height:150px'>Pointer target</div>
            <script>window.stats={}; for(const type of ['click','dblclick','contextmenu','mousemove','mousedown','mouseup'])
              document.querySelector('#target').addEventListener(type,e=>{stats[type]=(stats[type]||0)+1;stats.shift=e.shiftKey;stats.trusted=e.isTrusted;});</script>
            """)
        defer { window.close() }
        let (frame, _) = try await PageDriver.computerFrame(in: view)
        func perform(_ action: OpenAIJSON) async throws {
            do {
                try await PageDriver.computerAction(action, frame: frame, in: view)
            } catch {
                let stats = try? await view.evaluateJavaScript("JSON.stringify(window.stats)")
                Issue.record("Pointer action \(action["type"].string ?? "unknown") failed; fixture events: \(stats as? String ?? "unavailable")")
                throw error
            }
        }
        var double = point(60, 60, frame: frame, type: "double_click")
        double["keys"] = ["SHIFT"]
        try await perform(double)
        #expect(try await view.evaluateJavaScript("stats.dblclick === 1 && stats.shift && stats.trusted") as? Bool == true)
        var right = point(60, 60, frame: frame)
        right["button"] = "right"
        try await perform(right)
        #expect(try await view.evaluateJavaScript("stats.contextmenu === 1") as? Bool == true)
        if reorderWindow {
            window.orderOut(nil)
            window.orderBack(nil)
        }
        let path = [point(70, 70, frame: frame), point(90, 80, frame: frame), point(110, 90, frame: frame)]
        for _ in 0..<3 {
            let downs = try #require(try await view.evaluateJavaScript("stats.mousedown") as? Int)
            let ups = try #require(try await view.evaluateJavaScript("stats.mouseup") as? Int)
            try await perform(["type": "drag", "path": .array(path)])
            #expect(try await view.evaluateJavaScript("stats.mousedown === \(downs + 1) && stats.mouseup === \(ups + 1) && stats.trusted") as? Bool == true)
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["LINEN_COMPUTER_FOREGROUND_TEST"] == "1"))
    func nativeHoverReachesPageHandlersAndCSS() async throws {
        let (view, window) = await page("""
            <style>#target:hover { background-color:rgb(255, 0, 0); }</style>
            <div id='target' style='position:absolute;left:20px;top:20px;width:250px;height:150px'>Hover target</div>
            <script>target.addEventListener('mousemove', e=>{window.moved=e.isTrusted;});</script>
            """)
        defer { window.close() }
        let (frame, _) = try await PageDriver.computerFrame(in: view)
        do {
            try await PageDriver.computerAction(point(60, 60, frame: frame, type: "move"), frame: frame, in: view)
        } catch {
            Issue.record("Hover input failed: active=\(NSApp.isActive), key=\(window.isKeyWindow)")
            throw error
        }
        #expect(try await view.evaluateJavaScript("window.moved === true") as? Bool == true)
        #expect(try await view.evaluateJavaScript("getComputedStyle(target).backgroundColor") as? String == "rgb(255, 0, 0)")
        #expect(await waitUntil(timeout: .seconds(30)) { !window.isVisible })
    }

    @Test func backgroundHoverDoesNotClaimSuccess() async throws {
        let (view, window) = await page("<div style='height:300px' onmousemove='window.moved=true'>Target</div>")
        defer { window.close() }
        let (frame, _) = try await PageDriver.computerFrame(in: view)
        #expect(!window.isKeyWindow)
        await #expect(throws: PageComputerFailure.self) {
            try await PageDriver.computerAction(point(60, 60, frame: frame, type: "move"), frame: frame, in: view)
        }
        #expect(try await view.evaluateJavaScript("window.moved === undefined") as? Bool == true)
    }

    @Test func editingADraftDoesNotAskToPublishButEnterDoes() async throws {
        let (view, window) = await page("""
            <form onsubmit='event.preventDefault();window.sent=true'>
              <input aria-label='Message'><button>Send message</button>
            </form>
            """)
        defer { window.close() }
        _ = try await view.evaluateJavaScript("document.querySelector('input').focus()")
        let (frame, _) = try await PageDriver.computerFrame(in: view)
        var confirmations = 0
        try await AgentActionConsent.$decisionForTesting.withValue(.init { _, _, _ in
            confirmations += 1
            return .decline
        }) {
            try await PageDriver.computerAction(["type": "type", "text": "Draft"], frame: frame, in: view)
            try await PageDriver.computerAction(["type": "keypress", "keys": ["LEFT"]], frame: frame, in: view)
            #expect(confirmations == 0)
            await #expect(throws: PageComputerFailure.self) {
                try await PageDriver.computerAction(["type": "keypress", "keys": ["ENTER"]], frame: frame, in: view)
            }
        }
        #expect(confirmations == 1)
        #expect(try await view.evaluateJavaScript("document.querySelector('input').value") as? String == "Draft")
        #expect(try await view.evaluateJavaScript("window.sent === undefined") as? Bool == true)
    }

    @Test func zoomedCoordinatesProtectTheActualTarget() async throws {
        let (view, window) = await page("""
            <input type='password' style='position:absolute;left:20px;top:20px;width:100px;height:40px'>
            <button style='position:absolute;left:180px;top:20px;width:60px;height:40px' onclick='window.chosen=true'>Choose</button>
            """)
        defer { window.close() }
        view.pageZoom = 2
        let (frame, _) = try await PageDriver.computerFrame(in: view)
        await #expect(throws: PageComputerFailure.self) {
            try await PageDriver.computerAction(point(200, 60, frame: frame), frame: frame, in: view)
        }
        try await PageDriver.computerAction(point(400, 60, frame: frame), frame: frame, in: view)
        #expect(try await view.evaluateJavaScript("window.chosen === true") as? Bool == true)
        view.pageZoom = 1.5
        await #expect(throws: PageComputerFailure.self) {
            try await PageDriver.validateComputerFrame(frame, in: view, checkRevision: false)
        }
    }

    @Test func anAppOverlayCannotReceiveComputerInput() async throws {
        let (view, window) = await page("<button style='position:absolute;left:20px;top:20px;width:120px;height:40px' onclick='window.chosen=true'>Choose</button>")
        defer { window.close() }
        let root = NSView(frame: view.frame)
        window.contentView = root
        root.addSubview(view)
        let overlay = ComputerInputOverlay(frame: NSRect(x: 20, y: 340, width: 120, height: 40))
        root.addSubview(overlay)
        #expect(view.window === window)
        #expect(root.hitTest(NSPoint(x: 60, y: 360)) === overlay)
        let (frame, _) = try await PageDriver.computerFrame(in: view)
        await #expect(throws: PageComputerFailure.self) {
            try await PageDriver.computerAction(point(60, 40, frame: frame), frame: frame, in: view)
        }
        #expect(overlay.clicks == 0)
        #expect(try await view.evaluateJavaScript("window.chosen === undefined") as? Bool == true)
    }

    @Test func sensitiveTargetsFilledFieldsAndRevokedScopeAreDenied() async throws {
        let (view, window) = await page("<input type='password' style='position:absolute;left:20px;top:20px;width:100px;height:40px'>")
        defer { window.close() }
        let (frame, _) = try await PageDriver.computerFrame(in: view)
        await #expect(throws: PageComputerFailure.self) {
            try await PageDriver.computerAction(point(40, 40, frame: frame), frame: frame, in: view)
        }
        _ = try await view.evaluateJavaScript("document.querySelector('input').value='secret'")
        await #expect(throws: PageComputerFailure.self) { _ = try await PageDriver.computerFrame(in: view) }
        let guardScope = PageAutomationGuard(documentURL: "about:blank", snapshot: nil, validate: { false })
        await PageAutomationGuard.$current.withValue(guardScope) {
            await #expect(throws: PageComputerFailure.self) { try await PageDriver.computerAction(["type": "wait"], frame: frame, in: view) }
        }
    }

    @Test func consequentialClickAndSystemClipboardShortcutDoNotExecute() async throws {
        let (view, window) = await page("<button style='position:absolute;left:20px;top:20px;width:120px;height:40px' onclick='window.sent=true'>Send message</button><input>")
        defer { window.close() }
        let (frame, _) = try await PageDriver.computerFrame(in: view)
        await AgentActionConsent.$decisionForTesting.withValue(.init { _, _, _ in .decline }) {
            await #expect(throws: PageComputerFailure.self) {
                try await PageDriver.computerAction(point(60, 40, frame: frame), frame: frame, in: view)
            }
        }
        #expect(try await view.evaluateJavaScript("window.sent === undefined") as? Bool == true)
        _ = try await view.evaluateJavaScript("document.querySelector('input').focus()")
        await #expect(throws: PageComputerFailure.self) {
            try await PageDriver.computerAction(["type": "keypress", "keys": ["CMD", "V"]], frame: frame, in: view)
        }
    }
}

@MainActor
private final class ComputerInputOverlay: NSView {
    var clicks = 0
    override func mouseDown(with event: NSEvent) {
        clicks += 1
    }
}
