// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

#if DEBUG
import Foundation
import Network
import Testing
import WebKit

@testable import Linen

@MainActor
struct StageIsolationTests {
    private func home(_ name: String) -> URL {
        TestFiles.directory.appending(path: "stage-\(UUID().uuidString)").appending(path: name)
    }

    private func remove(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Issue.record(error, "Could not remove \(url.path)")
        }
    }

    @Test func eachHomeKeepsItsOwnPreferencesAcrossARestart() {
        let first = home("first")
        let second = home("second")
        let restarted = first.deletingLastPathComponent().appending(path: "unused").appending(path: "..").appending(path: "first")
        defer {
            for suite in [first, second].map(StageMode.defaultsSuiteName(for:)) {
                UserDefaults.standard.removePersistentDomain(forName: suite)
                // removePersistentDomain leaves an empty plist behind.
                remove(URL.libraryDirectory.appending(path: "Preferences/\(suite).plist"))
            }
        }

        StageMode.defaults(for: first).set("first", forKey: "stage.isolation")
        StageMode.defaults(for: second).set("second", forKey: "stage.isolation")

        #expect(StageMode.defaults(for: second).string(forKey: "stage.isolation") == "second")
        #expect(StageMode.defaults(for: first).string(forKey: "stage.isolation") == "first")
        #expect(StageMode.defaults(for: restarted).string(forKey: "stage.isolation") == "first")
    }

    @Test func eachHomeKeepsItsOwnWebsiteData() async throws {
        let first = home("first")
        let second = home("second")
        let cookie = try #require(HTTPCookie(properties: [
            .name: "stage", .value: "first", .domain: "stage.example", .path: "/",
            .expires: Date(timeIntervalSinceNow: 3_600),
        ]))
        // WebKit crashes removing a store before any store exists in the process.
        _ = WKWebsiteDataStore.nonPersistent()
        let firstStore = StageMode.websiteDataStore(for: first)
        let secondStore = StageMode.websiteDataStore(for: second)

        await firstStore.httpCookieStore.setCookie(cookie)
        let firstCookies = await firstStore.httpCookieStore.allCookies().map(\.name)
        let secondCookies = await secondStore.httpCookieStore.allCookies()

        // Nothing above throws, so the persistent stores are always removed, and a failed removal is reported.
        for home in [first, second] {
            do {
                try await WKWebsiteDataStore.remove(forIdentifier: StageMode.dataStoreID(for: home))
            } catch {
                Issue.record(error, "Could not remove the website data store of \(home.path)")
            }
        }

        #expect(firstCookies == ["stage"])
        #expect(secondCookies.isEmpty)
    }

    @Test func aStageSocketPathFitsInASocketAddress() {
        let long = URL(filePath: "/Users/" + String(repeating: "a-long-name/", count: 30), directoryHint: .isDirectory)
        #expect(LocalMCPEndpoint.stagePath(for: long).utf8.count < 104)
    }

    @Test func twoStageHomesServeAtTheSameTimeEachOnItsOwnSocket() async throws {
        let first = LocalMCPEndpoint.stagePath(for: home("first"))
        let second = LocalMCPEndpoint.stagePath(for: home("second"))
        let accepted = Accepted()
        var listeners: [LocalMCPListener] = []
        // Registered before the throwing initializers: the first listener creates its directory even if the second fails.
        defer {
            for listener in listeners {
                listener.stop()
            }
            for path in [first, second] {
                remove(URL(filePath: path).deletingLastPathComponent())
            }
        }
        listeners.append(try LocalMCPListener(path: first) { _ in accepted.first += 1 })
        listeners.append(try LocalMCPListener(path: second) { _ in accepted.second += 1 })
        try await listeners[0].start()
        try await listeners[1].start()

        let connection = NWConnection(to: .unix(path: first), using: .tcp)
        defer { connection.cancel() }
        connection.start(queue: .main)

        #expect(await waitUntil { accepted.first == 1 })
        #expect(accepted.second == 0)
    }
}

@MainActor
private final class Accepted {
    var first = 0
    var second = 0
}
#endif
