// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WebKit

extension BrowserTab {
    func probeReader() {
        guard isFrontmost, isMaterialised, isShowingRealPage, !isShowingError else { return }
        Task { await reader.probe() }
    }

    func readerPageMoved(from previous: String) {
        guard Self.withoutFragment(urlString) != Self.withoutFragment(previous) else { return }
        reader.pageChanged()
        probeReader()
    }

    var translationSurface: WKWebView {
        guard reader.isActive, let view = reader.presentedView else { return webView }
        return view
    }

    func retranslateShownSurface() {
        guard translation.isActive, let target = translation.target else { return }
        Task { await translate(to: target, downloading: nil) }
    }

    nonisolated static func withoutFragment(_ address: String) -> Substring {
        address.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
    }
}
