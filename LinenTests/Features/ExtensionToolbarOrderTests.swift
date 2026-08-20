// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

/// The arrangement of the extensions bar: the order icons sit in, which of
/// them are on the bar at all, and the promise that an index written before
/// either idea existed still opens the way it always did.
@MainActor
struct ExtensionToolbarOrderTests {
    /// Each test gets its own directory, so nothing here touches the real
    /// library in Application Support.
    private func makeLibrary() -> (ExtensionLibrary, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("linen-extensions-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (ExtensionLibrary(baseDirectory: directory), directory)
    }

    /// Recording an install is the only way records get into a library, so
    /// this is how a test arranges one. The package itself is beside the
    /// point here: these tests are about the arrangement of the bar.
    private func install(_ ids: [String], into library: ExtensionLibrary) {
        for id in ids {
            library.recordInstall(id: id)
        }
    }

    private func writeIndex(_ json: String, to directory: URL) {
        try? Data(json.utf8).write(to: directory.appendingPathComponent("installed.json"))
    }

    // MARK: - Order

    @Test func installsLandAtTheEndRatherThanShufflingTheBar() {
        let (library, directory) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }

        install(["a", "b", "c"], into: library)

        #expect(library.records.map(\.id) == ["a", "b", "c"])
        #expect(library.records.map(\.toolbarOrder) == [0, 1, 2])
    }

    @Test func movingBeforeANeighbourReordersTheBar() {
        let (library, directory) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }

        install(["a", "b", "c"], into: library)
        library.move("c", before: "a")

        #expect(library.records.map(\.id) == ["c", "a", "b"])
        #expect(library.records.map(\.toolbarOrder) == [0, 1, 2])
    }

    @Test func movingBeforeNothingSendsItToTheEnd() {
        let (library, directory) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }

        install(["a", "b", "c"], into: library)
        library.move("a", before: nil)

        #expect(library.records.map(\.id) == ["b", "c", "a"])
    }

    /// The toolbar only draws the enabled, loaded, pinned records, so a
    /// drag is always made against a *visible* neighbour. The move has to
    /// land correctly in the full list even when other records sit between
    /// the two the user could see.
    @Test func movingAgainstAVisibleNeighbourStepsOverTheHiddenOnes() {
        let (library, directory) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }

        install(["a", "off", "b", "away", "c"], into: library)
        library.setEnabled(false, id: "off")
        library.setPinned(false, id: "away")

        // On the bar the user sees a, b, c - and drags c in front of b.
        library.move("c", before: "b")

        #expect(library.records.map(\.id) == ["a", "off", "c", "b", "away"])
        let onTheBar = library.records
            .filter { $0.enabled && $0.isPinned }
            .map(\.id)
        #expect(onTheBar == ["a", "c", "b"])
    }

    @Test func orderSurvivesAReload() {
        let (library, directory) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }

        install(["a", "b", "c"], into: library)
        library.move("c", before: "a")

        let reopened = ExtensionLibrary(baseDirectory: directory)
        reopened.load()
        #expect(reopened.records.map(\.id) == ["c", "a", "b"])
    }

    // MARK: - Pinning

    /// Being off the bar is not the same as being switched off: an unpinned
    /// extension is still enabled, and still loads on the next launch.
    @Test func unpinningLeavesTheExtensionRunning() {
        let (library, directory) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }

        install(["a"], into: library)
        library.setPinned(false, id: "a")

        #expect(library.records[0].isPinned == false)
        #expect(library.records[0].enabled == true)

        let reopened = ExtensionLibrary(baseDirectory: directory)
        reopened.load()
        #expect(reopened.records[0].isPinned == false)
        #expect(reopened.records[0].enabled == true)
    }

    @Test func pinningPutsItBackWhereItWas() {
        let (library, directory) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }

        install(["a", "b", "c"], into: library)
        library.setPinned(false, id: "b")
        library.setPinned(true, id: "b")

        #expect(library.records.map(\.id) == ["a", "b", "c"])
        #expect(library.records.allSatisfy { $0.isPinned })
    }

    // MARK: - Older indexes

    /// The two fields arrived after the first indexes were on disk. One
    /// without them means "everything on the bar, in install order".
    @Test func anIndexWrittenBeforeTheseFieldsOpensUnchanged() {
        let (library, directory) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }

        writeIndex(
            """
            {"records":[\
            {"id":"first","displayName":"First","version":"1","enabled":true,"installedAt":1},\
            {"id":"second","displayName":"Second","version":"1","enabled":false,"installedAt":2}\
            ]}
            """,
            to: directory
        )
        library.load()

        #expect(library.records.map(\.id) == ["first", "second"])
        #expect(library.records.allSatisfy { $0.isPinned })
        #expect(library.records.map(\.toolbarOrder) == [0, 1])
        // The rest of the record is untouched by the migration.
        #expect(library.records[1].enabled == false)
        #expect(library.records[0].displayName == "First")
    }

    /// A half-migrated index - some records arranged, some written by an
    /// older build - puts the arranged ones first and leaves the rest in
    /// the order they were already in.
    @Test func recordsWithoutAnOrderFallInBehindTheOnesThatHaveOne() {
        let (library, directory) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }

        writeIndex(
            """
            {"records":[\
            {"id":"older","displayName":"Older","version":"1","enabled":true,"installedAt":1},\
            {"id":"arranged","displayName":"Arranged","version":"1","enabled":true,\
            "installedAt":2,"isPinned":true,"toolbarOrder":0},\
            {"id":"alsoOlder","displayName":"Also older","version":"1","enabled":true,"installedAt":3}\
            ]}
            """,
            to: directory
        )
        library.load()

        #expect(library.records.map(\.id) == ["arranged", "older", "alsoOlder"])
        #expect(library.records.map(\.toolbarOrder) == [0, 1, 2])
    }

    @Test func uninstallingClosesTheGapItLeaves() {
        let (library, directory) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }

        install(["a", "b", "c"], into: library)
        library.uninstall(id: "b")

        #expect(library.records.map(\.id) == ["a", "c"])
        #expect(library.records.map(\.toolbarOrder) == [0, 1])
    }
}
