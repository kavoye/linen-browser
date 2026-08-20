// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct GeneralSettings: View {
    let coordinator: AppCoordinator

    @Bindable var settings: BrowserSettings

    @State private var isDefault = false
    @State private var askedToBeDefault = false
    @State private var handedOver = false

    private var defaultBrowserCaption: LocalizedStringResource {
        isDefault ? "Linen is your default browser." : "Linen isn’t your default browser."
    }

    private var defaultBrowserButton: LocalizedStringResource {
        isDefault ? "Default" : "Set as Default…"
    }

    var body: some View {
        SettingsPageHeader(title: "General")

        SettingsSection(title: "When Linen opens", symbol: "power") {
            OptionList(
                options: StartupBehavior.allCases.map {
                    .init(value: $0, label: $0.label, caption: $0.caption)
                },
                selection: settings.startup,
                onSelect: { settings.startup = $0 }
            )
        }
        .settingsAnchor("general.startup")

        SettingsSection(title: "New tabs", symbol: "rectangle.badge.plus") {
            OptionList(
                options: NewTabBehavior.allCases.map {
                    .init(value: $0, label: $0.label, caption: $0.caption)
                },
                selection: settings.newTab,
                onSelect: { settings.newTab = $0 }
            )

            if settings.newTab == .homepage {
                RowSeparator()

                HomepageRow(coordinator: coordinator, settings: settings)
                    .settingsAnchor("general.homepage")
            }
        }
        .settingsAnchor("general.newTab")

        SettingsSection(title: "Default browser", symbol: "arrow.up.forward.app") {
            DetailRow(
                title: "Open links from other apps",
                caption: defaultBrowserCaption
            ) {
                SettingsButton(
                    title: defaultBrowserButton,
                    isProminent: !isDefault
                ) {
                    becomeDefault()
                }
                .disabled(isDefault)
            }
            .settingsAnchor("general.defaultBrowser")
        }
        .task { isDefault = DefaultBrowser.isCurrent }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isDefault = DefaultBrowser.isCurrent
        }

        if handedOver {
            Footnote("System Settings is open. Choose Linen under “Default web browser.”")
        } else if askedToBeDefault, !isDefault {
            Footnote("If no panel appeared, set it in System Settings under Desktop & Dock.")
        }

        ImportSection(coordinator: coordinator)
    }

    private func becomeDefault() {
        askedToBeDefault = true
        Task {
            handedOver = await DefaultBrowser.request() == .handedOverToSystemSettings
            isDefault = DefaultBrowser.isCurrent
        }
    }
}

private struct HomepageRow: View {
    let coordinator: AppCoordinator

    @Bindable var settings: BrowserSettings

    @FocusState private var focused: Bool

    private var currentPage: String? {
        let url = coordinator.browser.activeTab?.urlString ?? ""
        return url.isEmpty || url.hasPrefix("about:") ? nil : url
    }

    var body: some View {
        DetailRow(
            title: "Homepage",
            caption: "New tabs open with this page.",
            layout: .stacked
        ) {
            HStack(spacing: 8) {
                FieldChrome(isFocused: focused) {
                    TextField(text: $settings.homepage) {
                        Text(verbatim: "example.com")
                    }
                        .textFieldStyle(.plain)
                        .font(Theme.Font.body)
                        .focused($focused)
                }

                if let currentPage {
                    SettingsButton(title: "Use This Page") {
                        settings.homepage = currentPage
                    }
                }

                if !settings.homepage.isEmpty {
                    IconButton(symbol: "xmark", help: "Clear") {
                        settings.homepage = ""
                        if settings.newTab == .homepage {
                            settings.newTab = .startPage
                        }
                    }
                }
            }
        }
    }
}

private struct ImportSection: View {
    let coordinator: AppCoordinator

    private typealias Source = BrowserImport.Source

    @State private var status: [Source: String] = [:]
    @State private var scanning: Source?
    @State private var safariNeedsAccess = false
    @State private var pending: (source: Source, payload: BrowserImport.Payload)?

    var body: some View {
        SettingsSection(title: "Import", symbol: "square.and.arrow.down") {
            row(.safari) {
                if safariNeedsAccess {
                    SettingsButton(title: "Open System Settings", isProminent: true) {
                        let pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
                        if let url = URL(string: pane) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
            .settingsAnchor("general.importSafari")

            RowSeparator()

            row(.chrome)
                .settingsAnchor("general.importChrome")
        }
        .confirmationDialog(
            pending.map { "Import Items from \($0.source.name)" } ?? "",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })
        ) {
            Button("Import") {
                guard let pending else { return }
                BrowserImport.apply(pending.payload, into: coordinator.browser)
                status[pending.source] = "Imported \(pending.payload.summary.phrase)."
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(importMessage)
        }
    }

    private var importMessage: String {
        guard let payload = pending?.payload else { return "" }
        var lines = ["\(payload.summary.phrase) will be imported."]
        if !payload.bookmarks.isEmpty {
            lines.append("The bookmarks go into a new folder in the sidebar.")
        }
        return lines.joined(separator: " ")
    }

    @ViewBuilder
    private func row(
        _ source: Source,
        @ViewBuilder leading: () -> some View = { EmptyView() }
    ) -> some View {
        DetailRow(
            verbatimTitle: source.name,
            verbatimCaption: status[source] ?? String(localized: source.caption)
        ) {
            HStack(spacing: 8) {
                leading()
                if scanning == source {
                    Spinner(size: 12)
                        .foregroundStyle(.secondary)
                }
                SettingsButton(title: "Import…") { beginImport(source) }
                    .disabled(!source.isPresent || scanning != nil)
            }
        }
    }

    private func beginImport(_ source: Source) {
        scanning = source
        Task {
            let result = await Task.detached { Result { try source.scan() } }.value
            scanning = nil
            switch result {
            case .success(let payload) where payload.summary.isEmpty:
                status[source] = "No items to import from \(source.name)."
            case .success(let payload):
                if source == .safari {
                    safariNeedsAccess = false
                }
                pending = (source, payload)
            case .failure(BrowserImport.Failure.needsFullDiskAccess):
                safariNeedsAccess = true
                status[source] = "macOS protects Safari’s files. Allow Linen under "
                    + "Privacy & Security → Full Disk Access, then try again."
            case .failure:
                status[source] = "\(source.name)’s files couldn’t be read."
            }
        }
    }
}
