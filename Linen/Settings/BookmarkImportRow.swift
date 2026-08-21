// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct BookmarkImportRow: View {
    let browser: BrowserModel
    let caption: LocalizedStringResource
    var actionWidth: CGFloat?

    @State private var pending: BrowserImport.Payload?
    @State private var status: String?
    @State private var isReading = false

    var body: some View {
        DetailRow(
            verbatimTitle: String(localized: "Bookmarks"),
            verbatimCaption: status ?? String(localized: caption)
        ) {
            control
        }
        .confirmationDialog(
            "Import Bookmarks",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })
        ) {
            Button("Import") {
                guard let pending else { return }
                BrowserImport.apply(pending, into: browser)
                status = String(localized: "Imported \(pending.phrase).")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(verbatim: message)
        }
    }

    @ViewBuilder
    private var control: some View {
        Group {
            if isReading {
                Spinner(size: 12)
                    .foregroundStyle(.secondary)
            } else {
                SettingsButton(title: "Choose File…", minWidth: actionWidth) { choose() }
            }
        }
        .frame(width: actionWidth, alignment: .trailing)
    }

    private var message: String {
        guard let pending else { return "" }
        return String(localized: "\(pending.phrase) will be imported.")
            + " " + String(localized: "The bookmarks go into a new folder in the sidebar.")
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.html]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "Choose the bookmarks file you exported from another browser.")
        panel.prompt = String(localized: "Import")
        guard panel.runModal() == .OK, let file = panel.url else { return }
        read(file)
    }

    private func read(_ file: URL) {
        isReading = true
        status = nil
        Task {
            let result = await Task.detached { Result { try BrowserImport.read(file) } }.value
            isReading = false
            switch result {
            case .success(let payload) where payload.isEmpty:
                status = String(localized: "No bookmarks in this file.")
            case .success(let payload):
                pending = payload
            case .failure:
                status = String(localized: "This file couldn’t be read.")
            }
        }
    }
}
