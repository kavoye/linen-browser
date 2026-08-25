// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI
import Testing

@testable import Linen

@MainActor
struct AppearancePickerFitTests {
    private func widthTaken(_ view: some View, proposing width: CGFloat) -> CGFloat {
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: width, height: 900)
        renderer.scale = 1
        return renderer.nsImage?.size.width ?? 0
    }

    @Test func theThemeCardsWrapIntoANarrowPage() {
        let narrow = AppearanceThumbnailMetrics.width + 20
        let picker = ThemePicker(selection: .system, onSelect: { _ in })

        #expect(widthTaken(picker, proposing: narrow) <= narrow)
    }

    @Test func theWindowStyleCardsWrapIntoANarrowPage() {
        let narrow = AppearanceThumbnailMetrics.width + 20
        let picker = LoomStylePicker(
            selection: .standard,
            usesWebsiteTint: false,
            tintsSelectedTab: false,
            onSelect: { _ in }
        )

        #expect(widthTaken(picker, proposing: narrow) <= narrow)
    }

    @Test func theCardsStayInOneRowWhenThereIsRoom() {
        let roomy = AppearanceThumbnailMetrics.width * 3
            + AppearanceThumbnailMetrics.spacing * 2
        let picker = ThemePicker(selection: .system, onSelect: { _ in })

        #expect(widthTaken(picker, proposing: roomy) <= roomy)
    }
}
