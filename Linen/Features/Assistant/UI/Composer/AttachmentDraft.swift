// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class AttachmentDraft {
    var files: [AssistantAttachment] = []
    var error: String?
    private(set) var pendingImports = 0
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var work: Task<Void, Never>?

    nonisolated enum Source: Sendable {
        case file(URL)
        case bytes(Data, name: String, type: UTType)

        func read() throws -> AssistantAttachment {
            switch self {
            case .file(let url):
                try AttachmentImporter.read(url)
            case .bytes(let data, let name, let type):
                try AttachmentImporter.prepare(data: data, name: name, type: type)
            }
        }
    }

    var isImporting: Bool {
        pendingImports > 0
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image, .pdf, .rtf, .text, .json] + AttachmentImporter.textExtensions.compactMap {
            UTType(filenameExtension: $0)
        }
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            self?.add(panel.urls.map { .file($0) })
        }
    }

    func add(_ sources: [Source]) {
        guard !sources.isEmpty else { return }
        guard sources.count + files.count + pendingImports <= AssistantAttachment.maximumFiles else {
            error = String(localized: "Attach up to 10 files at a time.")
            return
        }
        let token = generation
        let previous = work
        pendingImports += sources.count
        error = nil
        work = Task { [weak self] in
            await previous?.value
            for source in sources {
                guard let self, generation == token else { return }
                let reader = Task.detached(priority: .userInitiated) { try source.read() }
                let result = await withTaskCancellationHandler {
                    await reader.result
                } onCancel: {
                    reader.cancel()
                }
                guard generation == token else { return }
                pendingImports -= 1
                do {
                    let file = try result.get()
                    try AssistantAttachment.validate(files + [file])
                    files.append(file)
                } catch is CancellationError {
                    return
                } catch {
                    self.error = error.localizedDescription
                }
            }
        }
    }

    @discardableResult
    func paste(_ pasteboard: NSPasteboard) -> Bool {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            add(urls.map { .file($0) })
            return true
        }
        for (pasteType, type, name) in [(NSPasteboard.PasteboardType.png, UTType.png, "Pasted Image.png"), (.tiff, .tiff, "Pasted Image.tiff")] {
            if let data = pasteboard.data(forType: pasteType) {
                add([.bytes(data, name: name, type: type)])
                return true
            }
        }
        return false
    }

    func drop(_ providers: [NSItemProvider]) -> Bool {
        let token = generation
        let accepted = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
                || $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
        }
        guard !accepted.isEmpty else { return false }
        guard accepted.count + files.count + pendingImports <= AssistantAttachment.maximumFiles else {
            error = String(localized: "Attach up to 10 files at a time.")
            return true
        }
        pendingImports += accepted.count
        Task { [weak self] in
            for provider in accepted {
                let type = provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
                    ? UTType.fileURL.identifier
                    : provider.registeredTypeIdentifiers.first { UTType($0)?.conforms(to: .image) == true } ?? UTType.png.identifier
                let result: Result<Data, Error> = await withCheckedContinuation { continuation in
                    provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
                        if let data {
                            continuation.resume(returning: .success(data))
                        } else {
                            continuation.resume(returning: .failure(error ?? AttachmentFailure.message(String(localized: "This attachment couldn’t be read."))))
                        }
                    }
                }
                guard let self, generation == token else { return }
                pendingImports -= 1
                do {
                    let data = try result.get()
                    if type == UTType.fileURL.identifier {
                        guard let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL else {
                            throw AttachmentFailure.message(String(localized: "This attachment couldn’t be read."))
                        }
                        add([.file(url)])
                    } else {
                        let contentType = UTType(type) ?? .png
                        add([.bytes(data, name: "Dropped Image.\(contentType.preferredFilenameExtension ?? "png")", type: contentType)])
                    }
                } catch {
                    self.error = error.localizedDescription
                }
            }
        }
        return true
    }

    func clear() {
        generation = UUID()
        work?.cancel()
        work = nil
        pendingImports = 0
        files = []
        error = nil
    }
}
