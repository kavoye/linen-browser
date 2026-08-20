// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import CoreGraphics
import SwiftUI
import Testing

@testable import Linen

struct ChromeInkTests {
    private func resolved(_ color: Color) -> NSColor {
        NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
    }

    // MARK: - Which way the ink points

    @Test func aLightBandTakesDarkerInkAsItGetsMoreEmphatic() {
        let black = resolved(ChromeInk.wash(onLight: true, opacity: 1))
        #expect(black.brightnessComponent < 0.01)
    }

    @Test func aDarkBandTakesLighterInk() {
        let white = resolved(ChromeInk.wash(onLight: false, opacity: 1))
        #expect(white.brightnessComponent > 0.99)
    }

    @Test func theTwoSidesAreNeverTheSameColor() {
        let onLight = resolved(ChromeInk.wash(onLight: true, opacity: 1))
        let onDark = resolved(ChromeInk.wash(onLight: false, opacity: 1))
        #expect(abs(onLight.brightnessComponent - onDark.brightnessComponent) > 0.9)
    }

    @Test func aWashCarriesTheOpacityItWasAskedFor() {
        #expect(abs(resolved(ChromeInk.wash(onLight: true, opacity: 0.08)).alphaComponent - 0.08) < 0.001)
        #expect(abs(resolved(ChromeInk.wash(onLight: false, opacity: 0.3)).alphaComponent - 0.3) < 0.001)
    }

    // MARK: - The ladder

    @Test func hoveringIsTheFullestAGlyphGets() {
        for onLight in [true, false] {
            #expect(ChromeInk.glyphOpacity(onLight: onLight, hovering: true) == 1)
        }
    }

    @Test func aDisabledGlyphIsTheFaintestState() {
        for onLight in [true, false] {
            let disabled = ChromeInk.glyphOpacity(onLight: onLight, enabled: false)
            #expect(disabled < ChromeInk.glyphOpacity(onLight: onLight, subdued: true))
            #expect(disabled < ChromeInk.glyphOpacity(onLight: onLight))
            #expect(disabled < ChromeInk.glyphOpacity(onLight: onLight, hovering: true))
        }
    }

    @Test func subduedSitsBetweenDisabledAndPlain() {
        for onLight in [true, false] {
            let subdued = ChromeInk.glyphOpacity(onLight: onLight, subdued: true)
            #expect(subdued > ChromeInk.glyphOpacity(onLight: onLight, enabled: false))
            #expect(subdued < ChromeInk.glyphOpacity(onLight: onLight))
        }
    }

    @Test func disabledOutranksHoveringAndSubduing() {
        for onLight in [true, false] {
            let disabled = ChromeInk.glyphOpacity(onLight: onLight, enabled: false)
            #expect(ChromeInk.glyphOpacity(onLight: onLight, enabled: false, hovering: true) == disabled)
            #expect(ChromeInk.glyphOpacity(onLight: onLight, enabled: false, subdued: true) == disabled)
        }
    }

    @Test func hoveringOutranksSubduing() {
        for onLight in [true, false] {
            #expect(ChromeInk.glyphOpacity(onLight: onLight, hovering: true, subdued: true) == 1)
        }
    }

    @Test func darkBandsCarryTheirInkSlightlyFurther() {
        #expect(ChromeInk.glyphOpacity(onLight: false) > ChromeInk.glyphOpacity(onLight: true))
        #expect(ChromeInk.glyphOpacity(onLight: false, subdued: true)
            > ChromeInk.glyphOpacity(onLight: true, subdued: true))
        #expect(ChromeInk.glyphOpacity(onLight: false, enabled: false)
            > ChromeInk.glyphOpacity(onLight: true, enabled: false))
    }

    @Test func everyStateStaysWithinTheOpacityRange() {
        for onLight in [true, false] {
            for enabled in [true, false] {
                for hovering in [true, false] {
                    for subdued in [true, false] {
                        let value = ChromeInk.glyphOpacity(
                            onLight: onLight, enabled: enabled, hovering: hovering, subdued: subdued
                        )
                        #expect(value > 0 && value <= 1)
                    }
                }
            }
        }
    }
}

struct ThemeRadiusTests {
    @Test func anInsetShapeFollowsItsContainer() {
        #expect(Theme.Radius.nested(in: Theme.Radius.card, inset: 4) == Theme.Radius.card - 4)
    }

    @Test func aDeepInsetStopsAtTheTightestCorner() {
        #expect(Theme.Radius.nested(in: Theme.Radius.control, inset: 40) == Theme.Radius.tight)
        #expect(Theme.Radius.nested(in: 0, inset: 0) == Theme.Radius.tight)
    }

    @Test func anInsetCornerIsNeverRounderThanItsContainer() {
        for container in [Theme.Radius.panel, Theme.Radius.card, Theme.Radius.control, Theme.Radius.chip] {
            for inset in stride(from: 0.0 as CGFloat, through: 24, by: 1) {
                #expect(Theme.Radius.nested(in: container, inset: inset) <= max(container, Theme.Radius.tight))
            }
        }
    }

    @Test func theRadiiRunFromWidestToTightest() {
        #expect(Theme.Radius.panel > Theme.Radius.card)
        #expect(Theme.Radius.card > Theme.Radius.control)
        #expect(Theme.Radius.control > Theme.Radius.chip)
        #expect(Theme.Radius.chip > Theme.Radius.tight)
    }

    @Test func hoverPlatesMatchTheControlsTheySitUnder() {
        #expect(Theme.Radius.hover == Theme.Radius.control)
    }
}
