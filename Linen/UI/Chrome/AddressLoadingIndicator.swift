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
    @State private var timelineStart = Date()

    private var input: AddressLoadingInput {
        AddressLoadingInput(progress: progress, isLoading: isLoading)
    }

    var body: some View {
        Group {
            if isAnimating && !isSuppressed && !reduceMotion {
                TimelineView(.periodic(from: timelineStart, by: 1.0 / 60)) { _ in
                    artwork(at: ProcessInfo.processInfo.systemUptime)
                }
            } else {
                artwork(at: ProcessInfo.processInfo.systemUptime)
            }
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
                    try await Task.sleep(for: .seconds(animation.completionDuration(at: ProcessInfo.processInfo.systemUptime)))
                } catch {
                    return
                }
            }
            isAnimating = false
        }
    }

    private func artwork(at time: Double) -> some View {
        AddressLoadingArtwork(
            frame: animation.frame(at: time, reduceMotion: reduceMotion),
            color: .accentColor
        )
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
    static let advanceSpeed = 1.2
    static let fadeDuration = 0.32
    private static let slowdownStart = 0.88
    private static let tailLength = 0.10
    private static let cruiseSpeed = 0.32
    private static let speedTransition = 0.15

    private var origin = 0.0
    private var target = 0.0
    private var initialSpeed = 0.0
    private var desiredSpeed = 0.0
    private var changedAt = 0.0
    private var startedAt = 0.0
    private var finishesAt: Double?
    private var isLoading = false

    var hasProgress: Bool {
        target > 0
    }

    func completionDuration(at time: Double) -> Double {
        max(0, (finishesAt ?? time) - time) + Self.fadeDuration
    }

    mutating func update(_ input: AddressLoadingInput, at time: Double) {
        if input.isLoading {
            if !isLoading || (input.progress <= 0.1 && input.progress < target) {
                origin = 0
                target = max(0.05, input.progress)
                initialSpeed = 0
                desiredSpeed = Self.cruiseSpeed
                changedAt = time
                startedAt = time
                finishesAt = nil
            } else if input.progress > target {
                let currentDistance = distance(at: time)
                initialSpeed = speed(at: time)
                origin = currentDistance
                target = input.progress
                changedAt = time
            }
            let checkpointSpeed = max(0, Self.distance(for: target) - origin) / 0.7
            desiredSpeed = max(desiredSpeed, min(Self.advanceSpeed, checkpointSpeed))
        } else if isLoading {
            let currentDistance = distance(at: time)
            let currentSpeed = speed(at: time)
            origin = Self.loadingProgress(for: currentDistance)
            initialSpeed = currentSpeed * Self.tailScale(at: currentDistance)
            desiredSpeed = Self.advanceSpeed
            target = 1
            changedAt = time
            var lower = 0.0
            var upper = 2.0
            for _ in 0..<24 {
                let midpoint = (lower + upper) / 2
                if origin + travel(for: midpoint) >= 1 {
                    upper = midpoint
                } else {
                    lower = midpoint
                }
            }
            finishesAt = time + upper
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
        if isLoading {
            return Self.loadingProgress(for: distance(at: time))
        }
        return min(target, distance(at: time))
    }

    private func distance(at time: Double) -> Double {
        let elapsed = max(0, time - changedAt)
        return origin + travel(for: elapsed)
    }

    private func travel(for elapsed: Double) -> Double {
        let transition = Self.speedTransition
        return desiredSpeed * elapsed
            + (initialSpeed - desiredSpeed) * transition * (1 - exp(-elapsed / transition))
    }

    private func speed(at time: Double) -> Double {
        let elapsed = max(0, time - changedAt)
        return desiredSpeed + (initialSpeed - desiredSpeed) * exp(-elapsed / Self.speedTransition)
    }

    private static func loadingProgress(for distance: Double) -> Double {
        guard distance > slowdownStart else { return distance }
        return slowdownStart + tailLength * (1 - exp(-(distance - slowdownStart) / tailLength))
    }

    private static func tailScale(at distance: Double) -> Double {
        distance > slowdownStart ? exp(-(distance - slowdownStart) / tailLength) : 1
    }

    private static func distance(for progress: Double) -> Double {
        guard progress > slowdownStart else { return progress }
        let tailProgress = min(progress - slowdownStart, tailLength * 0.99)
        return slowdownStart - tailLength * log(1 - tailProgress / tailLength)
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
