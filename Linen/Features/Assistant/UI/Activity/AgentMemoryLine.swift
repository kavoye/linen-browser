// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct AgentMemoryLine: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let updates: [AgentMemoryUpdate]
    let memory: AssistantMemory

    @State private var hoveringLine = false
    @State private var showsCard = false
    @State private var shown: Bool

    private static var drawn: Set<UUID> = []

    init(updates: [AgentMemoryUpdate], memory: AssistantMemory) {
        self.updates = updates
        self.memory = memory
        let fresh = updates.first.flatMap { update in memory.facts.first { $0.id == update.factID } }
            .map { Date().timeIntervalSince($0.savedAt) < 60 } ?? false
        _shown = State(initialValue: !fresh || updates.first.map { Self.drawn.contains($0.factID) } ?? true)
    }

    private var isCrossedOut: Bool {
        !updates.contains { memory.status(of: $0) == .kept }
    }

    private var summary: String {
        guard updates.count == 1, let update = updates.first else {
            return String(localized: "Remembered \(updates.count) things")
        }
        return String(localized: "Remembered \(update.subject): \(update.value)")
    }

    var body: some View {
        Button {
            showsCard.toggle()
        } label: {
            HStack(spacing: 6) {
                ZStack {
                    Image(systemName: "pencil.and.list.clipboard")
                        .hidden()
                    if shown {
                        Image(systemName: "pencil.and.list.clipboard")
                            .transition(.symbolEffect(.drawOn.byLayer))
                    }
                }
                .font(.system(size: 11))
                .frame(width: 14)
                .animation(reduceMotion ? nil : .default, value: shown)
                .opacity(isCrossedOut ? 0.5 : 1)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: isCrossedOut)
                Text(verbatim: summary)
                    .font(Theme.Font.caption)
                    .lineLimit(1)
                    .crossedOut(isCrossedOut)
            }
            .foregroundStyle(hoveringLine ? Color.primary : Theme.metaInk)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveringLine = $0 }
        .popover(isPresented: $showsCard, arrowEdge: .bottom) {
            MemoryUpdateCard(updates: updates, memory: memory)
        }
        .animation(Theme.Motion.quick, value: hoveringLine)
        .accessibilityHint(Text("Shows what was remembered"))
        .onAppear {
            guard !shown, let key = updates.first?.factID else { return }
            Self.drawn.insert(key)
            shown = true
        }
    }
}

private struct MemoryUpdateCard: View {
    let updates: [AgentMemoryUpdate]
    let memory: AssistantMemory

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(updates, id: \.factID) { update in
                let status = memory.status(of: update)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: update.subject.prefix(1).uppercased() + update.subject.dropFirst())
                            .font(Theme.Font.caption)
                            .foregroundStyle(.secondary)
                        Text(verbatim: update.value)
                            .font(Theme.Font.body)
                            .crossedOut(status != .kept)
                    }
                    Spacer(minLength: 16)
                    ZStack(alignment: .trailing) {
                        Button("Forget") { memory.forget(update.factID) }
                            .buttonStyle(AgentInlineButtonStyle())
                            .opacity(status == .kept ? 1 : 0)
                            .allowsHitTesting(status == .kept)
                        Button("Remember") { memory.restore(update) }
                            .buttonStyle(AgentInlineButtonStyle())
                            .opacity(status == .forgotten ? 1 : 0)
                            .allowsHitTesting(status == .forgotten)
                        Text("Changed")
                            .opacity(status == .changed ? 1 : 0)
                    }
                    .font(Theme.Font.caption)
                    .foregroundStyle(.tertiary)
                    .animation(Theme.Motion.quick, value: status)
                }
            }
        }
        .padding(12)
        .frame(minWidth: 220, alignment: .leading)
    }
}

private struct CrossedOut: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isActive ? 0.5 : 1)
            .overlay(alignment: .leading) {
                Rectangle()
                    .frame(height: 1)
                    .scaleEffect(x: isActive ? 1 : 0, anchor: .leading)
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: isActive)
    }
}

private extension View {
    func crossedOut(_ isActive: Bool) -> some View {
        modifier(CrossedOut(isActive: isActive))
    }
}
