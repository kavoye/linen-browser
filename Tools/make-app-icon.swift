#!/usr/bin/env swift

// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

//
// Draws Linen's app icon and writes Linen/AppIcon.icon.
//
//     swift Tools/make-app-icon.swift
//
// The icon is generated rather than drawn by hand so it stays editable: the
// geometry below is the source, and the mark PNG is build output that happens
// to be committed. Re-run from the repository root after changing anything.
//
// Output is an **Icon Composer document**, not an .appiconset. That is the only
// way to get a light/dark app icon on macOS 26: actool accepts `appearances` on
// an .appiconset for iOS, but for the mac idiom it silently drops every dark
// image and ships the light one twice. In this format we supply just the mark
// on a transparent canvas and the system draws the tile, the material and the
// shadow - which is also why the icon picks up the tinted and clear appearances
// for free.
//
// The schema below (specialization lists whose *unlabelled* entry is the base
// value) was read off a shipping .icon document; `Icon Composer.app` can open
// this file if you would rather edit it there.

import AppKit
import CoreGraphics
import Foundation

// MARK: - The mark
//
// A disc split by an offset seam, the two halves stepped apart: a threshold.
// Abstract on purpose - it says "a way through", not "a browser" and not "a
// microphone". Geometry is on the 1024pt canvas Icon Composer expects.

let canvas = 1024
let center = CGPoint(x: 512, y: 512)
let radius: CGFloat = 290
let seam: CGFloat = 58          // the gap between the two halves
let step: CGFloat = 74          // how far each half slides along the seam

func renderMark() -> CGImage {
    let ctx = CGContext(data: nil, width: canvas, height: canvas, bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setAllowsAntialiasing(true)
    // Any opaque colour will do: the layer fill below recolours the shape per
    // appearance, using this image purely as a mask.
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))

    for (side, offset) in [(-1.0, step), (1.0, -step)] as [(CGFloat, CGFloat)] {
        ctx.saveGState()
        let edge = center.x + side * seam / 2
        ctx.clip(to: side < 0
            ? CGRect(x: 0, y: 0, width: edge, height: CGFloat(canvas))
            : CGRect(x: edge, y: 0, width: CGFloat(canvas) - edge, height: CGFloat(canvas)))
        ctx.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius + offset,
                                   width: radius * 2, height: radius * 2))
        ctx.restoreGState()
    }
    return ctx.makeImage()!
}

// MARK: - The document

/// Near-black on the light tile, near-white on the dark one. The tile itself is
/// left to the system (`system-light` / `system-dark`) so it tracks whatever
/// macOS considers the standard icon ground.
let lightInk = "srgb:0.07059,0.07059,0.09412,1.00000"
let darkInk = "srgb:0.96078,0.96471,0.97255,1.00000"

let document: [String: Any] = [
    "fill-specializations": [
        ["value": "system-light"],
        ["appearance": "dark", "value": "system-dark"],
    ],
    "groups": [
        [
            "layers": [
                [
                    "image-name": "Mark.png",
                    "name": "Mark",
                    "glass": false,
                    "hidden": false,
                    "fill-specializations": [
                        ["value": ["solid": lightInk]],
                        ["appearance": "dark", "value": ["solid": darkInk]],
                    ],
                ],
            ],
            "lighting": "individual",
            "shadow": ["kind": "neutral", "opacity": 0.5],
            "translucency": ["enabled": false, "value": 0.5],
        ],
    ],
    "supported-platforms": ["squares": ["macOS"]],
]

// MARK: - Write

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Linen").path) else {
    FileHandle.standardError.write(Data("run this from the repository root\n".utf8))
    exit(1)
}

let icon = root.appendingPathComponent("Linen/AppIcon.icon")
let assets = icon.appendingPathComponent("Assets")
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

let image = renderMark()
let rep = NSBitmapImageRep(cgImage: image)
rep.size = NSSize(width: image.width, height: image.height)
try rep.representation(using: .png, properties: [:])!
    .write(to: assets.appendingPathComponent("Mark.png"))

let json = try JSONSerialization.data(withJSONObject: document,
                                      options: [.prettyPrinted, .sortedKeys])
try json.write(to: icon.appendingPathComponent("icon.json"))

print("wrote \(icon.path)")
