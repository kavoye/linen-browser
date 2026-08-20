// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

struct JSONFileStoreTests {
    private nonisolated struct Payload: Codable, Equatable, Sendable {
        var zebra: String
        var apple: Int
    }

    private func scratch() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "JSONFileStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    @Test func aValueCanBeReadBackAsItself() throws {
        let directory = scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "value.json")
        let written = Payload(zebra: "z", apple: 1)

        JSONFileStore.encodeAndWrite(written, to: file)

        let read = try JSONDecoder().decode(Payload.self, from: Data(contentsOf: file))
        #expect(read == written)
    }

    @Test func aMissingFolderIsBuiltOnTheWayDown() {
        let directory = scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "one/two/three/value.json")

        JSONFileStore.encodeAndWrite(Payload(zebra: "z", apple: 1), to: file)

        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func writingTwiceLeavesTheSecondValue() throws {
        let directory = scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "value.json")

        JSONFileStore.encodeAndWrite(Payload(zebra: "first", apple: 1), to: file)
        JSONFileStore.encodeAndWrite(Payload(zebra: "second", apple: 2), to: file)

        let read = try JSONDecoder().decode(Payload.self, from: Data(contentsOf: file))
        #expect(read == Payload(zebra: "second", apple: 2))
    }

    @Test func sortedKeysPutTheFileInAStableOrder() throws {
        let directory = scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sorted = directory.appending(path: "sorted.json")

        JSONFileStore.encodeAndWrite(Payload(zebra: "z", apple: 1), to: sorted, sortedKeys: true)

        let text = try String(contentsOf: sorted, encoding: .utf8)
        let apple = try #require(text.range(of: "apple"))
        let zebra = try #require(text.range(of: "zebra"))
        #expect(apple.lowerBound < zebra.lowerBound)
    }

    @Test func aValueThatCannotBeEncodedLeavesNoFileBehind() {
        nonisolated struct Unencodable: Encodable {
            func encode(to encoder: any Encoder) throws {
                throw CocoaError(.coderInvalidValue)
            }
        }
        let directory = scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "value.json")

        JSONFileStore.encodeAndWrite(Unencodable(), to: file)

        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func aFailedEncodeLeavesTheEarlierFileIntact() throws {
        nonisolated struct Unencodable: Encodable {
            func encode(to encoder: any Encoder) throws {
                throw CocoaError(.coderInvalidValue)
            }
        }
        let directory = scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "value.json")
        JSONFileStore.encodeAndWrite(Payload(zebra: "kept", apple: 1), to: file)

        JSONFileStore.encodeAndWrite(Unencodable(), to: file)

        let read = try JSONDecoder().decode(Payload.self, from: Data(contentsOf: file))
        #expect(read == Payload(zebra: "kept", apple: 1))
    }

    @Test func theActorWritesThroughToTheSameFile() async throws {
        let directory = scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "actor.json")

        await JSONFileStore.shared.write(Payload(zebra: "z", apple: 9), to: file)

        let read = try JSONDecoder().decode(Payload.self, from: Data(contentsOf: file))
        #expect(read == Payload(zebra: "z", apple: 9))
    }
}
