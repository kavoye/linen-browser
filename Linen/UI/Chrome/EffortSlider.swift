// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct EffortSlider: View {
    let efforts: [LLMSettings.ReasoningEffort]
    let effort: LLMSettings.ReasoningEffort
    let onSelect: (LLMSettings.ReasoningEffort) -> Void

    private enum Metrics {
        static let knob: CGFloat = 15
        static let track: CGFloat = 4
        static let tick: CGFloat = 5
        static let lane: CGFloat = 18
        static let captionIndent: CGFloat = 53
    }

    private var stops: [LLMSettings.ReasoningEffort] {
        efforts.isEmpty ? LLMSettings.ReasoningEffort.allCases : efforts
    }

    private var index: Int {
        stops.firstIndex(of: effort) ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if stops.count > 1 {
                track
            }

            caption
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Thinking"))
        .accessibilityValue(Text(effort.label))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                move(by: 1)
            case .decrement:
                move(by: -1)
            @unknown default:
                break
            }
        }
    }

    private func move(by step: Int) {
        let next = min(max(index + step, 0), stops.count - 1)
        guard stops[next] != effort else { return }
        onSelect(stops[next])
    }

    private var track: some View {
        GeometryReader { proxy in
            let inset = Metrics.knob / 2
            let span = max(1, proxy.size.width - Metrics.knob)
            let step = span / CGFloat(max(1, stops.count - 1))
            let knobX = inset + step * CGFloat(index)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.Wash.strong)
                    .frame(height: Metrics.track)

                Capsule()
                    .fill(Theme.accent)
                    .frame(width: knobX, height: Metrics.track)

                ForEach(stops.indices, id: \.self) { stop in
                    Circle()
                        .fill(stop <= index ? Color.white.opacity(0.7) : Theme.Wash.emphasis)
                        .frame(width: Metrics.tick, height: Metrics.tick)
                        .position(x: inset + step * CGFloat(stop), y: Metrics.lane / 2)
                }

                Circle()
                    .fill(Theme.controlSurface)
                    .overlay(Circle().strokeBorder(Theme.Wash.strong, lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.18), radius: 1.5, y: 0.5)
                    .frame(width: Metrics.knob, height: Metrics.knob)
                    .position(x: knobX, y: Metrics.lane / 2)
            }
            .frame(height: Metrics.lane)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        pick(at: value.location.x, inset: inset, step: step)
                    }
            )
            .animation(Theme.Motion.quick, value: index)
        }
        .frame(height: Metrics.lane)
    }

    private var caption: some View {
        Text(effort.caption)
            .font(Theme.Font.caption)
            .foregroundStyle(.tertiary)
            .lineLimit(2, reservesSpace: true)
            .padding(.leading, Metrics.captionIndent)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pick(at x: CGFloat, inset: CGFloat, step: CGFloat) {
        let nearest = Int(((x - inset) / step).rounded())
        let clamped = min(max(nearest, 0), stops.count - 1)
        guard stops[clamped] != effort else { return }
        onSelect(stops[clamped])
    }
}
