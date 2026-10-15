// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct SpacePeerList: View {
    let browser: BrowserModel
    let coordinator: AppCoordinator
    let slide: SpaceSlide
    let contentInsets: EdgeInsets

    private var ids: [UUID] {
        guard let peer = slide.peer, !slide.mounted.contains(peer.id) else { return slide.mounted }
        return slide.mounted + [peer.id]
    }

    var body: some View {
        ZStack(alignment: .top) {
            ForEach(ids, id: \.self) { id in
                SpacePeerPage(coordinator: coordinator, slide: slide, spaceID: id, contentInsets: contentInsets)
            }
        }
    }
}

private struct SpacePeerPage: View {
    let coordinator: AppCoordinator
    let slide: SpaceSlide
    let spaceID: UUID
    let contentInsets: EdgeInsets

    var body: some View {
        SpacePage(coordinator: coordinator, spaceID: spaceID, contentInsets: contentInsets)
            .modifier(SpacePeerOffset(slide: slide, spaceID: spaceID))
            .transition(.identity)
    }
}

struct SpacePage: View {
    let coordinator: AppCoordinator
    let spaceID: UUID
    let contentInsets: EdgeInsets

    @Environment(\.windowColorScheme) private var scheme

    private var wash: ChromeWash {
        let color = LoomChrome.sampledColor(coordinator.loomColor(forSpace: spaceID), scheme: scheme)
        return .of(color, isLight: PageInk.isLight(color, scheme: scheme))
    }

    var body: some View {
        Group {
            if let source = coordinator.peerModel(for: spaceID) {
                SpacePeerRows(
                    browser: source,
                    coordinator: coordinator,
                    spaceID: spaceID,
                    contentInsets: contentInsets
                )
            }
        }
        .allowsHitTesting(false)
        .environment(\.chromeWash, wash)
        .environment(\.chromeIsLight, wash.isLight)
        .environment(\.colorScheme, wash.isLight ? .light : .dark)
    }
}

private struct SpacePeerOffset: ViewModifier {
    let slide: SpaceSlide
    let spaceID: UUID

    func body(content: Content) -> some View {
        let shown = slide.peer?.id == spaceID ? slide.peer : nil
        let offset = shown.map { slide.offset + ($0.forward ? slide.width : -slide.width) } ?? 4 * slide.width
        return content.visualEffect { effect, _ in effect.offset(x: offset) }
    }
}

private struct SpacePeerRows: View {
    let browser: BrowserModel
    let coordinator: AppCoordinator
    let spaceID: UUID
    let contentInsets: EdgeInsets

    @State private var selection = SidebarSelection()
    @State private var frames = SidebarFrames()

    private var items: [SidebarItem] {
        browser.rootItems(inSpace: spaceID)
    }

    private var litTab: UUID? {
        browser.lastActiveTab(inSpace: spaceID)?.id
    }

    private var context: SidebarRowContext {
        SidebarRowContext(
            browser: browser,
            coordinator: coordinator,
            selection: selection,
            drag: nil,
            isLeaving: false,
            incoming: nil,
            arriving: [],
            pinsCarried: false,
            space: "sidebar-space-peer",
            frames: frames,
            litTab: litTab,
            isInteractive: false
        )
    }

    var body: some View {
        let items = items
        let kept = Array(items.prefix { browser.isKept($0) })
        let loose = Array(items.dropFirst(kept.count))
        VStack(spacing: 2) {
            if !kept.isEmpty {
                SidebarRows(items: kept, depth: 0, context: context, ownsEnd: false)
                SidebarSectionSeam()
            }
            SidebarRows(items: loose, depth: 0, context: context)
        }
        .padding(.leading, contentInsets.leading)
        .padding(.trailing, contentInsets.trailing)
        .coordinateSpace(.named("sidebar-space-peer"))
    }
}
