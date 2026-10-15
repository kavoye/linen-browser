// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

struct DownloadThumbnail: View {
    let item: DownloadManager.Item
    let size: CGFloat

    @Environment(\.displayScale) private var scale
    @State private var thumbnail: NSImage?

    private var file: URL? {
        item.state == .finished ? item.destination : nil
    }

    var body: some View {
        Image(nsImage: thumbnail ?? DownloadThumbnails.icon(forFilename: item.filename))
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .task(id: file) {
                guard let file else {
                    thumbnail = nil
                    return
                }
                thumbnail = await DownloadThumbnails.thumbnail(for: file, size: size, scale: scale)
            }
    }
}

enum DownloadThumbnails {
    private static let cache = NSCache<NSString, NSImage>()

    static func icon(forFilename filename: String) -> NSImage {
        let ext = (filename as NSString).pathExtension
        return NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data)
    }

    static func thumbnail(for file: URL, size: CGFloat, scale: CGFloat) async -> NSImage? {
        let key = "\(file.path)|\(size)|\(scale)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let request = QLThumbnailGenerator.Request(
            fileAt: file,
            size: CGSize(width: size, height: size),
            scale: scale,
            representationTypes: .all
        )
        request.iconMode = true
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else {
            return nil
        }
        let image = representation.nsImage
        cache.setObject(image, forKey: key)
        return image
    }
}
