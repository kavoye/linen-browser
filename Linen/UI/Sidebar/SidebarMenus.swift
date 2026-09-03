// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct SidebarLinkMenuItems: View {
    let tabs: [BrowserTab]
    let coordinator: AppCoordinator

    private var linkable: [BrowserTab] {
        tabs.filter { coordinator.linkURL(for: $0) != nil }
    }

    var body: some View {
        if !linkable.isEmpty {
            Button {
                coordinator.copyLinks(for: linkable)
            } label: {
                if linkable.count == 1 {
                    Label("Copy Link", systemImage: "doc.on.doc")
                } else {
                    Label("Copy Links", systemImage: "doc.on.doc")
                }
            }
            Divider()
        }
    }
}

struct SidebarPinMenuItems: View {
    let tab: BrowserTab
    let browser: BrowserModel

    var body: some View {
        if tab.pinnedURL == nil {
            Button {
                browser.pin(tab)
            } label: {
                Label("Pin This Page", systemImage: "pin")
            }
            .disabled(tab.urlString.isEmpty)
        } else {
            if tab.isAwayFromPin {
                Button {
                    browser.returnToPin(tab)
                } label: {
                    Label("Back to Pinned Page", systemImage: "arrow.uturn.backward")
                }
            }
            Menu {
                Button {
                    browser.pin(tab)
                } label: {
                    Label("Move Pin to This Page", systemImage: "pin")
                }
                .disabled(!tab.isAwayFromPin)

                Button {
                    PinEditor.edit(tab, in: browser)
                } label: {
                    Label("Edit…", systemImage: "pencil")
                }
            } label: {
                Label("Edit Pinned Page", systemImage: "pin.circle")
            }
        }
        Divider()
    }
}

struct SidebarUnpinButton: View {
    let tab: BrowserTab
    let browser: BrowserModel

    var body: some View {
        Button {
            browser.unpin(tab)
        } label: {
            Label("Unpin Tab", systemImage: "pin.slash")
        }
    }
}

struct SidebarAudioMenuItems: View {
    let tab: BrowserTab
    let coordinator: AppCoordinator

    var body: some View {
        Button {
            coordinator.toggleMute(tab: tab)
        } label: {
            if tab.isMuted {
                Label("Unmute Tab", systemImage: "speaker.wave.2")
            } else {
                Label("Mute Tab", systemImage: "speaker.slash")
            }
        }
        Divider()
    }
}

struct SidebarFolderMenuItems: View {
    let items: [SidebarItem]
    let browser: BrowserModel

    private var isFiled: Bool {
        items.contains { browser.sidebarTree.parent(of: $0) != nil }
    }

    private var targets: [TabFolder] {
        browser.folders.filter { browser.sidebarTree.canHold($0.id, items) }
    }

    var body: some View {
        Menu {
            ForEach(targets) { folder in
                Button {
                    browser.move(items, into: folder)
                } label: {
                    Text(verbatim: folder.name)
                }
            }
            if !targets.isEmpty {
                Divider()
            }
            Button {
                browser.createFolder(containing: items)
            } label: {
                Label("New Folder…", systemImage: "folder.badge.plus")
            }
        } label: {
            Label("Move to Folder", systemImage: "folder")
        }
        if isFiled {
            Button {
                browser.moveOut(items)
            } label: {
                Label("Remove from Folder", systemImage: "folder.badge.minus")
            }
        }
        Divider()
    }
}

struct SidebarSelectionMenuItems: View {
    let items: [SidebarItem]
    let browser: BrowserModel
    let coordinator: AppCoordinator

    private var tabs: [BrowserTab] {
        browser.tabs(under: items)
    }

    var body: some View {
        SidebarLinkMenuItems(tabs: tabs, coordinator: coordinator)
        SidebarFolderMenuItems(items: items, browser: browser)
        SidebarCloseTabsButton(items: items, browser: browser)
    }
}

struct SidebarCloseTabsButton: View {
    let items: [SidebarItem]
    let browser: BrowserModel

    var body: some View {
        let count = browser.tabCount(in: items)
        Button(role: .destructive) {
            Task {
                guard await ConfirmAlert.destructive(
                    "Close \(count) tabs?",
                    verb: "Close Tabs"
                ) else { return }
                browser.close(items)
            }
        } label: {
            Label("Close \(count) Tabs", systemImage: "xmark")
        }
        .disabled(count == 0)
    }
}
