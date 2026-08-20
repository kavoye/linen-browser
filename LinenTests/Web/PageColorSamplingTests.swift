// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Testing

@testable import Linen

/// `_sampledPageTopColor` is private API: no deprecation period, no release
/// note, no compile error when WebKit renames it - just a toolbar that
/// quietly stops matching pages. These tests are the alarm that replaces
/// the contract.
@MainActor
struct PageColorSamplingTests {
    /// The `responds` checks that gate every use. If this fails on a new
    /// macOS, the toolbar has fallen back to declared colours and
    /// `PageColorSampling` needs updating for whatever WebKit renamed.
    @Test func webKitStillExposesTheSampler() {
        #expect(PageColorSampling.isSupported)
    }
}
