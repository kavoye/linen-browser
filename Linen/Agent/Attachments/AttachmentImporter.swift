// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

nonisolated enum AttachmentImporter {
    static let textExtensions: Set<String> = [
        "md", "markdown", "txt", "csv", "tsv", "json", "jsonl", "yaml", "yml", "xml", "html", "htm",
        "css", "js", "jsx", "ts", "tsx", "swift", "py", "rb", "rs", "go", "c", "h", "cpp", "hpp",
        "java", "kt", "sh", "sql", "toml", "ini", "log", "tex", "diff", "patch", "rtf",
    ]

    static func read(_ url: URL) throws -> AssistantAttachment {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentTypeKey])
        guard values.isRegularFile == true else {
            throw AttachmentFailure.message(String(localized: "Choose files, not folders."))
        }
        guard (values.fileSize ?? 0) <= AssistantAttachment.maximumFileBytes else {
            throw AttachmentFailure.message(String(localized: "Each attachment must be 20 MB or smaller."))
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: AssistantAttachment.maximumFileBytes + 1) ?? Data()
        return try prepare(data: data, name: url.lastPathComponent, type: values.contentType)
    }

    static func prepare(data: Data, name: String, type: UTType? = nil) throws -> AssistantAttachment {
        try Task.checkCancellation()
        guard !data.isEmpty else {
            throw AttachmentFailure.message(String(localized: "This file is empty."))
        }
        guard data.count <= AssistantAttachment.maximumFileBytes else {
            throw AttachmentFailure.message(String(localized: "Each attachment must be 20 MB or smaller."))
        }
        let ext = (name as NSString).pathExtension.lowercased()
        let type = type ?? UTType(filenameExtension: ext) ?? .data
        var text: String
        var images: [AssistantAttachment.Image] = []
        if type.conforms(to: .pdf) || ext == "pdf" {
            (text, images) = try pdf(data)
        } else if type.conforms(to: .image) {
            let image = try normalizedImage(data)
            images = [.init(data: image.data, mimeType: "image/jpeg")]
            text = try recognize(image.cgImage)
        } else if type.conforms(to: .rtf) || ext == "rtf" {
            text = try NSAttributedString(
                data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil
            ).string
        } else if type.conforms(to: .text) || textExtensions.contains(ext) || type.conforms(to: .json) {
            text = try decodeText(data)
        } else {
            throw AttachmentFailure.message(String(localized: "This file type isn’t supported. Attach an image, PDF, RTF, or text file."))
        }
        guard text.count <= AssistantAttachment.maximumTextCharacters else {
            throw AttachmentFailure.message(String(localized: "This document contains too much text. Attach a shorter selection."))
        }
        return AssistantAttachment(
            id: UUID(), name: name, contentType: (ext == "pdf" ? UTType.pdf : type).identifier,
            data: data, text: text, images: images
        )
    }

    static func decodeText(_ data: Data) throws -> String {
        let text: String?
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            text = String(data: data, encoding: .utf16)
        } else {
            text = String(data: data, encoding: .utf8)
        }
        guard let text, !text.contains("\0") else {
            throw AttachmentFailure.message(String(localized: "This file isn’t readable text. Save it as UTF-8 or UTF-16 and try again."))
        }
        return text
    }

    private static func normalizedImage(_ data: Data) throws -> (data: Data, cgImage: CGImage) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, Double(width) * Double(height) <= 100_000_000,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 1_600,
                  kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary)
        else {
            throw AttachmentFailure.message(String(localized: "This image couldn’t be read or is too large to process."))
        }
        return (try jpeg(image), image)
    }

    private static func jpeg(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw AttachmentFailure.message(String(localized: "This image couldn’t be prepared."))
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw AttachmentFailure.message(String(localized: "This image couldn’t be prepared."))
        }
        return data as Data
    }

    private static func recognize(_ image: CGImage) throws -> String {
        try Task.checkCancellation()
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    private static func pdf(_ data: Data) throws -> (String, [AssistantAttachment.Image]) {
        guard let document = PDFDocument(data: data), !document.isLocked, document.pageCount > 0 else {
            throw AttachmentFailure.message(String(localized: "This PDF is locked or couldn’t be read. Attach an unlocked copy."))
        }
        guard document.pageCount <= AssistantAttachment.maximumPages else {
            throw AttachmentFailure.message(String(localized: "Attach PDFs with 20 pages or fewer. Export a page range from longer documents."))
        }
        var pages: [String] = []
        var images: [AssistantAttachment.Image] = []
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else {
                throw AttachmentFailure.message(String(localized: "This PDF contains an unreadable page."))
            }
            let thumbnail = page.thumbnail(of: CGSize(width: 1_200, height: 1_600), for: .mediaBox)
            guard let cgImage = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                throw AttachmentFailure.message(String(localized: "This PDF page couldn’t be prepared."))
            }
            var text = (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                text = try recognize(cgImage)
            }
            if !text.isEmpty {
                pages.append("Page \(index + 1):\n\(text)")
            }
            images.append(.init(data: try jpeg(cgImage), mimeType: "image/jpeg"))
        }
        return (pages.joined(separator: "\n\n"), images)
    }
}
