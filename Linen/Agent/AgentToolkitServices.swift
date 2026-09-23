// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WebKit

extension AgentToolkit {
    struct Services {
        var search: (String) async -> [SearchHit]
        var resolveVideo: (String) async -> ResolvedVideo
        var chooseFiles: ((WKOpenPanelParameters) async -> [URL]?)?

        static var live: Self {
            Self(
                search: { await SnippetFetcher.search(query: $0) },
                resolveVideo: { await YouTubeResolver().resolve(query: $0) }
            )
        }
    }
}
