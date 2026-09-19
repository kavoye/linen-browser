// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct AddressLoadingIndicator: View {
    let progress: Double
    let isLoading: Bool
    let isSuppressed: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animation = AddressLoadingAnimation()
    @State private var isAnimating = false

    private var input: AddressLoadingInput {
        AddressLoadingInput(progress: progress, isLoading: isLoading)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isAnimating || isSuppressed || reduceMotion)) { _ in
            AddressLoadingArtwork(
                frame: animation.frame(at: ProcessInfo.processInfo.systemUptime, reduceMotion: reduceMotion),
                color: .accentColor
            )
        }
        .opacity(isSuppressed ? 0 : 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: input) {
            animation.update(input, at: ProcessInfo.processInfo.systemUptime)
            isAnimating = input.isLoading || animation.hasProgress
            guard !input.isLoading else { return }
            if animation.hasProgress, !reduceMotion {
                do {
                    try await Task.sleep(for: .seconds(AddressLoadingAnimation.completionDuration))
                } catch {
                    return
                }
            }
            isAnimating = false
        }
    }
}

struct AddressLoadingInput: Equatable {
    let progress: Double
    let isLoading: Bool

    init(progress: Double, isLoading: Bool) {
        self.progress = progress.isFinite ? min(max(progress, 0), 1) : 0
        self.isLoading = isLoading
    }
}

struct AddressLoadingAnimation {
    static let advanceDuration = 0.18
    static let fadeDuration = 0.32
    static let completionDuration = advanceDuration + fadeDuration

    private var origin = 0.0
    private var target = 0.0
    private var changedAt = 0.0
    private var startedAt = 0.0
    private var finishesAt: Double?
    private var isLoading = false

    var hasProgress: Bool {
        target > 0
    }

    mutating func update(_ input: AddressLoadingInput, at time: Double) {
        if input.isLoading {
            if !isLoading || (input.progress <= 0.1 && input.progress < target) {
                origin = 0
                target = max(0.05, input.progress)
                changedAt = time
                startedAt = time
                finishesAt = nil
            } else if input.progress > target {
                origin = fraction(at: time)
                target = input.progress
                changedAt = time
            }
        } else if isLoading {
            origin = fraction(at: time)
            target = 1
            changedAt = time
            finishesAt = time + Self.advanceDuration
        }
        isLoading = input.isLoading
    }

    func frame(at time: Double, reduceMotion: Bool = false) -> AddressLoadingFrame {
        let exit = finishesAt.map { reduceMotion ? 1 : Self.unit((time - $0) / Self.fadeDuration) } ?? 0
        let pulse = reduceMotion || !isLoading ? 0.5 : (1 - cos((time - startedAt) * .pi / 0.7)) / 2
        return AddressLoadingFrame(
            progress: reduceMotion ? target : fraction(at: time),
            glow: 0.5 + 0.35 * pulse,
            exit: exit,
            opacity: hasProgress ? 1 - exit : 0
        )
    }

    private func fraction(at time: Double) -> Double {
        let elapsed = Self.unit((time - changedAt) / Self.advanceDuration)
        let eased = 1 - pow(1 - elapsed, 3)
        return origin + (target - origin) * eased
    }

    private static func unit(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

struct AddressLoadingFrame {
    let progress: Double
    let glow: Double
    let exit: Double
    let opacity: Double
}

struct AddressLoadingArtwork: View {
    let frame: AddressLoadingFrame
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let tail = min(240, max(60, width * 0.45))
            let head = width * frame.progress + frame.exit * (tail + 16)
            let gradient = LinearGradient(
                stops: [
                    .init(color: color.opacity(0), location: 0),
                    .init(color: color.opacity(0.18), location: 0.45),
                    .init(color: color.opacity(0.7), location: 0.82),
                    .init(color: color, location: 1),
                ],
                startPoint: .leading, endPoint: .trailing
            )

            ZStack(alignment: .bottomLeading) {
                Capsule()
                    .fill(color.opacity(0.65))
                    .frame(width: width * frame.progress, height: 1.5)
                    .mask {
                        LinearGradient(
                            colors: [.clear, .black],
                            startPoint: UnitPoint(x: frame.exit * 1.2 - 0.2, y: 0.5),
                            endPoint: UnitPoint(x: frame.exit * 1.2, y: 0.5)
                        )
                    }

                Capsule()
                    .fill(gradient)
                    .frame(width: tail, height: 5)
                    .blur(radius: 4)
                    .opacity(frame.glow)
                    .offset(x: head - tail)

                Capsule()
                    .fill(gradient)
                    .frame(width: tail, height: 1.5)
                    .opacity(frame.glow)
                    .offset(x: head - tail)

                Circle()
                    .fill(color)
                    .overlay(Circle().fill(.white.opacity(0.35)))
                    .frame(width: 5, height: 5)
                    .blur(radius: 2.5)
                    .opacity(frame.glow)
                    .offset(x: head - 2.5, y: 1.75)
            }
            .frame(width: width, height: geometry.size.height, alignment: .bottomLeading)
            .opacity(frame.opacity)
        }
        .clipped()
    }
}
