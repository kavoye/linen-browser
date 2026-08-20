// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation

nonisolated enum FaviconInk {
    static let flatChroma = 0.15
    static let flatRange = 0.3
    static let darkLimit = 0.4
    static let lightLimit = 0.6

    static func bitmap(_ data: Data) -> NSBitmapImageRep? {
        NSBitmapImageRep(data: data) ?? rasterized(data)
    }

    static func needsInk(_ data: Data, isDark: Bool) -> Bool {
        guard let reading = read(data), reading.covered > 0 else { return false }
        guard reading.chroma <= flatChroma, reading.range <= flatRange else { return false }
        return isDark ? reading.luminance < darkLimit : reading.luminance > lightLimit
    }

    static func inked(_ data: Data, isDark: Bool, side: Int = 32) -> Data? {
        guard let source = NSImage(data: data), source.isValid,
              let rep = makeRep(side: side),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

        let bounds = NSRect(x: 0, y: 0, width: side, height: side)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        source.draw(in: bounds)
        (isDark ? NSColor.white : NSColor.black).set()
        bounds.fill(using: .sourceAtop)
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .png, properties: [:])
    }

    private struct Reading {
        var luminance = 0.0
        var chroma = 0.0
        var range = 0.0
        var covered = 0
    }

    private static func read(_ data: Data) -> Reading? {
        guard let rep = bitmap(data) else { return nil }
        var luminance = 0.0
        var chroma = 0.0
        var covered = 0
        var darkest = 1.0
        var lightest = 0.0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let raw = rep.colorAt(x: x, y: y), raw.alphaComponent > 0.5,
                      let colour = raw.usingColorSpace(.deviceRGB) else { continue }
                covered += 1
                let red = colour.redComponent
                let green = colour.greenComponent
                let blue = colour.blueComponent
                let level = 0.2126 * red + 0.7152 * green + 0.0722 * blue
                luminance += level
                if raw.alphaComponent > 0.9 {
                    darkest = min(darkest, level)
                    lightest = max(lightest, level)
                }
                chroma += max(red, green, blue) - min(red, green, blue)
            }
        }
        guard covered > 0 else { return Reading() }
        return Reading(
            luminance: luminance / Double(covered),
            chroma: chroma / Double(covered),
            range: max(0, lightest - darkest),
            covered: covered
        )
    }

    private static func rasterized(_ data: Data, side: Int = 32) -> NSBitmapImageRep? {
        guard let image = NSImage(data: data), image.isValid,
              let rep = makeRep(side: side),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private static func makeRep(side: Int) -> NSBitmapImageRep? {
        NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: side,
            pixelsHigh: side,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
    }
}
