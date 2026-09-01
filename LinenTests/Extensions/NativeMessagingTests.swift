// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

/// The native-messaging bridge speaks Chrome's stdio protocol: a little-endian
/// length header, then the JSON. The dead host leads - a launch-constrained
/// helper is AMFI-killed the instant an unlisted browser launches it.
struct NativeMessagingTests {
    // MARK: - Hosts that die

    /// A regression here SIGPIPE-kills the test runner itself.
    @Test func aWriteToADeadHostIsHarmless() async throws {
        let manifest = NativeMessagingManifest(
            name: "com.example.exits",
            path: "/usr/bin/true",
            allowedOrigins: ["chrome-extension://abcdef/"]
        )
        let connection = try NativeMessagingConnection(manifest: manifest, arguments: ["chrome-extension://abcdef/"])

        var sawClose = false
        for await event in connection.events {
            if case .closed = event { sawClose = true }
        }
        #expect(sawClose, "a host that exits reports its close")

        connection.send(Data(#"{"late":true}"#.utf8))
        try await Task.sleep(for: .milliseconds(200))
    }

    @Test func aHostThatFailsReportsItsExit() async throws {
        let manifest = NativeMessagingManifest(
            name: "com.example.fails",
            path: "/usr/bin/false",
            allowedOrigins: ["chrome-extension://abcdef/"]
        )
        let connection = try NativeMessagingConnection(manifest: manifest, arguments: ["chrome-extension://abcdef/"])

        var closure: NativeMessagingError?
        for await event in connection.events {
            if case .closed(let error) = event { closure = error }
        }
        #expect(closure == .hostExited, "a nonzero exit is an error, not a clean close")
    }

    // MARK: - A host that answers

    @Test func aHostRepliesToWhatTheBridgeSends() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let host = directory.appendingPathComponent("echo-host")
        let script = """
        #!/usr/bin/env python3
        import sys, struct
        header = sys.stdin.buffer.read(4)
        length = struct.unpack('<I', header)[0]
        body = sys.stdin.buffer.read(length)
        out = b'{"echo":true}'
        sys.stdout.buffer.write(struct.pack('<I', len(out)) + out)
        sys.stdout.buffer.flush()
        """
        try script.write(to: host, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: host.path)

        let manifest = NativeMessagingManifest(
            name: "com.example.echo",
            path: host.path,
            allowedOrigins: ["chrome-extension://abcdef/"]
        )
        let connection = try NativeMessagingConnection(manifest: manifest, arguments: ["chrome-extension://abcdef/"])
        connection.send(Data(#"{"ping":1}"#.utf8))

        var received: Data?
        for await event in connection.events {
            if case .message(let data) = event {
                received = data
                connection.close()
            }
            if case .closed = event { break }
        }

        let object = received.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        #expect(object?["echo"] as? Bool == true)
    }

    // MARK: - Errors the extension sees

    @Test func theErrorStringsAreChromesVerbatim() {
        #expect(NativeMessagingError.forbidden.localizedDescription
            == "Access to the specified native messaging host is forbidden.")
        #expect(NativeMessagingError.communicationFailed.localizedDescription
            == "Error when communicating with the native messaging host.")
        #expect(NativeMessagingError.hostExited.localizedDescription
            == "Native host has exited.")
    }

    // MARK: - Framing

    @Test func aFrameCarriesItsLengthLittleEndianFirst() throws {
        let payload = Data("hi".utf8)
        let frame = try NativeMessageFraming.encode(payload)
        #expect(Array(frame.prefix(4)) == [2, 0, 0, 0])
        #expect(frame.dropFirst(4) == payload)
    }

