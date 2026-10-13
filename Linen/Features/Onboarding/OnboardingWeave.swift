// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

extension OnboardingUI {
    struct Weave: View {
        let start: Date
        let landing: CGFloat
        var side: CGFloat = 220

        static let iconCue: Double = 1.8
        static let duration: Double = 2.2

        private static let threads = 7
        private static let fall: Double = 0.65
        private static let stagger: Double = 0.08
        private static let crossStart: Double = 0.6
        private static let tightenStart: Double = 1.45
        private static let tighten: Double = 0.45
        private static let fadeStart: Double = 1.85
        private static let fade: Double = 0.3
        private static let tileCornerFraction: CGFloat = 0.2282

        var body: some View {
            TimelineView(.animation) { context in
                let elapsed = context.date.timeIntervalSince(start)
                Canvas { canvas, size in
                    draw(in: &canvas, size: size, at: elapsed)
                }
            }
            .frame(width: side, height: side)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }

        private func draw(in canvas: inout GraphicsContext, size: CGSize, at elapsed: Double) {
            let tightening = Self.easeInOut(Self.progress(elapsed, from: Self.tightenStart, over: Self.tighten))
            let opacity = 1 - Self.progress(elapsed, from: Self.fadeStart, over: Self.fade)
            guard opacity > 0 else { return }

            canvas.opacity = opacity
            canvas.translateBy(x: size.width / 2, y: size.height / 2)
            canvas.rotate(by: .degrees(90 * tightening))
            let scale = 1 - (1 - landing / side) * tightening
            canvas.scaleBy(x: scale, y: scale)
            canvas.clip(to: Path(
                roundedRect: CGRect(x: -side / 2, y: -side / 2, width: side, height: side),
                cornerRadius: side * Self.tileCornerFraction * tightening,
                style: .continuous
            ))

            let count = Self.threads
            let pitch = side / CGFloat(count)
            let width = pitch * 0.46
            let gap = width + pitch * 0.14
            let half = side / 2
            let middle = Double(count - 1) / 2

            func center(_ index: Int) -> CGFloat {
                -half + pitch * (CGFloat(index) + 0.5)
            }

            for column in 0..<count {
                let delay = abs(Double(column) - middle) * Self.stagger
                let reach = Self.easeOut(Self.progress(elapsed, from: delay, over: Self.fall))
                guard reach > 0 else { continue }
                let rect = CGRect(x: center(column) - width / 2, y: -half, width: width, height: side * reach)
                canvas.fill(Path(roundedRect: rect, cornerRadius: width / 2), with: .color(.primary.opacity(0.5)))
            }

            canvas.blendMode = .copy
            for row in 0..<count {
                let delay = Self.crossStart + abs(Double(row) - middle) * Self.stagger
                let reach = Self.easeOut(Self.progress(elapsed, from: delay, over: Self.fall))
                guard reach > 0 else { continue }
                let length = side * reach
                let span = row.isMultiple(of: 2)
                    ? (-half)...(-half + length)
                    : (half - length)...half
                var lower = span.lowerBound
                for column in 0..<count where (column + row).isMultiple(of: 2) {
                    let gapStart = center(column) - gap / 2
                    let gapEnd = center(column) + gap / 2
                    guard gapStart < span.upperBound else { break }
                    if gapStart > lower {
                        segment(from: lower, to: gapStart, row: center(row), width: width, in: &canvas)
                    }
                    lower = max(lower, gapEnd)
                }
                if lower < span.upperBound {
                    segment(from: lower, to: span.upperBound, row: center(row), width: width, in: &canvas)
                }
            }
        }

        private func segment(from start: CGFloat, to end: CGFloat, row: CGFloat, width: CGFloat, in canvas: inout GraphicsContext) {
            let rect = CGRect(x: start, y: row - width / 2, width: end - start, height: width)
            canvas.fill(Path(rect), with: .color(.primary.opacity(0.3)))
        }

        private static func progress(_ elapsed: Double, from start: Double, over duration: Double) -> Double {
            min(1, max(0, (elapsed - start) / duration))
        }

        private static func easeOut(_ value: Double) -> Double {
            1 - pow(1 - value, 3)
        }

        private static func easeInOut(_ value: Double) -> Double {
            value < 0.5 ? 4 * value * value * value : 1 - pow(-2 * value + 2, 3) / 2
        }
    }
}
