// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation
import WebKit

nonisolated struct ChooseFilesOnPageTool: AgentTool {
    static let toolName = "chooseFilesOnPage"
    static let toolDescription = """
        Open the website's file picker for a visible main-frame file input. The user chooses the files; never supply local paths. Waits for \
        selection or cancellation. Selection alone does not verify upload completion.
        """
    let toolkit: AgentToolkit
    @Generable struct Arguments {
        var page: String?
        var observationID: String
        var ref: Int
    }
    func call(arguments: Arguments) async throws -> String {
        guard !arguments.observationID.isEmpty else { return await toolkit.rejectTool(name: name, reason: "Read the page first.") }
        return await toolkit.withPageContext(page: arguments.page, observationID: arguments.observationID) {
            await toolkit.pageOperation(name: name) { view in
                await PageDriver.chooseFiles(ref: arguments.ref, in: view, selectFiles: toolkit.fileSelection)
            }
        }
    }
}

nonisolated struct InspectDownloadsTool: AgentTool {
    static let toolName = "inspectDownloads"
    static let toolDescription = """
        List download IDs, filenames, status, and received bytes for this task's selected page and current site. Supply downloadID to inspect one. \
        Does not read file contents or expose local paths.
        """
    let toolkit: AgentToolkit
    @Generable struct Arguments {
        var page: String?
        var downloadID: String?
    }
    func call(arguments: Arguments) async throws -> String {
        await toolkit.inspectDownloads(page: arguments.page, downloadID: arguments.downloadID)
    }
}

extension AgentToolkit {
    func inspectDownloads(page: String?, downloadID: String?) async -> String {
        await withPageContext(page: page, observationID: nil) {
            await pageOperation(name: "inspectDownloads", readOnly: true) { view in
                let items = taskDownloads(in: view).filter { downloadID == nil || $0.id.uuidString == downloadID }
                let rows = items.prefix(30).map { item -> String in
                    let state: String
                    switch item.state {
                    case .running:
                        state = "running"
                    case .finished:
                        state = "finished"
                    case .interrupted:
                        state = "interrupted"
                    case .failed:
                        state = "failed"
                    case .cancelled:
                        state = "cancelled"
                    }
                    return "\(item.id.uuidString) \(String(item.filename.prefix(200))) status=\(state) receivedBytes=\(item.bytesReceived)"
                }
                return "CONTROL: Task downloads\n" + (rows.isEmpty ? "No matching downloads from this task and site." : rows.joined(separator: "\n"))
            }
        }
    }
}
