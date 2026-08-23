// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import CoreGraphics
import SwiftUI
import Testing

@testable import Linen

@MainActor
struct AskSurfacePlacementTests {
    private let toolbar = AskSurface.Placement.toolbar
    private let startPage = AskSurface.Placement.startPage

    // MARK: - The start page is the larger of the two

    @Test func theStartPageFieldIsTallerAndRoomier() {
        #expect(startPage.rowHeight > toolbar.rowHeight)
        #expect(startPage.rowInset > toolbar.rowInset)
        #expect(startPage.controlSpacing > toolbar.controlSpacing)
    }

    @Test func theStartPageSetsItsTextAndOrbLarger() {
        #expect(startPage.textSize > toolbar.textSize)
        #expect(startPage.orbSize > toolbar.orbSize)
    }

    @Test func theStartPageShowsMoreOfALongReply() {
        #expect(startPage.messageLineLimit > toolbar.messageLineLimit)
    }

    // MARK: - Everything has to fit

    @Test func theOrbHasRoomInsideTheRow() {
        for placement in [toolbar, startPage] {
            #expect(placement.iconSlot > placement.orbSize)
            #expect(placement.iconSlot < placement.rowHeight)
        }
    }

    @Test func theTextFitsWithinTheRow() {
        for placement in [toolbar, startPage] {
            #expect(placement.textSize < placement.rowHeight)
        }
    }

    @Test func everyMeasurementIsAPositiveLength() {
        for placement in [toolbar, startPage] {
            #expect(placement.rowHeight > 0)
            #expect(placement.orbSize > 0)
            #expect(placement.textSize > 0)
            #expect(placement.rowInset > 0)
            #expect(placement.controlSpacing > 0)
            #expect(placement.cornerRadius > 0)
            #expect(placement.messageLineLimit > 0)
        }
    }

    @Test func bothPlacementsUseTheSameCardCorner() {
        #expect(toolbar.cornerRadius == startPage.cornerRadius)
        #expect(toolbar.cornerRadius == Theme.Radius.card)
    }

    @Test func bothPlacementsOfferTheSamePrompt() {
        #expect(toolbar.placeholder == startPage.placeholder)
        #expect(!toolbar.placeholder.isEmpty)
    }

    // MARK: - What each one is for

    @Test func onlyTheToolbarFieldStandsInForTheAddressBar() {
        #expect(toolbar.mirrorsPageURL)
        #expect(!startPage.mirrorsPageURL)
        #expect(toolbar.showsSiteControls)
        #expect(!startPage.showsSiteControls)
    }

    @Test func onlyTheStartPageFieldTakesFocusByItself() {
        #expect(startPage.takesFocusOnAppear)
        #expect(!toolbar.takesFocusOnAppear)
    }

    @Test func onlyTheStartPageHasRoomForHintsAndActivity() {
        #expect(startPage.showsKeyHints)
        #expect(!toolbar.showsKeyHints)
    }

}

@MainActor
struct AskSurfaceStatusTests {
    private func resolved(_ color: Color) -> NSColor {
        NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
    }

    private func distance(_ one: Color, _ other: Color) -> CGFloat {
        let first = resolved(one)
        let second = resolved(other)
        return abs(first.redComponent - second.redComponent)
            + abs(first.greenComponent - second.greenComponent)
            + abs(first.blueComponent - second.blueComponent)
    }

    @Test func listeningWarningAndWorkingAreThreeDifferentColors() {
        #expect(distance(AskSurfaceStatus.listening.color, AskSurfaceStatus.warning.color) > 0.15)
        #expect(distance(AskSurfaceStatus.listening.color, AskSurfaceStatus.agent.color) > 0.15)
        #expect(distance(AskSurfaceStatus.warning.color, AskSurfaceStatus.agent.color) > 0.15)
    }

    @Test func listeningIsDrawnInTheRecordingColor() {
        #expect(distance(AskSurfaceStatus.listening.color, Theme.danger) < 0.01)
    }

    @Test func theAssistantWorkingIsDrawnInTheAccent() {
        #expect(distance(AskSurfaceStatus.agent.color, Theme.accent) < 0.01)
    }

    @Test func aWarningIsNotDrawnInTheAccent() {
        #expect(distance(AskSurfaceStatus.warning.color, Theme.accent) > 0.15)
    }
}
