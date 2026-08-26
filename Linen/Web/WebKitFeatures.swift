// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WebKit

nonisolated struct WebKitFeature: Identifiable, Sendable {
    let key: String
    let name: String
    let details: String
    let isOnByDefault: Bool

    var id: String {
        key
    }
}

@objc private protocol WebKitFeatureToggling {
    @objc(_setEnabled:forFeature:)
    func setEnabled(_ enabled: Bool, for feature: AnyObject)
}

@MainActor
enum WebKitFeatures {
    private static let store = "webkit.experimentalFeatures"
    private static let listing = NSSelectorFromString("_experimentalFeatures")
    private static let toggling = NSSelectorFromString("_setEnabled:forFeature:")

    static var defaults: UserDefaults = .standard

    private static let known: [String: AnyObject] = read()

    static let all: [WebKitFeature] = known.values
        .compactMap { described($0) }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    static var isAvailable: Bool {
        !all.isEmpty
    }

    static var overrides: [String: Bool] {
        get { defaults.dictionary(forKey: store) as? [String: Bool] ?? [:] }
        set {
            if newValue.isEmpty {
                defaults.removeObject(forKey: store)
            } else {
                defaults.set(newValue, forKey: store)
            }
        }
    }

    static var changedCount: Int {
        overrides.count
    }

    static func isOn(_ feature: WebKitFeature) -> Bool {
        overrides[feature.key] ?? feature.isOnByDefault
    }

    static func setOn(_ isOn: Bool, _ feature: WebKitFeature) {
        var kept = overrides
        if isOn == feature.isOnByDefault {
            kept.removeValue(forKey: feature.key)
        } else {
            kept[feature.key] = isOn
        }
        overrides = kept
    }

    static func resetAll() {
        overrides = [:]
    }

    static func apply(to preferences: WKPreferences) {
        let wanted = overrides
        guard !wanted.isEmpty, preferences.responds(to: toggling) else { return }
        let switcher = unsafeBitCast(preferences, to: WebKitFeatureToggling.self)
        for (key, isOn) in wanted {
            guard let feature = known[key] else { continue }
            switcher.setEnabled(isOn, for: feature)
        }
    }

    private static func read() -> [String: AnyObject] {
        guard WKPreferences.responds(to: listing),
              let listed = WKPreferences.perform(listing)?.takeUnretainedValue() as? [AnyObject]
        else { return [:] }

        var found: [String: AnyObject] = [:]
        for feature in listed {
            guard let key = feature.value(forKey: "key") as? String else { continue }
            found[key] = feature
        }
        return found
    }

    private static func described(_ feature: AnyObject) -> WebKitFeature? {
        guard let key = feature.value(forKey: "key") as? String,
              feature.value(forKey: "hidden") as? Bool != true
        else { return nil }

        let name = feature.value(forKey: "name") as? String
        let details = feature.value(forKey: "details") as? String
        return WebKitFeature(
            key: key,
            name: name?.isEmpty == false ? name! : key,
            details: details ?? "",
            isOnByDefault: feature.value(forKey: "defaultValue") as? Bool ?? false
        )
    }
}
