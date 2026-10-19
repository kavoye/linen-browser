// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

struct MCPClientIdentityTests {
    @Test(arguments: [
        ("Developer ID Application: Anthropic PBC (Q6L2SF6YDW)", "Anthropic PBC"),
        ("Apple Development: Jane Doe (ABCDE12345)", "Jane Doe"),
        ("Software Signing", "Software Signing"),
    ])
    func developerNameComesFromTheCertificate(summary: String, expected: String) {
        #expect(MCPClientIdentity.organization(fromSummary: summary) == expected)
    }

    @Test func appExecutablesUseTheirBundleName() {
        #expect(MCPClientIdentity.displayName(forExecutable: "/System/Applications/Calculator.app/Contents/MacOS/Calculator") == "Calculator")
        #expect(MCPClientIdentity.displayName(forExecutable: "/usr/local/bin/codex") == "codex")
    }
}