    @Test func aTooLargeMessageIsRefused() {
        var big = Data(count: NativeMessageFraming.maxMessageBytes + 1)
        #expect(throws: NativeMessagingError.self) {
            _ = try NativeMessageFraming.encode(big)
        }
        big.removeAll()
    }

    @Test func theDecoderYieldsWholeMessagesOnly() throws {
        var decoder = NativeMessageDecoder()
        let frame = try NativeMessageFraming.encode(Data("abc".utf8))

        decoder.append(frame.prefix(3))
        #expect(try decoder.next() == nil, "a partial header is not a message")

        decoder.append(frame.dropFirst(3))
        #expect(try decoder.next() == Data("abc".utf8))
        #expect(try decoder.next() == nil)
    }

    @Test func theDecoderSplitsBackToBackMessages() throws {
        var decoder = NativeMessageDecoder()
        var stream = Data()
        stream.append(try NativeMessageFraming.encode(Data("one".utf8)))
        stream.append(try NativeMessageFraming.encode(Data("two".utf8)))
        decoder.append(stream)

        #expect(try decoder.next() == Data("one".utf8))
        #expect(try decoder.next() == Data("two".utf8))
        #expect(try decoder.next() == nil)
    }

    @Test func theDecoderRejectsAnAbsurdLength() {
        var decoder = NativeMessageDecoder()
        decoder.append(Data([0xFF, 0xFF, 0xFF, 0xFF]))
        #expect(throws: NativeMessagingError.self) {
            _ = try decoder.next()
        }
    }

    // MARK: - Manifest

    @Test func aHostNameStaysWithinItsOwnFile() {
        #expect(NativeMessagingManifest.isValidHostName("com.apple.passwordmanager"))
        #expect(NativeMessagingManifest.isValidHostName("com_1password"))
        #expect(!NativeMessagingManifest.isValidHostName("../etc/passwd"))
        #expect(!NativeMessagingManifest.isValidHostName("a/b"))
        #expect(!NativeMessagingManifest.isValidHostName(""))
        #expect(!NativeMessagingManifest.isValidHostName("com..apple"))
    }

    @Test func onlyAStdioManifestWhoseNameMatchesParses() {
        let good = Data("""
        { "name": "com.example.host", "type": "stdio", "path": "/bin/cat",
          "allowed_origins": ["chrome-extension://abcdef/"] }
        """.utf8)
        #expect(NativeMessagingManifest.parse(good, name: "com.example.host") != nil)
        #expect(NativeMessagingManifest.parse(good, name: "com.other.host") == nil)

        let wrongType = Data("""
        { "name": "com.example.host", "type": "native", "path": "/bin/cat",
          "allowed_origins": ["chrome-extension://abcdef/"] }
        """.utf8)
        #expect(NativeMessagingManifest.parse(wrongType, name: "com.example.host") == nil)
    }

    @Test func theOriginMustBeOnTheHostsAllowlist() {
        let manifest = NativeMessagingManifest(
            name: "com.example.host",
            path: "/bin/cat",
            allowedOrigins: ["chrome-extension://pejdijmoenmkgeppbflobdenhhabjlaj/"]
        )
        #expect(manifest.allows(origin: "chrome-extension://pejdijmoenmkgeppbflobdenhhabjlaj/"))
        #expect(manifest.allows(origin: "chrome-extension://pejdijmoenmkgeppbflobdenhhabjlaj"))
        #expect(!manifest.allows(origin: "chrome-extension://someotherextensionid/"))
    }

    @Test func locateSkipsAManifestWhoseBinaryIsMissing() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let manifest = Data("""
        { "name": "com.example.missing", "type": "stdio", "path": "/does/not/exist",
          "allowed_origins": ["chrome-extension://abcdef/"] }
        """.utf8)
        try manifest.write(to: directory.appendingPathComponent("com.example.missing.json"))

        #expect(NativeMessagingManifest.locate(name: "com.example.missing", in: [directory]) == nil)
    }

    @Test func aFirefoxManifestNamesExtensionsInsteadOfOrigins() {
        let mozilla = Data("""
        { "name": "com.apple.passwordmanager", "type": "stdio", "path": "/bin/cat",
          "allowed_extensions": ["apple-passwords-firefox-extension@apple.com"] }
        """.utf8)
        let manifest = NativeMessagingManifest.parse(mozilla, name: "com.apple.passwordmanager")
        #expect(manifest?.allowedExtensions == ["apple-passwords-firefox-extension@apple.com"])
        #expect(manifest?.allowedOrigins == [])

        let empty = Data(#"{ "name": "x", "type": "stdio", "path": "/bin/cat" }"#.utf8)
        #expect(NativeMessagingManifest.parse(empty, name: "x") == nil, "a manifest allowing nobody is refused")
    }

    @Test func aPackageManifestNamesItsGeckoID() throws {
        let package = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: package) }

        let manifest = Data("""
        { "manifest_version": 2,
          "browser_specific_settings": { "gecko": { "id": "{aecec67f-0d10}" } } }
        """.utf8)
        try manifest.write(to: package.appendingPathComponent("manifest.json"))
        #expect(NativeMessagingManifest.geckoID(inPackage: package) == "{aecec67f-0d10}")

        let legacy = Data(#"{ "applications": { "gecko": { "id": "old@style" } } }"#.utf8)
        try legacy.write(to: package.appendingPathComponent("manifest.json"))
        #expect(NativeMessagingManifest.geckoID(inPackage: package) == "old@style")
    }

    @Test func locateFindsAManifestPointingAtARealBinary() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let manifest = Data("""
        { "name": "com.example.cat", "type": "stdio", "path": "/bin/cat",
          "allowed_origins": ["chrome-extension://abcdef/"] }
        """.utf8)
        try manifest.write(to: directory.appendingPathComponent("com.example.cat.json"))

        let found = NativeMessagingManifest.locate(name: "com.example.cat", in: [directory])
        #expect(found?.path == "/bin/cat")
        #expect(found?.allowedOrigins == ["chrome-extension://abcdef/"])
    }
}
