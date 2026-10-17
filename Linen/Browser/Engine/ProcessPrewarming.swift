// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import WebKit

/// Keeps one web content process running ahead of time. A new tab, or a tab
/// coming back from sleep, then skips the process launch and loads about
/// 35 ms sooner.
///
/// WebKit reads this setting only when it creates a process pool, so the
/// configuration template gets its own pool. The deprecation notice on the
/// pool type says extra pools have no effect, but this setting still works.
/// The code looks the type up by name to keep the build free of warnings.
/// If the setting is missing, the template keeps the default pool.
enum ProcessPrewarming {
    private static let initializer = NSSelectorFromString("_initWithConfiguration:")

    static func install(in configuration: WKWebViewConfiguration) {
        guard let poolType = NSClassFromString("WKProcessPool") as? NSObject.Type,
              let settingsType = NSClassFromString("_WKProcessPoolConfiguration") as? NSObject.Type,
              poolType.instancesRespond(to: initializer)
        else { return }
        let settings = settingsType.init()
        guard settings.responds(to: NSSelectorFromString("setPrewarmsProcessesAutomatically:")) else { return }
        settings.setValue(true, forKey: "prewarmsProcessesAutomatically")
        guard let allocated = poolType.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue(),
              let pool = allocated.perform(initializer, with: settings)?.takeRetainedValue()
        else { return }
        configuration.setValue(pool, forKey: "processPool")
    }
}
