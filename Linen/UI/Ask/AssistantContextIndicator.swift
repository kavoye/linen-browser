// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct AssistantContextIndicator: View {
    let tokens: Int
    let window: ContextWindow.Resolution
    let providerNotice: String?
    let canCompact: Bool
    let isCompacting: Bool
    let compactionMessage: LocalizedStringResource?
    let onCompact: () -> Void

    @State private var isPresenting = false
    @State private var isHovering = false
    @State private var isHoveringPopover = false
    @State private var isPinned = false

    private var hasKnownLimit: Bool {
        window.source != .fallback
    }

    private var fraction: Double {
        hasKnownLimit ? min(1, max(0, Double(tokens) / Double(max(1, window.tokens)))) : 0
    }

    private var percent: Int {
        Int((fraction * 100).rounded())
    }

    var body: some View {
        Button {
            isPinned = true
            isPresenting = true
        } label: {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.13), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(fraction >= 0.9 ? Color.orange : Color.secondary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 13, height: 13)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Context window")
        .accessibilityValue(hasKnownLimit
            ? Text("Estimated: \(percent)% used, \(100 - percent)% left")
            : Text("Estimated: \(tokens) tokens. Model limit unavailable."))
        .onHover { isHovering = $0 }
        .task(id: isHovering) {
            guard isHovering else { return }
            do {
                try await Task.sleep(for: .milliseconds(500))
                try Task.checkCancellation()
                isPresenting = true
            } catch {   }
        }
        .task(id: isHovering || isHoveringPopover || isPinned) {
            guard !isHovering, !isHoveringPopover, !isPinned else { return }
            do {
                try await Task.sleep(for: .milliseconds(250))
                try Task.checkCancellation()
                isPresenting = false
            } catch {   }
        }
        .onChange(of: isPresenting) { _, showing in
            if !showing {
                isPinned = false
                isHoveringPopover = false
            }
        }
        .popover(isPresented: $isPresenting, arrowEdge: .bottom) {
            VStack(spacing: 5) {
                Text("Context window")
                    .foregroundStyle(.secondary)
                if let providerNotice {
                    Text(verbatim: providerNotice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if hasKnownLimit {
                    Text("\(percent)% used (\(100 - percent)% left)")
                        .fontWeight(.medium)
                    Text("\(compact(tokens)) / \(compact(window.tokens)) tokens")
                        .monospacedDigit()
                } else {
                    Text("\(compact(tokens)) tokens used")
                        .monospacedDigit()
                    Text("Model limit unavailable")
                        .foregroundStyle(.secondary)
                }
                Text(window.source == .configured ? "Estimated usage · custom limit" : "Estimated usage")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Divider().padding(.vertical, 5)
                Button {
                    isPinned = true
                    onCompact()
                } label: {
                    if isCompacting {
                        HStack(spacing: 6) {
                            Spinner(size: 11)
                            Text("Compacting…")
                        }
                    } else {
                        Text("Compact")
                    }
                }
                .disabled(!canCompact || isCompacting)
                .help("Summarize older context now. Context also compacts automatically when needed.")
                if let compactionMessage {
                    Text(compactionMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .fixedSize()
            .onHover { isHoveringPopover = $0 }
        }
    }

    private func compact(_ value: Int) -> String {
        max(0, value).formatted(.number.notation(.compactName).precision(.fractionLength(0...(value >= 1_000_000 ? 2 : 1))))
    }
}
