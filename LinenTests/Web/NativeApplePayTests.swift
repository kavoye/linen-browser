// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

@MainActor
struct NativeApplePayTests {
    @Test func paymentPreferencesPersistAndCardFillingFollowsTheProfile() throws {
        let prefix = "PaymentPreferencesTests.\(UUID().uuidString)"
        let names = [prefix + ".app", prefix + ".work", prefix + ".personal"]
        defer { names.forEach { UserDefaults.standard.removePersistentDomain(forName: $0) } }
        let app = try #require(UserDefaults(suiteName: names[0]))
        let work = try #require(UserDefaults(suiteName: names[1]))
        let personal = try #require(UserDefaults(suiteName: names[2]))
        let settings = BrowserSettings(defaults: app, sessionDefaults: work)
        #expect(settings.fillsPaymentCards)
        settings.fillsPaymentCards = false
        let restored = BrowserSettings(defaults: app, sessionDefaults: work)
        #expect(!restored.fillsPaymentCards)
        settings.useSessionDefaults(personal)
        #expect(settings.fillsPaymentCards)
        settings.useSessionDefaults(work)
        #expect(!settings.fillsPaymentCards)
    }

    @Test(.boundedWebViews) func unsupportedNativeSessionIsNotAdvertisedEvenAfterOldOptIn() async throws {
        for enabled in [false, true, false] {
            let configuration = WebViewPool.makeConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            if configuration.preferences.responds(to: NSSelectorFromString("_setApplePayEnabled:")) {
                configuration.preferences.setValue(enabled, forKey: "applePayEnabled")
            }
            NativeApplePay.apply(to: configuration.preferences)
            let view = WKWebView(frame: .zero, configuration: configuration)
            view.loadHTMLString("<!doctype html><p>Payment capability test</p>", baseURL: URL(string: "https://checkout.example/"))
            #expect(await PageSettle.untilIdle(view, timeout: .seconds(20)))
            let type = try await view.evaluateJavaScript("typeof ApplePaySession") as? String
            #expect(type == "undefined")
        }
    }
}
