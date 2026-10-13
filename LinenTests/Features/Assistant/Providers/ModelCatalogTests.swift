// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

@Suite("Model catalog")
struct ModelCatalogTests {
    private let hosted = Provider(
        id: "hosted",
        name: "Hosted",
        blurb: "",
        symbol: "cloud",
        baseURL: URL(string: "https://models.example/v1"),
        wire: .chatCompletions,
        auth: .bearer
    )

    private let local = Provider(
        id: "local",
        name: "Local",
        blurb: "",
        symbol: "desktopcomputer",
        baseURL: URL(string: "http://localhost:11434/v1"),
        wire: .chatCompletions,
        auth: .none,
        isLocal: true
    )

    @Test func hostedCatalogKeepsTextModelsNewestFirst() throws {
        let data = json([
            ["id": "chat-older", "created": 10],
            ["id": "text-embedding-3-small", "created": 30],
            ["id": "chat-newer", "created": 20],
        ])

        #expect(try ModelCatalog.modelIDs(from: data, for: hosted) == ["chat-newer", "chat-older"])
    }

    @Test func hostedFilteringIsCaseInsensitive() throws {
        let data = json([
            ["id": "WHISPER-LARGE"],
            ["id": "IMAGE-1"],
            ["id": "Reasoning-1"],
        ])

        #expect(try ModelCatalog.modelIDs(from: data, for: hosted) == ["Reasoning-1"])
    }

    @Test func localCatalogKeepsUserInstalledModels() throws {
        let data = json([
            ["id": "zeta-embed"],
            ["id": "alpha-audio"],
        ])

        #expect(try ModelCatalog.modelIDs(from: data, for: local) == ["alpha-audio", "zeta-embed"])
    }

    @Test func entriesWithoutAnIDAreIgnored() throws {
        let data = json([
            ["created": 20],
            ["id": "usable"],
        ])

        #expect(try ModelCatalog.modelIDs(from: data, for: hosted) == ["usable"])
    }

    @Test func anEmptyCatalogIsValid() throws {
        #expect(try ModelCatalog.modelIDs(from: Data(#"{"data":[]}"#.utf8), for: hosted).isEmpty)
    }

    @Test(arguments: [Data(), Data(#"{}"#.utf8), Data(#"{"data":"wrong"}"#.utf8)])
    func malformedCatalogsFail(data: Data) {
        #expect(throws: ModelCatalogError.self) {
            try ModelCatalog.modelIDs(from: data, for: hosted)
        }
    }

    private func json(_ entries: [[String: Any]]) -> Data {
        // swiftlint:disable:next force_try
        try! JSONSerialization.data(withJSONObject: ["data": entries])
    }
}
