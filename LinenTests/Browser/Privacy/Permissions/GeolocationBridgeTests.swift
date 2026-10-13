// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

struct GeolocationBridgeTests {
    @Test func parsesWellFormedMessage() {
        let parsed = GeolocationBridge.parse(["type": "get", "id": 3])
        #expect(parsed?.type == "get")
        #expect(parsed?.jsID == 3)
    }

    @Test func parsesWatchAndClear() {
        #expect(GeolocationBridge.parse(["type": "watch", "id": 1])?.type == "watch")
        #expect(GeolocationBridge.parse(["type": "clear", "id": 7])?.type == "clear")
    }

    @Test func ignoresExtraKeys() {
        let parsed = GeolocationBridge.parse(["type": "get", "id": 2, "junk": "x"])
        #expect(parsed?.jsID == 2)
    }

    @Test func rejectsMissingType() {
        #expect(GeolocationBridge.parse(["id": 3]) == nil)
    }

    @Test func rejectsMissingID() {
        #expect(GeolocationBridge.parse(["type": "get"]) == nil)
    }

    @Test func rejectsStringID() {
        #expect(GeolocationBridge.parse(["type": "get", "id": "3"]) == nil)
    }

    @Test func rejectsNonDictionaryBody() {
        #expect(GeolocationBridge.parse("get") == nil)
        #expect(GeolocationBridge.parse([1, 2, 3]) == nil)
        #expect(GeolocationBridge.parse(NSNull()) == nil)
    }

    @Test func rejectsWrongValueTypes() {
        #expect(GeolocationBridge.parse(["type": 4, "id": 3]) == nil)
    }
}
