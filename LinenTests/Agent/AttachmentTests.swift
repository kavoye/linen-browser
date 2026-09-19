// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import CoreText
import GRDB
import PDFKit
import Testing
import UniformTypeIdentifiers

@testable import Linen

@MainActor
struct AttachmentTests {
    @Test(arguments: ["notes.md", "data.csv", "sample.swift", "data.json", "notes.txt"])
    func readsTextFiles(name: String) throws {
        let bytes = Data("Hello, 世界\nsecond line".utf8)
        let file = try AttachmentImporter.prepare(data: bytes, name: name)
        #expect(file.name == name)
        #expect(file.text == "Hello, 世界\nsecond line")
        #expect(file.data == bytes)
        #expect(file.images.isEmpty)
    }

    @Test func readsRTFAsText() throws {
        let attributed = NSAttributedString(string: "Styled document", attributes: [.font: NSFont.boldSystemFont(ofSize: 18)])
        let bytes = try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        let file = try AttachmentImporter.prepare(data: bytes, name: "notes.rtf")
        #expect(file.text == "Styled document")
        #expect(file.data == bytes)
    }

    @Test func normalizesImagesAndRecognizesText() throws {
        let file = try AttachmentImporter.prepare(data: image(), name: "receipt.png", type: .png)
        #expect(file.images.count == 1)
        #expect(file.images.first?.mimeType == "image/jpeg")
        #expect(file.text.contains("INVOICE"))
        #expect(file.text.contains("42"))
    }

    @Test func readsPDFTextAndKeepsPageImages() throws {
        let file = try AttachmentImporter.prepare(data: pdf(), name: "invoice.pdf")
        #expect(file.isPDF)
        #expect(file.images.count == 1)
        #expect(file.text.contains("INVOICE 42"))
        #expect(file.text.contains("Page 1"))
    }

    @Test func recognizesScannedPDFPages() throws {
        let file = try AttachmentImporter.prepare(data: pdf(scanned: true), name: "scan.pdf")
        #expect(file.text.contains("INVOICE"))
        #expect(file.text.contains("42"))
        #expect(file.images.count == 1)
    }

