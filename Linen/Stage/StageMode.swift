// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

#if DEBUG
import Foundation
import WebKit

nonisolated enum StageMode {
    static let isActive: Bool = {
        guard let value = ProcessInfo.processInfo.environment["LINEN_STAGE"] else { return false }
        return !value.isEmpty && value != "0"
    }()

    static let home: URL? = {
        guard isActive else { return nil }
        let path = ProcessInfo.processInfo.environment["LINEN_STAGE_HOME"]
            ?? NSTemporaryDirectory() + "linen-stage/home"
        return URL(filePath: path, directoryHint: .isDirectory)
    }()

    static let dataStoreID = UUID(uuidString: "57A6E000-0000-4000-A000-000000000001")!

    static var defaults: UserDefaults {
        guard isActive, let suite = UserDefaults(suiteName: "app.linen.stage") else {
            return .standard
        }
        return suite
    }

    @MainActor
    static func websiteDataStore() -> WKWebsiteDataStore {
        WKWebsiteDataStore(forIdentifier: dataStoreID)
    }
}
#endif
