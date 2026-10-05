// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import Synchronization
import Testing
import WebKit

@testable import Linen

@MainActor
@Suite(.boundedWebViews)
struct WebViewGeometryTests {
    @Test(arguments: [false, true])
    func webSurfacesNeverReturnNegativeDimensions(_ isMedia: Bool) throws {
        let webView = WKWebView(frame: .zero, configuration: WebViewPool.makeConfiguration())
        let surface = isMedia
            ? AnyView(MediaCropSurface(webView: webView, crop: CGRect(x: 0, y: 0, width: 640, height: 360)))
            : AnyView(WebViewRepresentable(webView: webView))

        for (proposal, expected) in [
            (CGSize(width: -24, height: -48), CGSize.zero),
            (CGSize(width: -24, height: 180), CGSize(width: 0, height: 180)),
            (CGSize(width: 320, height: -48), CGSize(width: 320, height: 0)),
            (CGSize.zero, CGSize.zero),
            (CGSize(width: 320, height: 180), CGSize(width: 320, height: 180)),
        ] {
            let measurement = WebSurfaceMeasurement()
            let host = NSHostingView(rootView: WebSurfaceProbe(
                proposal: ProposedViewSize(proposal), measurement: measurement
            ) { surface })
            _ = host.fittingSize
            let size = try #require(measurement.size)
            #expect(size == expected)
        }

        for proposal in [
            ProposedViewSize.unspecified,
            ProposedViewSize(width: nil, height: 180),
            ProposedViewSize(width: 320, height: nil),
        ] {
            let measurement = WebSurfaceMeasurement()
            let host = NSHostingView(rootView: WebSurfaceProbe(proposal: proposal, measurement: measurement) { surface })
            _ = host.fittingSize
            let size = try #require(measurement.size)
            #expect(size.width.isFinite && size.width >= 0)
            #expect(size.height.isFinite && size.height >= 0)
        }
    }
}

private nonisolated final class WebSurfaceMeasurement: Sendable {
    private let storage = Mutex<CGSize?>(nil)

    var size: CGSize? {
        get { storage.withLock { $0 } }
        set { storage.withLock { $0 = newValue } }
    }
}

private struct WebSurfaceProbe: Layout {
    let proposal: ProposedViewSize
    let measurement: WebSurfaceMeasurement

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        measurement.size = subviews.first?.sizeThatFits(self.proposal)
        return CGSize(width: 320, height: 180)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: self.proposal)
    }
}
