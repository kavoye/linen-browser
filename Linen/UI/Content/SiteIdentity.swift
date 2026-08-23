// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

enum SiteName {
    private static let genericSuffixes: Set<String> = ["co", "com", "org", "net", "ac", "gov", "edu"]

    static func name(forHost host: String) -> String {
        var parts = host.lowercased().split(separator: ".").map(String.init)
        if parts.first == "www" {
            parts.removeFirst()
        }
        guard parts.count > 1 else { return parts.first ?? host }

        var suffixLength = 1
        if parts.count > 2,
           parts[parts.count - 1].count == 2,
           genericSuffixes.contains(parts[parts.count - 2]) {
            suffixLength = 2
        }
        return parts[max(0, parts.count - suffixLength - 1)]
    }

    static func title(forHost host: String) -> String {
        let name = name(forHost: host)
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}

struct RemoteSiteBadge: View {
    let host: String
    let size: CGFloat

    @State private var icon: NSImage?

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: size / 5, style: .continuous))
            } else {
                Image(systemName: "globe")
                    .font(.system(size: size * 0.75))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: size, height: size)
        .task(id: host) {
            if let cached = FaviconLoader.shared.cached(for: host) {
                icon = cached
            } else {
                icon = await FaviconLoader.shared.load(forHost: host)
            }
        }
    }
}
