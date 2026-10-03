// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import WebKit

@testable import Linen

/// Automation fixtures run without a foreground browser window. WebKit's
/// default inactive policy can suspend JavaScript and layout between calls,
/// consuming an action's deadline before it can observe a stable control or
/// receive native input. Exercise these fixtures as active pages instead.
@MainActor
func interactiveWebViewConfiguration() -> WKWebViewConfiguration {
    let configuration = WebViewPool.makeConfiguration()
    configuration.preferences.inactiveSchedulingPolicy = .none
    return configuration
}
