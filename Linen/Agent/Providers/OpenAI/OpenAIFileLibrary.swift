// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import UniformTypeIdentifiers

nonisolated struct OpenAIFileCollection: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    var fileIDs: [String] = []
    var ready = false
    var storeDeleted = false
    let createdAt: Date

    func isAvailable(at date: Date = .now) -> Bool {
        ready && !storeDeleted && date.timeIntervalSince(createdAt) < 604_800
    }
}

nonisolated struct OpenAIFileLibrary: Sendable {
    let api: OpenAIAPI
    var pollInterval: Duration = .seconds(1)
    var maximumPolls = 120
    static let extensions: Set<String> = [
        "c", "cpp", "cs", "css", "doc", "docx", "go", "html", "java", "js", "json", "md", "pdf",
        "php", "pptx", "py", "rb", "sh", "tex", "ts", "txt",
    ]

    static func select(_ id: String, enabled: Bool, tools: [OpenAIJSON]) -> [OpenAIJSON] {
        var tools = tools
        for index in tools.indices where tools[index]["type"] == "file_search" {
            tools[index]["vector_store_ids"] = .array((tools[index]["vector_store_ids"].array ?? []).filter { $0 != .string(id) })
        }
        if enabled {
            if let index = tools.firstIndex(where: { $0["type"] == "file_search" }) {
                tools[index]["vector_store_ids"] = .array((tools[index]["vector_store_ids"].array ?? []) + [.string(id)])
            } else {
                tools.append(["type": "file_search", "vector_store_ids": [.string(id)]])
            }
        }
        return tools.filter { $0["type"] != "file_search" || $0["vector_store_ids"].array?.isEmpty == false }
    }

    static func validateSelection(tools: [OpenAIJSON], collections: [OpenAIFileCollection], now: Date = .now) throws {
        let selected = Set(tools.filter { $0["type"] == "file_search" }.flatMap { $0["vector_store_ids"].array ?? [] }.compactMap(\.string))
        guard !collections.contains(where: { selected.contains($0.id) && !$0.isAvailable(at: now) }) else {
            throw OpenAIFileLibraryFailure.unavailableCollection
        }
    }

    func create(name: String, files: [OpenAIUpload],
                onUpdate: @MainActor @Sendable (OpenAIFileCollection) -> Void) async throws -> OpenAIFileCollection {
        guard !files.isEmpty, files.count <= 10, files.reduce(0, { $0 + $1.data.count }) <= 40 * 1_024 * 1_024,
            files.allSatisfy({ !$0.data.isEmpty && $0.data.count <= 20 * 1_024 * 1_024
                && OpenAIUpload.valid($0.filename) && OpenAIUpload.valid($0.mimeType) && $0.field == "file"
                && Self.extensions.contains(($0.filename as NSString).pathExtension.lowercased()) })
        else { throw OpenAIFileLibraryFailure.invalidFiles }
        let response = try await api.request(["vector_stores"], body: [
            "name": .string(String(name.prefix(100))), "expires_after": ["anchor": "last_active_at", "days": 7],
        ])
        guard let id = response["id"].string else { throw OpenAIFailure(kind: .invalidResponse) }
        var collection = OpenAIFileCollection(id: id, name: String(name.prefix(100)), createdAt: .now)
        await onUpdate(collection)
        for file in files {
            try Task.checkCancellation()
            let uploaded = try await api.upload(["files"], fields: [
                "purpose": "user_data", "expires_after[anchor]": "created_at", "expires_after[seconds]": "604800",
            ], files: [file])
            guard let fileID = uploaded["id"].string else { throw OpenAIFailure(kind: .invalidResponse) }
            collection.fileIDs.append(fileID)
            await onUpdate(collection)
        }
        try Task.checkCancellation()
        let batch = try await api.request(["vector_stores", id, "file_batches"], body: [
            "file_ids": .array(collection.fileIDs.map(OpenAIJSON.string)),
        ])
        guard let batchID = batch["id"].string else { throw OpenAIFailure(kind: .invalidResponse) }
        var status = batch
        for attempt in 0..<maximumPolls {
            try Task.checkCancellation()
            if status["status"] == "completed" {
                guard status["file_counts"]["completed"].int == files.count,
                    status["file_counts"]["failed"].int == 0, status["file_counts"]["cancelled"].int == 0
                else { throw OpenAIFileLibraryFailure.indexing }
                collection.ready = true
                await onUpdate(collection)
                return collection
            }
            guard status["status"] == "in_progress" else { throw OpenAIFileLibraryFailure.indexing }
            guard attempt + 1 < maximumPolls else { break }
            try await Task.sleep(for: pollInterval)
            status = try await api.request(["vector_stores", id, "file_batches", batchID], method: "GET")
        }
        throw OpenAIFileLibraryFailure.indexingTimeout
    }

    func remove(_ original: OpenAIFileCollection,
                onUpdate: @MainActor @Sendable (OpenAIFileCollection) -> Void) async throws {
        var collection = original
        collection.ready = false
        await onUpdate(collection)
        if !collection.storeDeleted {
            try await delete(["vector_stores", collection.id])
            collection.storeDeleted = true
            await onUpdate(collection)
        }
        for id in original.fileIDs {
            try await delete(["files", id])
            collection.fileIDs.removeAll { $0 == id }
            await onUpdate(collection)
        }
    }

    private func delete(_ path: [String]) async throws {
        do { _ = try await api.request(path, method: "DELETE") } catch let failure as OpenAIFailure where failure.status == 404 {
        }
    }

    static func read(_ url: URL) throws -> OpenAIUpload {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard extensions.contains(url.pathExtension.lowercased()),
            try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw OpenAIFileLibraryFailure.invalidFiles }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 20 * 1_024 * 1_024 + 1) ?? Data()
        guard !data.isEmpty, data.count <= 20 * 1_024 * 1_024 else { throw OpenAIFileLibraryFailure.invalidFiles }
        return .init(field: "file", filename: url.lastPathComponent,
            mimeType: UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream", data: data)
    }

    static func read(_ urls: [URL]) throws -> [OpenAIUpload] {
        guard !urls.isEmpty, urls.count <= 10 else { throw OpenAIFileLibraryFailure.invalidFiles }
        var files: [OpenAIUpload] = []
        var bytes = 0
        for url in urls {
            try Task.checkCancellation()
            let file = try read(url)
            bytes += file.data.count
            guard bytes <= 40 * 1_024 * 1_024 else { throw OpenAIFileLibraryFailure.invalidFiles }
            files.append(file)
        }
        return files
    }
}

