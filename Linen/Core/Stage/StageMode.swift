// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

#if DEBUG
import CryptoKit
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

    /// Names everything a stage home owns outside its directory, so two homes never share it.
    static func identity(for home: URL) -> String {
        SHA256.hash(data: Data(home.standardizedFileURL.path.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func defaultsSuiteName(for home: URL) -> String {
        "app.linen.stage.\(identity(for: home))"
    }

    static func defaults(for home: URL) -> UserDefaults {
        UserDefaults(suiteName: defaultsSuiteName(for: home))!
    }

    static func dataStoreID(for home: URL) -> UUID {
        let digits = Array(identity(for: home))
        let groups = [0..<8, 8..<12, 12..<16, 16..<20, 20..<32].map { String(digits[$0]) }
        return UUID(uuidString: groups.joined(separator: "-"))!
    }

    static var defaults: UserDefaults {
        guard let home else { return .standard }
        return defaults(for: home)
    }

    @MainActor
    static func websiteDataStore(for home: URL) -> WKWebsiteDataStore {
        WKWebsiteDataStore(forIdentifier: dataStoreID(for: home))
    }
}
#endif
