// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct LinkPreview: View {
    let address: String?
    var delay: Duration = .milliseconds(400)
    var obeysSetting = true

    @State private var shown: String?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let shown, !obeysSetting || BrowserSettings.shared.showsLinkPreview {
                Text(verbatim: shown)
                    .font(Theme.Font.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .controlGlassSurface(in: Capsule())
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: 640, alignment: .leading)
        .allowsHitTesting(false)
        .task(id: address) {
            guard let address else {
                shown = nil
                return
            }
            if shown == nil, delay > .zero {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
            }
            shown = address
        }
    }
}
