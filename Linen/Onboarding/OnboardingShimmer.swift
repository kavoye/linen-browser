// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class ShimmerClock {
    private let start = Date()
    private var bankedBoost: Double = 0
    private var emphasisAt: Date?

    func emphasize() {
        let now = Date()
        if let emphasisAt {
            bankedBoost += Self.boost(now.timeIntervalSince(emphasisAt))
        }
        self.emphasisAt = now
    }

    func elapsed(at date: Date) -> Double {
        date.timeIntervalSince(start)
    }

    private(set) var pointer: CGPoint = .zero
    private var pointerFrom: Double = 0
    private var pointerTarget: Double = 0
    private var pointerChangedAt = Date.distantPast

    func movePointer(to location: CGPoint) {
        if pointerTarget == 0 {
            pointer = location
        } else {
            pointer.x += (location.x - pointer.x) * 0.25
            pointer.y += (location.y - pointer.y) * 0.25
        }
        aimPointer(at: 1)
    }

    func releasePointer() {
        aimPointer(at: 0)
    }

    func pointerWeight(at date: Date) -> Double {
        let progress = min(1, max(0, date.timeIntervalSince(pointerChangedAt) / Self.pointerFade))
        let eased = 1 - pow(1 - progress, 3)
        return pointerFrom + (pointerTarget - pointerFrom) * eased
    }

    private func aimPointer(at value: Double) {
        guard value != pointerTarget else { return }
        pointerFrom = pointerWeight(at: Date())
        pointerTarget = value
        pointerChangedAt = Date()
    }

    private static let pointerFade: Double = 0.9

    func phases(at date: Date) -> SIMD2<Float> {
        let advanced = elapsed(at: date) + bankedBoost + pendingBoost(at: date)
        return SIMD2(
            Float(ShimmerWave.speed * advanced),
            Float(-ShimmerWave.secondarySpeed * advanced)
        )
    }

    func shine(at date: Date) -> Float {
        guard let emphasisAt else { return 0 }
        return Float(Self.multiplierOffset(date.timeIntervalSince(emphasisAt)) / Self.peak)
    }

    private func pendingBoost(at date: Date) -> Double {
        guard let emphasisAt else { return 0 }
        return Self.boost(date.timeIntervalSince(emphasisAt))
    }

    private static let peak: Double = 1.15
    private static let rampUp: Double = 0.14
    private static let hold: Double = 0.32
    private static let rampDown: Double = 0.48

    private static func boost(_ elapsed: Double) -> Double {
        guard elapsed > 0 else { return 0 }
        if elapsed < rampUp {
            return 0.5 * peak * elapsed * elapsed / rampUp
        }
        let upArea = 0.5 * peak * rampUp
        if elapsed < rampUp + hold {
            return upArea + peak * (elapsed - rampUp)
        }
        let holdArea = upArea + peak * hold
        let falling = elapsed - rampUp - hold
        guard falling < rampDown else { return holdArea + 0.5 * peak * rampDown }
        return holdArea + peak * (falling - falling * falling / (2 * rampDown))
    }

    private static func multiplierOffset(_ elapsed: Double) -> Double {
        guard elapsed > 0 else { return 0 }
        if elapsed < rampUp {
            return peak * elapsed / rampUp
        }
        if elapsed < rampUp + hold {
            return peak
        }
        let falling = elapsed - rampUp - hold
        guard falling < rampDown else { return 0 }
        return peak * (1 - falling / rampDown)
    }
}

enum ShimmerWave {
    static let speed: Double = 0.42
    static let secondarySpeed: Double = 0.26

    static let targetStripeWidth: CGFloat = 110
    static let minStripeWidth: CGFloat = 64
    static let maxStripeWidth: CGFloat = 120

    static func stripeCount(forWidth width: CGFloat) -> CGFloat {
        guard width > minStripeWidth else { return 1 }
        let fewest = (width / maxStripeWidth).rounded(.up)
        let most = (width / minStripeWidth).rounded(.down)
        let target = (width / targetStripeWidth).rounded()
        return max(1, min(max(target, fewest), max(fewest, most)))
    }
}

struct OnboardingShimmer: View {
    let clock: ShimmerClock

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var size: CGSize = .zero

    var body: some View {
        Group {
            if reduceMotion {
                canvas(phases: SIMD2(0.9, -0.6), intro: SIMD2(100, 0), pointerWeight: 0)
            } else {
                TimelineView(.animation) { context in
                    canvas(
                        phases: clock.phases(at: context.date),
                        intro: SIMD2(Float(clock.elapsed(at: context.date)), clock.shine(at: context.date)),
                        pointerWeight: clock.pointerWeight(at: context.date)
                    )
                }
            }
        }
        .onGeometryChange(for: CGSize.self) {
            $0.size
        } action: {
            size = $0
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func canvas(phases: SIMD2<Float>, intro: SIMD2<Float>, pointerWeight: Double) -> some View {
        let count = ShimmerWave.stripeCount(forWidth: size.width)
        let palette = Self.palette(isDark: scheme == .dark)
        return Rectangle()
            .fill(
                ShaderLibrary.linenShimmer(
                    .float2(size),
                    .float2(Float(size.width / count), Float(count - 1)),
                    .float2(phases.x, phases.y),
                    .float2(intro.x, intro.y),
                    .float3(Float(clock.pointer.x), Float(clock.pointer.y), Float(pointerWeight)),
                    .float3(palette.start.x, palette.start.y, palette.start.z),
                    .float3(palette.delta.x, palette.delta.y, palette.delta.z),
                    .float4(
                        Float(Self.grainAlpha(isDark: scheme == .dark)),
                        Float(Self.grainSaturation(isDark: scheme == .dark)),
                        Float(Self.grainLuminance(isDark: scheme == .dark)),
                        Float(Self.grainContrast(isDark: scheme == .dark))
                    )
                )
            )
    }
}

extension OnboardingShimmer {
    private static func grainAlpha(isDark: Bool) -> Double {
        isDark ? 0.10 : 0.07
    }

    private static func grainSaturation(isDark: Bool) -> Double {
        isDark ? 32 : 8
    }

    private static func grainLuminance(isDark: Bool) -> Double {
        isDark ? 144 : 220
    }

    private static func grainContrast(isDark: Bool) -> Double {
        isDark ? 64 : 34
    }

    private static func palette(isDark: Bool) -> (start: SIMD3<Float>, delta: SIMD3<Float>) {
        let base = windowBackground(isDark: isDark)
        let target: SIMD3<Float> = isDark ? SIMD3(repeating: 1) : SIMD3(repeating: 0)
        let ink: Float = isDark ? 0.09 : 0.07
        return (base, (target - base) * ink)
    }

    private static func windowBackground(isDark: Bool) -> SIMD3<Float> {
        var components = SIMD3<Float>(0.98, 0.98, 0.99)
        let appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        appearance?.performAsCurrentDrawingAppearance {
            guard let resolved = NSColor(Theme.windowBackground).usingColorSpace(.sRGB) else { return }
            components = SIMD3(
                Float(resolved.redComponent),
                Float(resolved.greenComponent),
                Float(resolved.blueComponent)
            )
        }
        return components
    }
}
