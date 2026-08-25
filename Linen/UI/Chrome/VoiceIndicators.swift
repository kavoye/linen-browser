// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct MicButton: View {
    let coordinator: AppCoordinator
    var orbSize: CGFloat = 14

    @State private var hovering = false

    private var isAgentTurn: Bool {
        VoiceGlyph.showsAgentTurn(
            state: coordinator.state,
            isSpeakingReply: coordinator.isSpeakingInChrome
        )
    }

    private var help: LocalizedStringResource {
        if isAgentTurn {
            return "Stop"
        }
        return coordinator.state == .listening ? "Stop and Run" : "Click to Talk"
    }

    var body: some View {
        Button {
            if isAgentTurn {
                coordinator.stopAgent()
            } else {
                coordinator.toggleMicListening()
            }
        } label: {
            VoiceGlyph(
                state: coordinator.state,
                isSpeakingReply: coordinator.isSpeakingInChrome,
                isHighlighted: hovering,
                orbSize: orbSize
            )
            .frame(width: max(20, orbSize + 2), height: max(20, orbSize + 2))
            .hoverBackground(isActive: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.quick, value: hovering)
        .help(Text(help))
    }
}

struct FluidWaves: View {
    enum Motion: Equatable {
        case calm
        case active
        case thinking

        var speedMultiplier: Double {
            switch self {
            case .calm:
                0.35
            case .active:
                1
            case .thinking:
                2.15
            }
        }
    }

    let color: Color
    let motion: Motion

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                for layer in 0..<3 {
                    let layerFraction = Double(layer)
                    let amplitude = size.height * 0.09
                    let wavelength = size.width / (1.1 + 0.45 * layerFraction)
                    let speed = (42.0 + 16.0 * layerFraction) * motion.speedMultiplier
                    let phase = t * speed / wavelength * 2 * .pi
                    let baseline = size.height * (0.16 + 0.3 * layerFraction)

                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: size.height))
                    var x: Double = 0
                    while x <= size.width {
                        let y = baseline + sin((x / wavelength) * 2 * .pi - phase) * amplitude
                        path.addLine(to: CGPoint(x: x, y: y))
                        x += 3
                    }
                    path.addLine(to: CGPoint(x: size.width, y: size.height))
                    path.closeSubpath()

                    context.fill(path, with: .color(color.opacity(0.07 - 0.014 * layerFraction)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct VoiceGlyph: View {
    let state: PipelineState
    let isSpeakingReply: Bool
    var isHighlighted = false
    var orbSize: CGFloat = 14
    @State private var pulsing = false

    var body: some View {
        glyph
            .frame(width: max(14, orbSize))
            .scaleEffect(pulsing ? beat : 1.0)
            .onChange(of: isBeating) { _, beating in
                if beating {
                    withAnimation(.easeInOut(duration: pulseDuration).repeatForever(autoreverses: true)) {
                        pulsing = true
                    }
                } else {
                    withAnimation(.default) { pulsing = false }
                }
            }
    }

    private var isBeating: Bool {
        guard !showsStop else { return false }
        return state == .listening || state == .executing || isSpeakingReply
    }

    private var showsStop: Bool {
        isAgentTurn || (state == .listening && isHighlighted)
    }

    private var beat: CGFloat {
        state == .listening ? 1.25 : 1.12
    }
    private var pulseDuration: Double {
        state == .listening ? 0.5 : 0.75
    }

    @ViewBuilder
    private var glyph: some View {
        if isAgentTurn, !isHighlighted {
            ComposingOrb(size: orbSize)
        } else {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .contentTransition(.identity)
        }
    }

    private var symbol: String {
        if showsStop {
            return "stop.fill"
        }
        return state == .listening ? "mic.fill" : "mic"
    }

    static func showsAgentTurn(state: PipelineState, isSpeakingReply: Bool) -> Bool {
        state == .executing || (state == .idle && isSpeakingReply)
    }

    private var isAgentTurn: Bool {
        Self.showsAgentTurn(state: state, isSpeakingReply: isSpeakingReply)
    }

    private var color: Color {
        switch state {
        case .listening:
            .red
        case .executing:
            Theme.accent
        case .idle:
            isHighlighted ? .primary : .secondary
        }
    }
}
