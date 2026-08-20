// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI
import Testing

@testable import Linen

/// The player now stows only in the icons-only sidebar, so its controls have
/// to fit a sidebar dragged all the way in. The widths are measured from the
/// real views, because every button in the transport is a fixed size and an
/// overrun would overlap rather than wrap.
@MainActor
struct MediaCardFitTests {
    private func transportWidth(isCompact: Bool) -> CGFloat {
        NSHostingView(rootView: MediaTransport(media: MediaCenter(), isCompact: isCompact)).fittingSize.width
    }

    @Test func theTransportFitsTheNarrowestSidebar() {
        let panel = MediaSidebarCard.panelWidth(sidebarWidth: SidebarMetrics.minWidth, isStowed: false)
        #expect(MediaSidebarCard.isCompact(panelWidth: panel))
        #expect(transportWidth(isCompact: true) <= MediaSidebarCard.controlsWidth(panelWidth: panel))
    }

    @Test func theRoomyTransportFitsWhereItIsUsed() {
        let panel = MediaSidebarCard.widthForRoomyControls
        #expect(!MediaSidebarCard.isCompact(panelWidth: panel))
        #expect(transportWidth(isCompact: false) <= MediaSidebarCard.controlsWidth(panelWidth: panel))
    }

    @Test func theFloatingPlayerIsRoomy() {
        let panel = MediaSidebarCard.panelWidth(sidebarWidth: SidebarMetrics.iconsWidth, isStowed: true)
        #expect(panel == MediaSidebarCard.floatingWidth)
        #expect(!MediaSidebarCard.isCompact(panelWidth: panel))
    }
}
