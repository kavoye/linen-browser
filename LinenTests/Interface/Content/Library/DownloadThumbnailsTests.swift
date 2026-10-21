// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import Testing

@testable import Linen

@MainActor
struct DownloadThumbnailsTests {
    @Test func filesOfOneTypeShareAnIcon() {
        #expect(DownloadThumbnails.icon(forFilename: "report.pdf") === DownloadThumbnails.icon(forFilename: "Notes.PDF"))
    }

    @Test func aMadeThumbnailIsReadyWithoutWaiting() async throws {
        let directory = TestFiles.directory.appendingPathComponent("DownloadThumbnails-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("picture.png")
        let image = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            NSColor.systemTeal.setFill()
            rect.fill()
            return true
        }
        let tiff = try #require(image.tiffRepresentation)
        let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        try png.write(to: file)

        #expect(DownloadThumbnails.cached(for: file, size: 30, scale: 2) == nil)
        let made = try #require(await DownloadThumbnails.thumbnail(for: file, size: 30, scale: 2))
        #expect(DownloadThumbnails.cached(for: file, size: 30, scale: 2) === made)
    }
}
