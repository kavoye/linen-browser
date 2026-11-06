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
    private(set) var recognizing: Set<UUID> = []
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var recognition: Task<Void, Never>?
    @ObservationIgnored private let recognize: @Sendable (AssistantAttachment) async throws -> String

    init(
        recognize: @escaping @Sendable (AssistantAttachment) async throws -> String = {
            try AttachmentImporter.recognizedText(in: $0)
        }
    ) {
        self.recognize = recognize
    }

    nonisolated enum Source: Sendable {
        case file(URL)
        case bytes(Data, name: String, type: UTType)

        func read() throws -> AttachmentImporter.Draft {
            switch self {
            case .file(let url):
                try AttachmentImporter.draft(url)
            case .bytes(let data, let name, let type):
                try AttachmentImporter.draft(data: data, name: name, type: type)
            }
        }
    }

    var isImporting: Bool {
        pendingImports > 0
    }

    var isRecognizing: Bool {
        !recognizing.isEmpty
    }

    func isReady(textOnly: Bool) -> Bool {
        !isImporting && !(textOnly && isRecognizing)
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
                    let draft = try result.get()
                    try AssistantAttachment.validate(files + [draft.file])
                    files.append(draft.file)
                    if draft.needsRecognition {
                        recognizeText(in: draft.file)
                    }
                } catch is CancellationError {
                    return
                } catch {
                    self.error = error.localizedDescription
                }
            }
        }
    }

    private func recognizeText(in file: AssistantAttachment) {
        let token = generation
        let previous = recognition
        let recognize = recognize
        recognizing.insert(file.id)
        recognition = Task { [weak self] in
            await previous?.value
            guard let self, generation == token else { return }
            defer { recognizing.remove(file.id) }
            guard files.contains(where: { $0.id == file.id }) else { return }
            let reader = Task.detached(priority: .utility) { try await recognize(file) }
            let result = await withTaskCancellationHandler {
                await reader.result
            } onCancel: {
                reader.cancel()
            }
            guard generation == token,
                  case .success(let text) = result,
                  let index = files.firstIndex(where: { $0.id == file.id })
            else { return }
            files[index].text = text
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
        recognition?.cancel()
        recognition = nil
        recognizing = []
        pendingImports = 0
        files = []
        error = nil
    }
}