nonisolated enum OpenAIFileLibraryFailure: String, LocalizedError {
    case invalidFiles, indexing, indexingTimeout, unavailableCollection
    var errorDescription: String? {
        switch self {
        case .invalidFiles:
            String(localized: "Choose up to 10 supported documents, at most 20 MB each and 40 MB total.")
        case .indexing:
            String(localized: "OpenAI could not index every file. Delete the incomplete collection and try again.")
        case .indexingTimeout:
            String(localized: "Indexing did not finish in time. Delete the incomplete collection and try again.")
        case .unavailableCollection:
            String(localized: "A file search collection is incomplete or expired. Turn off Use in chat for it, or upload the documents again in OpenAI settings.")
        }
    }
}

enum OpenAIFileCollectionStore {
    nonisolated static func load(binding: String) -> [OpenAIFileCollection] {
        guard let data = UserDefaults.standard.data(forKey: "openai.fileCollections." + binding) else { return [] }
        return (try? JSONDecoder().decode([OpenAIFileCollection].self, from: data)) ?? []
    }
    static func update(_ collection: OpenAIFileCollection, binding: String) {
        var values = load(binding: binding)
        values.removeAll { $0.id == collection.id }
        values.append(collection)
        save(values, binding: binding)
    }
    static func remove(_ id: String, binding: String) {
        save(load(binding: binding).filter { $0.id != id }, binding: binding)
    }
    private static func save(_ values: [OpenAIFileCollection], binding: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(values), forKey: "openai.fileCollections." + binding)
    }
}
