// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct ComposingOrb: View {
    var size: CGFloat = 14

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                Canvas { context, canvasSize in
                    Self.paint(context, side: canvasSize.width, t: 0.6)
                }
            } else {
                TimelineView(.animation) { timeline in
                    Canvas { context, canvasSize in
                        let t = timeline.date.timeIntervalSinceReferenceDate * Self.speed
                        Self.paint(context, side: canvasSize.width, t: t)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static let speed = 3.12
    private static let ghostCount = 8
    private static let lanes = 10
    private static let segments = 20
    private static let dotBase = 1.1 * 1.073
    private static let dotDepth = 1.7 * 1.073
    private static let dotMin = 0.3
    private static let cameraTilt = 0.3
    private static let bandTilt = 0.55

    private struct Dot {
        var x: Double
        var y: Double
        var z: Double
        var r: Double
        var opacity: Double
    }

    private static func paint(_ context: GraphicsContext, side: Double, t: Double) {
        let c = side / 2
        let orbR = c * 0.78
        let radiusScale = pow(side / 300, 0.6)
        let st = sin(cameraTilt)
        let ct = cos(cameraTilt)

        func project(_ x: Double, _ y: Double, _ z: Double) -> (Double, Double, Double) {
            (c + x, c - (y * ct - z * st), y * st + z * ct)
        }

        var dots: [Dot] = []
        dots.reserveCapacity(ghostCount + lanes * segments)

        let golden = Double.pi * (3 - 5.0.squareRoot())
        for i in 0..<ghostCount {
            let fy = 1 - (2 * (Double(i) + 0.5)) / Double(ghostCount)
            let ring = (1 - fy * fy).squareRoot()
            let angle = Double(i) * golden
            let (px, py, z) = project(ring * cos(angle) * orbR, fy * orbR, ring * sin(angle) * orbR)
            let depth = (z / orbR + 1) / 2
            dots.append(Dot(
                x: px, y: py, z: z,
                r: max(dotMin, 0.8 * radiusScale),
                opacity: (0.1 + 0.22 * depth) * (1 - 0.78)
            ))
        }

        let sb = sin(bandTilt)
        let cb = cos(bandTilt)
        let halfSpan = Double(lanes - 1) / 2
        for lane in 0..<lanes {
            let centered = Double(lane) - halfSpan
            let laneOffset = centered * 0.075
            let edge = abs(centered) / halfSpan
            for k in 0..<segments {
                let a = Double(k) / Double(segments) * 2 * .pi
                let wobble = 0.16 * sin(a * 3 - t * 1.7 + Double(lane) * 0.22)
                    + 0.07 * sin(a * 5 + t * 1.1)
                let off = laneOffset + wobble
                let x = cos(a)
                let y = cb * sin(a) - sb * off
                let z = sb * sin(a) + cb * off
                let l = (x * x + y * y + z * z).squareRoot()
                let (px, py, zr) = project(x / l * orbR, y / l * orbR, z / l * orbR)
                let depth = (zr / orbR + 1) / 2
                let white = min(1, max(0, 0.52 - 0.44 * depth + 0.18 * edge))
                dots.append(Dot(
                    x: px, y: py, z: zr,
                    r: max(dotMin, (dotBase + dotDepth * depth) * (1 - 0.25 * edge) * radiusScale),
                    opacity: (0.4 + 0.6 * depth) * (1 - white)
                ))
            }
        }

        let ordered = dots.enumerated()
            .sorted { $0.element.z != $1.element.z ? $0.element.z < $1.element.z : $0.offset < $1.offset }
            .map(\.element)
        for dot in ordered where dot.opacity >= 0.02 {
            context.fill(
                Path(ellipseIn: CGRect(
                    x: dot.x - dot.r,
                    y: dot.y - dot.r,
                    width: dot.r * 2,
                    height: dot.r * 2
                )),
                with: .color(.primary.opacity(dot.opacity))
            )
        }
    }
}
