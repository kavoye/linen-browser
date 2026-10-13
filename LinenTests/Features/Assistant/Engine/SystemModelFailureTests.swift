// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import FoundationModels
import Testing

@testable import Linen

/// The on-device model raises FoundationModels' own `GenerationError`, which
/// is a different type from the one `AnyLanguageModel` declares. Matching only
/// the package's type let every 4k overflow reach the user as a raw
/// "Provided N tokens, but the maximum allowed is 4,096" failure.
struct SystemModelFailureTests {
    static func contextOverflow() -> any Error {
        LanguageModelSession.GenerationError.exceededContextWindowSize(
            .init(debugDescription: "transcript too long for the on-device window")
        )
    }

    @Test func theOnDeviceOverflowIsRecognised() {
        #expect(SystemModelFailure.isContextOverflow(Self.contextOverflow()))
    }

    @Test func anotherGenerationFailureIsNotAnOverflow() {
        let refusal = LanguageModelSession.GenerationError.guardrailViolation(
            .init(debugDescription: "unsafe")
        )
        #expect(!SystemModelFailure.isContextOverflow(refusal))
    }

    @Test func anUnrelatedFailureIsNotAnOverflow() {
        #expect(!SystemModelFailure.isContextOverflow(URLError(.timedOut)))
    }
}
