// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct Spinner: View {
    var size: CGFloat = 13

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var turning = false
    @State private var breathing = false

    private var lineWidth: CGFloat {
        max(1.2, size * 0.12)
    }

    private static let arc: CGFloat = 0.3

    private static let period: Double = 1.15

    var body: some View {
        ZStack {
            Circle()
                .stroke(style: StrokeStyle(lineWidth: lineWidth))
                .opacity(0.18)

            Circle()
                .trim(from: 0, to: Self.arc)
                .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(turning ? 360 : 0))
                .opacity(reduceMotion && !breathing ? 0.35 : 1)
        }
        .padding(lineWidth / 2)
        .frame(width: size, height: size)
        .onAppear(perform: start)
        .accessibilityHidden(true)
    }

    private func start() {
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                breathing = true
            }
        } else {
            withAnimation(.linear(duration: Self.period).repeatForever(autoreverses: false)) {
                turning = true
            }
        }
    }
}
