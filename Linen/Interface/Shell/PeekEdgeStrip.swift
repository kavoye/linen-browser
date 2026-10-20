// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

enum PeekEdge {
    static let width: CGFloat = 10
    static let dwell: Duration = .milliseconds(75)

    static func isHeld(pointer: CGPoint?, frame: CGRect) -> Bool {
        guard let pointer, !frame.isEmpty else { return false }
        return frame.contains(pointer)
    }
}

struct PeekEdgeStrip: View {
    let coordinator: AppCoordinator
    let onPeek: () -> Void

    @State private var frame: CGRect = .zero
    @State private var dwell: Task<Void, Never>?

    var body: some View {
        Color.clear
            .frame(width: PeekEdge.width)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                frame = $0
            }
            .onHover { inside in
                dwell?.cancel()
                guard inside else { return }
                dwell = Task {
                    try? await Task.sleep(for: PeekEdge.dwell)
                    guard !Task.isCancelled,
                          PeekEdge.isHeld(pointer: coordinator.pointerInShell, frame: frame) else { return }
                    onPeek()
                }
            }
            .onDisappear { dwell?.cancel() }
    }
}
