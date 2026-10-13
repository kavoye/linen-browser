// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WebKit

extension WKWebView {
    func finishPendingPageMessages() async throws {
        _ = try await callAsyncJavaScript(
            """
            await new Promise(resolve => {
                const done = event => {
                    if (event.source !== window || event.data !== marker) return;
                    window.removeEventListener('message', done);
                    resolve();
                };
                window.addEventListener('message', done);
                window.postMessage(marker, '*');
            });
            return true;
            """,
            arguments: ["marker": UUID().uuidString],
            in: nil,
            contentWorld: .page
        )
    }
}
