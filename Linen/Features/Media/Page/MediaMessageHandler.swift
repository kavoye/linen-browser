// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import WebKit

final class MediaMessageHandler: NSObject, WKScriptMessageHandler {
    var onMessage: ((String, WKWebView?, Bool) -> Void)?

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        onMessage?(
            message.body as? String ?? "",
            message.webView,
            message.frameInfo.isMainFrame
        )
    }
}
