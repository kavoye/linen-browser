// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

@MainActor
enum FaviconTint {
    private static let side = 16
    private static let opaqueEnough = 0.35
    private static let cacheLimit = 256

    private static var cache: [ObjectIdentifier: Color?] = [:]
    private static var held: [UUID: Color] = [:]

    static func of(_ image: NSImage?, heldBy tab: UUID) -> Color? {
        if let fresh = of(image) {
            if held.count >= cacheLimit {
                held.removeAll(keepingCapacity: true)
            }
            held[tab] = fresh
            return fresh
        }
        return held[tab]
    }

    static func forget(_ tab: UUID) {
        held[tab] = nil
    }

    static func of(_ image: NSImage?) -> Color? {
        guard let image else { return nil }
        let key = ObjectIdentifier(image)
        if let known = cache[key] {
            return known
        }
        if cache.count >= cacheLimit {
            cache.removeAll(keepingCapacity: true)
        }
        let derived = dominant(of: image).map(Color.init(nsColor:))
        cache[key] = derived
        return derived
    }

    private static func dominant(of image: NSImage) -> NSColor? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: side, height: side, bitsPerComponent: 8,
                  bytesPerRow: side * 4, space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        context.interpolationQuality = .medium
        context.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: side * side * 4)

        var red = 0.0
        var green = 0.0
        var blue = 0.0
        var total = 0.0
        for offset in stride(from: 0, to: side * side * 4, by: 4) {
            let alpha = Double(pixels[offset + 3]) / 255
            guard alpha > opaqueEnough else { continue }
            let r = Double(pixels[offset]) / 255 / alpha
            let g = Double(pixels[offset + 1]) / 255 / alpha
            let b = Double(pixels[offset + 2]) / 255 / alpha
            let high = max(r, max(g, b))
            let low = min(r, min(g, b))
            let saturation = high > 0 ? (high - low) / high : 0
            let weight = alpha * (0.15 + saturation)
            red += r * weight
            green += g * weight
            blue += b * weight
            total += weight
        }
        guard total > 0 else { return nil }
        return NSColor(
            srgbRed: red / total,
            green: green / total,
            blue: blue / total,
            alpha: 1
        )
    }
}
