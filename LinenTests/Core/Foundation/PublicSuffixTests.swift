// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Testing

@testable import Linen

struct PublicSuffixTests {
    @Test(arguments: [
        ("maps.google.com", "google.com"),
        ("google.com", "google.com"),
        ("www.bbc.co.uk", "bbc.co.uk"),
        ("alice.github.io", "alice.github.io"),
        ("docs.alice.github.io", "alice.github.io"),
        ("a.b.example.ck", "b.example.ck"),
        ("www.ck", "www.ck"),
        ("city.kobe.jp", "city.kobe.jp"),
        ("shop.xn--p1ai", "shop.xn--p1ai"),
        ("Maps.Google.COM.", "google.com"),
    ])
    func registrableDomain(host: String, expected: String) {
        #expect(PublicSuffix.registrableDomain(of: host) == expected)
    }

    @Test(arguments: ["co.uk", "github.io", "com", "localhost", "127.0.0.1", "::1", "", "unknownsuffix"])
    func hostsWithoutARegistrableDomain(host: String) {
        #expect(PublicSuffix.registrableDomain(of: host) == nil)
    }
}
