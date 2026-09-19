// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct VoiceConversationBackdrop: View {
    let session: OpenAIRealtimeConversation?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let assistant = session?.phase == .speaking || session?.phase == .thinking || session?.phase == .working
        let level = session?.isMicrophoneMuted == true ? 0 : session?.inputLevel ?? 0
        let color = assistant ? Color(red: 0.62, green: 0.25, blue: 0.88) : Color(red: 0.04, green: 0.72, blue: 0.73)
        ZStack {
            Theme.windowBackground.opacity(reduceTransparency ? 1 : 0.96)
            color.opacity(scheme == .dark ? 0.16 : 0.08)
            RadialGradient(colors: [color.opacity(0.30 + level * 0.20), .clear], center: .init(x: 0.5, y: 0.22), startRadius: 10, endRadius: 460)
            LinearGradient(colors: [.clear, Theme.windowBackground.opacity(0.65)], startPoint: .top, endPoint: .bottom)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: assistant)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: level)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct ConversationActivityIndicator: View {
    let session: OpenAIRealtimeConversation
    var size: CGFloat = 184
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let assistant = session.phase == .speaking || session.phase == .thinking || session.phase == .working
        let energy = session.isMicrophoneMuted ? 0 : (session.phase == .speaking ? 0.65 : session.inputLevel)
        VoiceOrbRenderer(energy: energy, assistant: assistant ? 1 : 0, active: session.isActive, reduceMotion: reduceMotion)
            .frame(width: size, height: size)
            .opacity(session.isMicrophoneMuted || !session.isActive ? 0.45 : 1)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.65), value: assistant)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.45), value: energy)
            .accessibilityLabel(session.phase == .speaking ? "Assistant speaking" : "Microphone input level")
            .accessibilityValue(Text("\(Int(session.inputLevel * 100)) percent"))
    }
}

private struct VoiceOrbRenderer: View, Animatable {
    var energy: Double
    var assistant: Double
    let active: Bool
    let reduceMotion: Bool
    @State private var epoch = Date()

    var animatableData: AnimatablePair<Double, Double> {
        get { .init(energy, assistant) }
        set { energy = newValue.first; assistant = newValue.second }
    }

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || !active)) { context in
                Rectangle().fill(ShaderLibrary.linenVoiceOrb(
                    .float2(geometry.size), .float(reduceMotion ? 0 : context.date.timeIntervalSince(epoch)),
                    .float(energy), .float(assistant)
                ))
            }
        }
    }
}
