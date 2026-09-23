// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation
import WebKit

nonisolated struct ListFramesTool: Tool {
    let name = "listFrames"
    let description = "List embedded frame IDs and origins on a page. Use readFrame to request separate access to an embedded website. Frame IDs expire on navigation."
    let toolkit: AgentToolkit
    @Generable struct Arguments {
        var page: String?
    }
    func call(arguments: Arguments) async throws -> String {
        await toolkit.withPageContext(page: arguments.page, observationID: nil) {
            await toolkit.pageOperation(name: name, readOnly: true) { view in
                var rows: [String] = []
                for target in PageFrameRegistry.shared.targets(in: view) {
                    guard await PageFrameRegistry.shared.isLive(target, in: view) else { continue }
                    rows.append("frameID: \(target.id) origin: \(SitePermissions.origin(for: target.url))")
                }
                return "CONTROL: Embedded frames\n" + (rows.isEmpty ? "No accessible frame handles. Reload the page if it predates frame support." : rows.joined(separator: "\n"))
            }
        }
    }
}

nonisolated struct ReadFrameTool: Tool {
    let name = "readFrame"
    let description = "Read text and controls in an embedded frame with separate permission for its origin. Return fresh refs and observationID. Use actInFrame for those refs."
    let toolkit: AgentToolkit
    @Generable struct Arguments {
        var page: String?
        var frameID: String
        var lookingFor: String?
        var textOffset: Int?
        var controlOffset: Int?
    }
    func call(arguments: Arguments) async throws -> String {
        await toolkit.withPageContext(page: arguments.page, observationID: nil) {
            await toolkit.frameOperation(name: name, frameID: arguments.frameID, readOnly: true) { view in
                "CONTROL: Frame observation\n" + (await PageDriver.readRenderedPage(view, lookingFor: arguments.lookingFor ?? "",
                    textOffset: arguments.textOffset ?? 0, controlOffset: arguments.controlOffset ?? 0))
            }
        }
    }
}

nonisolated struct ActInFrameTool: Tool {
    let name = "actInFrame"
    let description = """
        Act on a freshly observed embedded frame. action is click, type, select, check, key, or scroll. Use text for typing, option labels, keys, or \
        scroll direction; checked for check. Typing never submits. Frame and top-level site permissions both apply.
        """
    let toolkit: AgentToolkit
    @Generable struct Arguments {
        var page: String?
        var frameID: String
        var observationID: String
        var ref: Int
        var action: String
        var text: String?
        var checked: Bool?
    }
    func call(arguments: Arguments) async throws -> String {
        guard !arguments.observationID.isEmpty, (arguments.text?.utf8.count ?? 0) <= 100_000 else {
            return await toolkit.rejectTool(name: name, reason: "Read the frame first and supply its observationID. Input is limited to 100,000 bytes.")
        }
        return await toolkit.withPageContext(page: arguments.page, observationID: arguments.observationID) {
            await toolkit.frameOperation(name: name, frameID: arguments.frameID, readOnly: false) { view in
                switch arguments.action {
                case "click":
                    await PageDriver.click(ref: arguments.ref, label: "", in: view, announced: true)
                case "type":
                    await PageDriver.type(text: arguments.text ?? "", intoField: "", ref: arguments.ref, submit: false, in: view, announced: true)
                case "select":
                    await PageDriver.selectOption(arguments.text ?? "", ref: arguments.ref, field: "", in: view, announced: true)
                case "check":
                    await PageDriver.setChecked(ref: arguments.ref, checked: arguments.checked ?? false, in: view, announced: true)
                case "key":
                    await PageDriver.pressKey(arguments.text ?? "", ref: arguments.ref, in: view)
                case "scroll":
                    await PageDriver.scroll(direction: arguments.text ?? "down", ref: arguments.ref, in: view)
                default:
                    "Unsupported frame action. Use click, type, select, check, key, or scroll."
                }
            }
        }
    }
}

extension AgentToolkit {
    func frameOperation(name: String, frameID: String, readOnly: Bool, operation: (WKWebView) async -> String) async -> String {
        await pageOperation(name: name, readOnly: readOnly) { view in
            guard let target = PageFrameRegistry.shared.target(frameID, in: view),
                  await PageFrameRegistry.shared.isLive(target, in: view),
                  let access = embeddedAccess(for: target.url, in: view) else { return "Frame unavailable. List frames again." }
            let capability: AssistantPageCapability = readOnly ? .read : .control
            guard await access.authorize(capability) else { return access.denialMessage(for: capability) }
            guard await PageFrameRegistry.shared.isLive(target, in: view), let parent = PageAutomationGuard.current,
                  parent.validate() else { return PageDriver.staleMessage }
            let guardScope = PageAutomationGuard(documentURL: target.url.absoluteString, snapshot: nil) {
                parent.validate() && access.effectivePolicy.allows(capability) && PageFrameRegistry.shared.isCurrent(target, in: view)
            }
            return await PageDriver.$selectedFrame.withValue(target) {
                await PageAutomationGuard.$current.withValue(guardScope) {
                    let output = await operation(view)
                    guard guardScope.validate(), await PageFrameRegistry.shared.isLive(target, in: view) else { return PageDriver.staleMessage }
                    return output + "\nframeID: \(frameID)"
                }
            }
        }
    }
}
