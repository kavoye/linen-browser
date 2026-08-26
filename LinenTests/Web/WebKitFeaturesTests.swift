// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

@MainActor
struct WebKitFeaturesTests {
    private func withOwnDefaults(_ body: () throws -> Void) rethrows {
        let name = "webkit.features.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        let previous = WebKitFeatures.defaults
        WebKitFeatures.defaults = suite
        defer {
            WebKitFeatures.defaults = previous
            suite.removePersistentDomain(forName: name)
        }
        try body()
    }

    @Test func webKitStillOffersItsExperiments() {
        #expect(WebKitFeatures.isAvailable, "WebKit no longer lists its experimental features")
        #expect(WebKitFeatures.all.count > 50)
        #expect(WebKitFeatures.all.allSatisfy { !$0.key.isEmpty && !$0.name.isEmpty })
    }

    @Test func aFlagIsRememberedOnlyWhileItDiffers() throws {
        try withOwnDefaults {
            let feature = try #require(WebKitFeatures.all.first)
            #expect(WebKitFeatures.isOn(feature) == feature.isOnByDefault)

            WebKitFeatures.setOn(!feature.isOnByDefault, feature)
            #expect(WebKitFeatures.isOn(feature) == !feature.isOnByDefault)
            #expect(WebKitFeatures.changedCount == 1)

            WebKitFeatures.setOn(feature.isOnByDefault, feature)
            #expect(WebKitFeatures.changedCount == 0, "a flag back at its default is not an override")
        }
    }

    @Test func resettingForgetsEveryFlag() {
        withOwnDefaults {
            for feature in WebKitFeatures.all.prefix(3) {
                WebKitFeatures.setOn(!feature.isOnByDefault, feature)
            }
            #expect(WebKitFeatures.changedCount == 3)

            WebKitFeatures.resetAll()
            #expect(WebKitFeatures.changedCount == 0)
        }
    }
}
