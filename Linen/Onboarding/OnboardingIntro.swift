// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

private nonisolated let introSpace = "onboarding.intro"
private let heroMarkSize: CGFloat = 168
private let settledMarkSize: CGFloat = 104

extension OnboardingUI {
    enum IntroPhase {
        case hidden
        case hero
        case settled
    }

    struct WelcomeIntro<Content: View>: View {
        let model: OnboardingModel
        let content: (Bool) -> Content

        init(model: OnboardingModel, @ViewBuilder content: @escaping (Bool) -> Content) {
            self.model = model
            self.content = content
        }

        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        @State private var phase: IntroPhase = .hidden
        @State private var revealsCopy = false
        @State private var arc: CGFloat = 0
        @State private var bounds: CGSize = .zero
        @State private var slotCenterY: CGFloat = 0

        var body: some View {
            ZStack {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(width: settledMarkSize, height: settledMarkSize)
                        .onGeometryChange(for: CGFloat.self) {
                            $0.frame(in: .named(introSpace)).midY
                        } action: {
                            slotCenterY = $0
                        }
                        .padding(.bottom, 24)

                    content(revealsCopy)
                }

                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: markSize, height: markSize)
                    .position(x: bounds.width / 2, y: markCenterY)
                    .offset(y: rise + arc)
                    .blur(radius: phase == .hidden ? 10 : 0)
                    .opacity(isPlaced ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .coordinateSpace(.named(introSpace))
            .onGeometryChange(for: CGSize.self) {
                $0.size
            } action: {
                bounds = $0
            }
            .task { await play() }
        }

        private var markSize: CGFloat {
            phase == .settled ? settledMarkSize : heroMarkSize
        }

        private var markCenterY: CGFloat {
            phase == .settled ? slotCenterY : bounds.height / 2
        }

        private var isPlaced: Bool {
            phase != .hidden && bounds != .zero && slotCenterY != 0
        }

        private var rise: CGFloat {
            phase == .hidden ? 360 : 0
        }

        private func play() async {
            guard !model.hasPlayedIntro, !reduceMotion else {
                phase = .settled
                revealsCopy = true
                return
            }
            model.markIntroPlayed()

            try? await Task.sleep(for: .milliseconds(700))
            withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 1.7)) {
                phase = .hero
            }

            try? await Task.sleep(for: .milliseconds(1600))
            withAnimation(.timingCurve(0.32, 1, 0.4, 1, duration: 0.72)) {
                phase = .settled
            }
            withAnimation(.easeOut(duration: 0.2)) {
                arc = -40
            }

            try? await Task.sleep(for: .milliseconds(200))
            withAnimation(.easeInOut(duration: 0.52)) {
                arc = 0
            }

            try? await Task.sleep(for: .milliseconds(120))
            revealsCopy = true
        }
    }
}

extension View {
    func introReveal(_ revealed: Bool, delay: Double) -> some View {
        modifier(IntroReveal(revealed: revealed, delay: delay))
    }
}

private struct IntroReveal: ViewModifier {
    let revealed: Bool
    let delay: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(revealed ? 1 : 0)
            .blur(radius: blur)
            .offset(y: offset)
            .animation(animation, value: revealed)
    }

    private var offset: CGFloat {
        guard !revealed, !reduceMotion else { return 0 }
        return 24
    }

    private var blur: CGFloat {
        guard !revealed, !reduceMotion else { return 0 }
        return 8
    }

    private var animation: Animation {
        guard !reduceMotion else { return .easeOut(duration: 0.2) }
        return .easeOut(duration: 0.35).delay(delay)
    }
}
