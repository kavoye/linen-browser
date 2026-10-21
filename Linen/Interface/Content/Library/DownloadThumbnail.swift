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
    @State private var loaded: (file: URL, image: NSImage)?

    private var file: URL? {
        item.state == .finished ? item.destination : nil
    }

    var body: some View {
        if let file, let image = DownloadThumbnails.cached(for: file, size: size, scale: scale)
            ?? loaded.flatMap({ $0.file == file ? $0.image : nil }) {
            picture(image)
        } else {
            picture(DownloadThumbnails.icon(forFilename: item.filename))
                .task(id: file) {
                    guard let file,
                          let image = await DownloadThumbnails.thumbnail(for: file, size: size, scale: scale)
                    else { return }
                    loaded = (file, image)
                }
        }
    }

    private func picture(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

enum DownloadThumbnails {
    private static let cache = NSCache<NSString, NSImage>()
    private static var icons: [String: NSImage] = [:]
    private static var failed: Set<NSString> = []

    static func icon(forFilename filename: String) -> NSImage {
        let ext = (filename as NSString).pathExtension.lowercased()
        if let icon = icons[ext] {
            return icon
        }
        let icon = NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data)
        icons[ext] = icon
        return icon
    }

    private static func key(for file: URL, size: CGFloat, scale: CGFloat) -> NSString {
        "\(file.path)|\(size)|\(scale)" as NSString
    }

    static func cached(for file: URL, size: CGFloat, scale: CGFloat) -> NSImage? {
        cache.object(forKey: key(for: file, size: size, scale: scale))
    }

    static func thumbnail(for file: URL, size: CGFloat, scale: CGFloat) async -> NSImage? {
        let key = key(for: file, size: size, scale: scale)
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard !failed.contains(key) else { return nil }
        guard FileManager.default.fileExists(atPath: file.path) else {
            failed.insert(key)
            return nil
        }
        let request = QLThumbnailGenerator.Request(
            fileAt: file,
            size: CGSize(width: size, height: size),
            scale: scale,
            representationTypes: .all
        )
        request.iconMode = true
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else {
            failed.insert(key)
            return nil
        }
        let image = representation.nsImage
        cache.setObject(image, forKey: key)
        return image
    }
}
