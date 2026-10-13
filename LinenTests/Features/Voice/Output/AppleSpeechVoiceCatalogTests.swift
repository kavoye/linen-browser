// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Testing

@testable import Linen

@MainActor
struct AppleSpeechVoiceCatalogTests {
    @Test func readingAnUnpreparedCatalogDoesNotEnumerateVoices() {
        var enumerations = 0
        let catalog = AppleSpeechVoiceCatalog {
            enumerations += 1
            return []
        }

        #expect(catalog.voice == nil)
        #expect(enumerations == 0)
    }

    @Test func anEmptyCatalogIsCachedAcrossRepeatedPreparationAndTaskReads() async {
        var enumerations = 0
        let catalog = AppleSpeechVoiceCatalog {
            enumerations += 1
            return []
        }
        catalog.prepare()

        await Task { @MainActor in
            for _ in 0..<10 {
                catalog.prepare()
                #expect(catalog.voice == nil)
            }
        }.value

        #expect(enumerations == 1)
    }
}