    @Test func rejectsUnreadableAndOversizedFiles() throws {
        #expect(throws: AttachmentFailure.self) {
            try AttachmentImporter.prepare(data: Data([0, 1, 2]), name: "binary.txt")
        }
        #expect(throws: AttachmentFailure.self) {
            try AttachmentImporter.prepare(data: Data([1]), name: "archive.zip")
        }
        #expect(throws: AttachmentFailure.self) {
            try AttachmentImporter.prepare(data: Data(), name: "empty.md")
        }
        #expect(throws: AttachmentFailure.self) {
            try AttachmentImporter.prepare(data: Data(repeating: 1, count: AssistantAttachment.maximumFileBytes + 1), name: "big.pdf")
        }
        #expect(throws: AttachmentFailure.self) {
            try AttachmentImporter.prepare(data: pdf(pages: AssistantAttachment.maximumPages + 1), name: "long.pdf")
        }
        #expect(throws: AttachmentFailure.self) {
            try AttachmentImporter.prepare(data: Data("broken".utf8), name: "broken.pdf")
        }
    }

    @Test func preservesUTF16Text() throws {
        let bytes = try #require("Café and tea".data(using: .utf16))
        #expect(try AttachmentImporter.decodeText(bytes) == "Café and tea")
    }

    @Test func persistsAttachmentsAndDeletesThemWithTheConversation() throws {
        let database = AppDatabase.temporary()
        let log = ConversationLog(database: database)
        let tab = UUID()
        let task = log.beginTask("Read this", tabID: tab)
        let file = try AttachmentImporter.prepare(data: Data("My notes".utf8), name: "notes.md")
        log.setAttachments([file], textOnly: true, taskID: task)
        log.completeTask(task, response: "Read.")
        log.saveBlocking()

        let reopened = ConversationLog(database: database)
        #expect(reopened.latestTrace(forTab: tab)?.attachments == [file])
        #expect(reopened.exchanges(forTab: tab).first?.attachments == [file])
        #expect(reopened.exchanges(forTab: tab).first?.attachmentTextOnly == true)
        reopened.removeTab(tab)
        let count = try database.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM agentAttachments") }
        #expect(count == 0)
        #expect(ConversationLog(database: database).traces.isEmpty)
    }

    @Test func enforcesBatchAndModelLimits() throws {
        let file = try AttachmentImporter.prepare(data: Data("notes".utf8), name: "notes.md")
        #expect(throws: AttachmentFailure.self) {
            try AssistantAttachment.validate(Array(repeating: file, count: AssistantAttachment.maximumFiles + 1))
        }
        let large = try AttachmentImporter.prepare(data: Data(String(repeating: "a", count: 10_000).utf8), name: "notes.md")
        #expect(throws: AttachmentFailure.self) {
            try AttachmentRequest.validate([large], message: "Read", textOnly: true, windowTokens: 4_096)
        }
        let visual = AssistantAttachment(
            id: UUID(), name: "photo.jpg", contentType: UTType.jpeg.identifier,
            data: Data([1]), text: "", images: [.init(data: Data([1]), mimeType: "image/jpeg")]
        )
        #expect(throws: AttachmentFailure.self) {
            try AttachmentRequest.validate([visual], message: "Read", textOnly: true, windowTokens: 32_000)
        }
        #expect(AttachmentRequest.images([visual], textOnly: true).isEmpty)
        #expect(AttachmentRequest.images([visual], textOnly: false).count == 1)
    }

    @Test func pastingAnImageCreatesARemovableAttachment() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setData(try image(), forType: .png)
        let draft = AttachmentDraft()
        #expect(draft.paste(pasteboard))
        #expect(await waitUntil { !draft.isImporting })
        #expect(draft.files.count == 1)
        #expect(draft.files.first?.images.count == 1)
        #expect(draft.error == nil)
        draft.files.removeAll()
        #expect(draft.files.isEmpty)
    }

    @Test func pasteImportsFilesWithoutReplacingTheDraft() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).md")
        try Data("Pasted document".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.writeObjects([url as NSURL])
        let draft = AttachmentDraft()
        #expect(draft.paste(pasteboard))
        #expect(await waitUntil { !draft.isImporting })
        #expect(draft.files.first?.text == "Pasted document")
        #expect(draft.error == nil)
        draft.clear()
        #expect(draft.files.isEmpty)
    }

    @Test func droppingAFileURLImportsItsContents() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).md")
        try Data("Dropped document".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let provider = NSItemProvider(item: url as NSURL, typeIdentifier: UTType.fileURL.identifier)
        let draft = AttachmentDraft()
        #expect(draft.drop([provider]))
        #expect(await waitUntil { !draft.isImporting })
        #expect(draft.files.first?.text == "Dropped document")
        #expect(draft.error == nil)
    }

    @Test func clearingDuringImportDoesNotRestoreTheFiles() async {
        let draft = AttachmentDraft()
        draft.add([.bytes(Data("Hello".utf8), name: "notes.md", type: .plainText)])
        draft.clear()
        draft.add([.bytes(Data("New".utf8), name: "new.txt", type: .plainText)])
        #expect(await waitUntil { !draft.isImporting })
        #expect(draft.files.map(\.name) == ["new.txt"])
    }

    private func image() throws -> Data {
        let image = NSImage(size: NSSize(width: 600, height: 160))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 600, height: 160).fill()
        ("INVOICE 42" as NSString).draw(at: NSPoint(x: 20, y: 60), withAttributes: [
            .font: NSFont.systemFont(ofSize: 56), .foregroundColor: NSColor.black,
        ])
        image.unlockFocus()
        let tiff = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

    private func pdf(pages: Int = 1, scanned: Bool = false) throws -> Data {
        let data = NSMutableData()
        let consumer = try #require(CGDataConsumer(data: data))
        var bounds = CGRect(x: 0, y: 0, width: 600, height: 300)
        let context = try #require(CGContext(consumer: consumer, mediaBox: &bounds, nil))
        for _ in 0..<pages {
            context.beginPDFPage(nil)
            if scanned {
                let bitmap = try #require(NSBitmapImageRep(data: image()))
                context.draw(try #require(bitmap.cgImage), in: CGRect(x: 0, y: 100, width: 600, height: 160))
            } else {
                let text = NSAttributedString(string: "INVOICE 42", attributes: [.font: NSFont.systemFont(ofSize: 36)])
                context.textPosition = CGPoint(x: 30, y: 150)
                CTLineDraw(CTLineCreateWithAttributedString(text), context)
            }
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }
}
