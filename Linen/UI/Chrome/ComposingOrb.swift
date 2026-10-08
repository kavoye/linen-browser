// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct ComposingOrb: View {
    var size: CGFloat = 14
    var isAnimating = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var motion: OrbMotion
    @State private var isSettled: Bool

    init(size: CGFloat = 14, isAnimating: Bool = true) {
        self.size = size
        self.isAnimating = isAnimating
        _motion = State(initialValue: OrbMotion(isRunning: isAnimating, at: .now))
        _isSettled = State(initialValue: !isAnimating)
    }

    var body: some View {
        Group {
            if reduceMotion || isSettled {
                Canvas { context, canvasSize in
                    Self.paint(context, side: canvasSize.width, phase: OrbMotion.restPhase)
                }
            } else {
                TimelineView(.animation) { timeline in
                    Canvas { context, canvasSize in
                        Self.paint(context, side: canvasSize.width, phase: motion.phase(at: timeline.date))
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: isAnimating) { _, running in
            motion = running ? motion.running(at: .now) : motion.braking(at: .now)
            isSettled = false
        }
        .task(id: motion.settlesAt) {
            guard let settlesAt = motion.settlesAt else { return }
            try? await Task.sleep(for: .seconds(max(0, settlesAt.timeIntervalSinceNow)))
            if !Task.isCancelled {
                isSettled = true
            }
        }
    }

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

    private static func paint(_ context: GraphicsContext, side: Double, phase: SIMD2<Double>) {
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
                let wobble = 0.16 * sin(a * 3 - phase.x + Double(lane) * 0.22)
                    + 0.07 * sin(a * 5 + phase.y)
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

nonisolated struct OrbMotion: Sendable {
    static let rate = SIMD2<Double>(1.7, 1.1)
    static let velocity = rate * 3.12
    static let restPhase = rate * 0.6
    private static let rampDuration = 0.45
    private static let minimumBrake = 0.6
    private static let maximumBrake = 3.0

    private enum Segment: Sendable {
        case resting(SIMD2<Double>)
        case running(start: Date, from: SIMD2<Double>, entry: SIMD2<Double>)
        case braking(start: Date, from: SIMD2<Double>, entry: SIMD2<Double>, distance: SIMD2<Double>, duration: SIMD2<Double>)
    }

    private var segment: Segment

    init(isRunning: Bool, at date: Date) {
        segment = isRunning
            ? .running(start: date, from: Self.restPhase, entry: SIMD2(repeating: 1))
            : .resting(Self.restPhase)
    }

    var settlesAt: Date? {
        guard case .braking(let start, _, _, _, let duration) = segment else { return nil }
        return start.addingTimeInterval(max(duration.x, duration.y))
    }

    func phase(at date: Date) -> SIMD2<Double> {
        state(at: date).phase
    }

    func running(at date: Date) -> OrbMotion {
        let now = state(at: date)
        var next = self
        next.segment = .running(start: date, from: now.phase, entry: now.speed.clamped(lowerBound: .zero, upperBound: SIMD2(repeating: 1)))
        return next
    }

    func braking(at date: Date) -> OrbMotion {
        let now = state(at: date)
        var distance = SIMD2<Double>.zero
        var duration = SIMD2<Double>.zero
        for i in 0..<2 {
            let entryVelocity = Self.velocity[i] * max(0, now.speed[i])
            let lead = entryVelocity * Self.minimumBrake / 2
            let gap = (Self.restPhase[i] - now.phase[i] - lead).truncatingRemainder(dividingBy: 2 * .pi)
            distance[i] = lead + (gap < 0 ? gap + 2 * .pi : gap)
            duration[i] = min(max(2 * distance[i] / max(entryVelocity, 1e-6), Self.minimumBrake), Self.maximumBrake)
        }
        var next = self
        next.segment = .braking(start: date, from: now.phase, entry: now.speed, distance: distance, duration: duration)
        return next
    }

    private func state(at date: Date) -> (phase: SIMD2<Double>, speed: SIMD2<Double>) {
        switch segment {
        case .resting(let phase):
            return (phase, .zero)
        case .running(let start, let from, let entry):
            let elapsed = max(0, date.timeIntervalSince(start))
            let ramp = Self.rampDuration
            var phase = from
            var speed = SIMD2<Double>(repeating: 1)
            for i in 0..<2 {
                let u = entry[i]
                let travelled: Double = elapsed < ramp
                    ? u * elapsed + (1 - u) * elapsed * elapsed / (2 * ramp)
                    : elapsed - (1 - u) * ramp / 2
                phase[i] += Self.velocity[i] * travelled
                speed[i] = elapsed < ramp ? u + (1 - u) * elapsed / ramp : 1
            }
            return (phase, speed)
        case .braking(let start, let from, let entry, let distance, let duration):
            let elapsed = max(0, date.timeIntervalSince(start))
            var phase = from
            var speed = SIMD2<Double>.zero
            for i in 0..<2 {
                let d = duration[i]
                let s = min(elapsed / d, 1)
                let tangent: Double = Self.velocity[i] * max(0, entry[i]) * d
                let tangentWeight: Double = s * (1 - s) * (1 - s)
                let distanceWeight: Double = s * s * (3 - 2 * s)
                phase[i] += tangentWeight * tangent + distanceWeight * distance[i]
                let tangentSlope: Double = (1 - s) * (1 - 3 * s)
                let distanceSlope: Double = 6 * s * (1 - s)
                let slope: Double = tangentSlope * tangent + distanceSlope * distance[i]
                speed[i] = s < 1 ? slope / d / Self.velocity[i] : 0
            }
            return (phase, speed)
        }
    }
}
