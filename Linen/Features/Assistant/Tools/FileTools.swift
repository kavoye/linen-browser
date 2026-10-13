// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation
import WebKit

nonisolated struct ChooseFilesOnPageTool: Tool {
    let name = "chooseFilesOnPage"
    let description = """
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

nonisolated struct InspectDownloadsTool: Tool {
    let name = "inspectDownloads"
    let description = """
        List download IDs, filenames, status, and received bytes for this task's selected page and current site. Supply downloadID to inspect one. \
        With outcomeID, verify an outcome only if that download finished and its file exists. Does not read file contents or expose local paths.
        """
    let toolkit: AgentToolkit
    @Generable struct Arguments {
        var page: String?
        var downloadID: String?
        var outcomeID: String?
    }
    func call(arguments: Arguments) async throws -> String {
        await toolkit.inspectDownloads(page: arguments.page, downloadID: arguments.downloadID, outcomeID: arguments.outcomeID)
    }
}

extension AgentToolkit {
    func inspectDownloads(page: String?, downloadID: String?, outcomeID: String?) async -> String {
        let index = outcomeID.flatMap { id in taskLedger.outcomes.firstIndex { $0.id == id } }
        if let index {
            taskLedger.outcomes[index].evidence = nil
        }
        let output = await withPageContext(page: page, observationID: nil) {
            await pageOperation(name: "inspectDownloads", readOnly: true) { view in
                let items = taskDownloads(in: view).filter { downloadID == nil || $0.id.uuidString == downloadID }
                if outcomeID != nil {
                    guard let index, let downloadID, let item = items.first, item.id.uuidString == downloadID,
                          item.state == .finished, let file = item.destination,
                          let values = try? FileManager.default.attributesOfItem(atPath: file.path),
                          values[.type] as? FileAttributeType == .typeRegular,
                          let bytes = values[.size] as? NSNumber else {
                        return "Verification failed: choose a recorded outcome and a finished download whose file still exists."
                    }
                    taskLedger.outcomes[index].evidence = .init(url: item.sourceOrigin ?? "", observationID: item.id.uuidString,
                        matchedText: "Finished download: \(item.filename), \(bytes.int64Value) bytes", actionRevision: taskLedger.actionRevision)
                    taskLedger.outcomes[index].blocker = nil
                    if taskLedger.completion == .verified {
                        taskLedger.pendingAction = nil
                    }
                }
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
        if lastToolFailed, let index {
            taskLedger.outcomes[index].evidence = nil
        }
        return output
    }
}
