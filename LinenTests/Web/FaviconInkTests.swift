// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import Testing

@testable import Linen

/// A `mask-icon` is the site naming a shape for the browser to colour.
struct FaviconInkTests {
    private func svg(fill: String) -> Data {
        Data("""
        <svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32">\
        <circle cx="16" cy="16" r="12" fill="\(fill)"/></svg>
        """.utf8)
    }

    @Test func aFlatDarkGlyphIsInkedOnlyOnADarkSidebar() {
        let glyph = svg(fill: "#24292E")
        #expect(FaviconInk.needsInk(glyph, isDark: true))
        #expect(!FaviconInk.needsInk(glyph, isDark: false))
    }

    @Test func aFlatLightGlyphIsInkedOnlyOnALightSidebar() {
        let glyph = svg(fill: "white")
        #expect(FaviconInk.needsInk(glyph, isDark: false))
        #expect(!FaviconInk.needsInk(glyph, isDark: true))
    }

    /// The whole point of the saturation test: a brand keeps its colour.
    @Test func aColouredIconIsNeverInked() {
        for fill in ["#F05138", "#0066CC", "#34C759"] {
            #expect(!FaviconInk.needsInk(svg(fill: fill), isDark: true))
            #expect(!FaviconInk.needsInk(svg(fill: fill), isDark: false))
        }
    }

    /// A black disc with the mark knocked out reads as greyscale and dark, but
    /// inking every opaque pixel would fill the disc and swallow the mark.
    @Test func aPlatedIconIsNotInked() {
        let plated = Data("""
        <svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32">\
        <rect width="32" height="32" fill="black"/>\
        <circle cx="16" cy="16" r="8" fill="white"/></svg>
        """.utf8)
        #expect(!FaviconInk.needsInk(plated, isDark: true))
        #expect(!FaviconInk.needsInk(plated, isDark: false))
    }

    @Test func inkingKeepsTheShapeAndTakesTheContrastingColour() throws {
        let inked = try #require(FaviconInk.inked(svg(fill: "#24292E"), isDark: true))
        let rep = try #require(NSBitmapImageRep(data: inked))

        var light = 0
        var covered = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let colour = rep.colorAt(x: x, y: y), colour.alphaComponent > 0.5 else { continue }
                covered += 1
                if (colour.redComponent + colour.greenComponent + colour.blueComponent) / 3 > 0.9 {
                    light += 1
                }
            }
        }

        #expect(covered > 0)
        #expect(light == covered)
        #expect(covered < rep.pixelsWide * rep.pixelsHigh)
    }

    @Test func inkingAnEmptyGlyphCoversNothing() throws {
        let empty = Data(#"<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"></svg>"#.utf8)
        #expect(!FaviconInk.needsInk(empty, isDark: true))
    }

    @Test func aMaskFromAnotherDocumentIsRefused() {
        let page = URL(string: "https://example.com/page")!
        #expect(FaviconLoader.declaredMaskURL(
            fromAnswer: #"{"host":"other.com","href":"/i.png","mask":"/m.svg"}"#,
            requestedHost: "example.com",
            pageURL: page
        ) == nil)
        #expect(FaviconLoader.declaredMaskURL(
            fromAnswer: #"{"host":"example.com","href":"/i.png","mask":""}"#,
            requestedHost: "example.com",
            pageURL: page
        ) == nil)
        #expect(FaviconLoader.declaredMaskURL(
            fromAnswer: #"{"host":"example.com","href":"/i.png","mask":"/m.svg"}"#,
            requestedHost: "example.com",
            pageURL: page
        )?.absoluteString == "https://example.com/m.svg")
    }
}
