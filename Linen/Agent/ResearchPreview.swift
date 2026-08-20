// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Observation
import WebKit

@MainActor
@Observable
final class ResearchPreview {
    private(set) var snapshot: NSImage?
    private(set) var host: String?
    private(set) var isLive = false
    private(set) var spaceID: UUID?

    @ObservationIgnored var source: (() -> WKWebView?)?

    @ObservationIgnored private var ticker: Task<Void, Never>?

    private static let interval: Duration = .milliseconds(600)

    func begin(inSpace spaceID: UUID? = nil) {
        self.spaceID = spaceID
        snapshot = nil
        host = nil
        isLive = true
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    func end() {
        ticker?.cancel()
        ticker = nil
        isLive = false
    }

    private func tick() async {
        guard let webView = source?(), webView.url != nil else { return }
        guard let image = await Self.capture(webView) else { return }
        snapshot = image
        host = webView.url?.host()
    }

    static func capture(_ webView: WKWebView, width: CGFloat = 480) async -> NSImage? {
        let configuration = WKSnapshotConfiguration()
        configuration.snapshotWidth = NSNumber(value: Double(width))
        return try? await webView.takeSnapshot(configuration: configuration)
    }
}
