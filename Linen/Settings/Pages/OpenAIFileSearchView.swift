// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct OpenAIFileSearchView: View {
    let providerID: String
    @Binding var tools: [OpenAIJSON]
    @State private var collections: [OpenAIFileCollection] = []
    @State private var operation: Task<Void, Never>?
    @State private var busy = false
    @State private var status: String?
    @State private var failure: String?
    @State private var binding = ""
    @State private var library: OpenAIFileLibrary?

    @State private var deleting: OpenAIFileCollection?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add documents, then ask your assistant questions about them in chat.")
                .font(.callout).foregroundStyle(.secondary)
            if collections.isEmpty {
                SettingsCard {
                    VStack(spacing: 10) {
                        Image(systemName: "doc.text.magnifyingglass").font(.system(size: 30)).foregroundStyle(.secondary)
                        Text("No documents yet").font(.headline)
                        Text("Choose PDFs, text files, or other supported documents.")
                            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity).padding(.vertical, 28)
                }
            } else {
                SettingsCard {
                    ForEach(collections) { collection in
                        HStack(spacing: 12) {
                            Image(systemName: "doc.text").foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(collection.name).lineLimit(2)
                                Text(collection.isAvailable() ? "Ready to search" : "Expired or incomplete — add the documents again")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("Use in chat", isOn: Binding(
                                get: { contains(collection.id) },
                                set: { enabled in
                                    guard connectionIsCurrent(binding) else { connect(); return }
                                    tools = OpenAIFileLibrary.select(collection.id, enabled: enabled, tools: tools)
                                }
                            )).toggleStyle(.switch).controlSize(.small)
                                .disabled(busy || (!collection.isAvailable() && !contains(collection.id)))
                            Menu {
                                Button("Delete Documents…", role: .destructive) { deleting = collection }
                            } label: { Image(systemName: "ellipsis") }
                            .menuStyle(.borderlessButton).fixedSize().disabled(busy)
                            .accessibilityLabel("Document actions")
                        }.padding(.vertical, 14)
                        if collection.id != collections.last?.id {
                            RowSeparator()
                        }
                    }
                }
            }
            HStack {
                SettingsButton(title: "Add Documents…", isProminent: true, symbol: "plus", action: chooseFiles)
                    .disabled(busy || library == nil)
                if busy {
                    ProgressView().controlSize(.small)
                    SettingsButton(title: "Cancel") { operation?.cancel() }
                }
            }
            if let status {
                Text(status).font(.callout).foregroundStyle(.secondary)
            }
            if let failure {
                Text(failure).font(.callout).foregroundStyle(.red).textSelection(.enabled)
            }
            Text("Documents are uploaded to OpenAI. Storage and search charges may apply. Files expire after 7 days; document groups expire after 7 inactive days.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .confirmationDialog("Delete these documents from OpenAI?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        ), titleVisibility: .visible) {
            Button("Delete Documents", role: .destructive) {
                if let deleting {
                    remove(deleting)
                }
                deleting = nil
            }
        } message: {
            Text("This removes the uploaded files in this group. The original files on your Mac are kept.")
        }
        .task(id: providerID) { connect() }
        .onDisappear { operation?.cancel() }
    }

    private func connect() {
        library = nil
        collections = []
        binding = ""
        failure = nil
        guard let provider = ProviderCatalog.shared.all.first(where: { $0.id == providerID }),
            let endpoint = provider.baseURL, let key = CredentialStore.key(for: provider), !key.isEmpty else {
            failure = String(localized: "Add an API key to upload documents.")
            return
        }
        binding = OpenAIConversationState.binding(endpoint: endpoint, model: "file-collections", credential: key)
        library = .init(api: .init(transport: OpenAIHTTPTransport(baseURL: endpoint, apiKey: key)))
        collections = OpenAIFileCollectionStore.load(binding: binding)
    }

    private func connectionIsCurrent(_ expected: String) -> Bool {
        guard let provider = ProviderCatalog.shared.all.first(where: { $0.id == providerID }),
            let endpoint = provider.baseURL, let key = CredentialStore.key(for: provider), !key.isEmpty else { return false }
        return expected == OpenAIConversationState.binding(endpoint: endpoint, model: "file-collections", credential: key)
    }

    private func contains(_ id: String) -> Bool {
        tools.contains { $0["type"] == "file_search" && $0["vector_store_ids"].array?.contains(.string(id)) == true }
    }

    private func chooseFiles() {
        guard !busy, let library else { return }
        guard connectionIsCurrent(binding) else { connect(); return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = OpenAIFileLibrary.extensions.sorted().compactMap { UTType(filenameExtension: $0) }
        busy = true
        failure = nil
        let binding = binding
        operation = Task {
            defer { busy = false; status = nil; operation = nil }
            guard await panel.begin() == .OK else { return }
            var pending: OpenAIFileCollection?
            do {
                try Task.checkCancellation()
                guard panel.urls.count <= 10 else { throw OpenAIFileLibraryFailure.invalidFiles }
                let urls = panel.urls
                let files = try await Task.detached { try OpenAIFileLibrary.read(urls) }.value
                try Task.checkCancellation()
                guard connectionIsCurrent(binding) else { throw CancellationError() }
                status = String(localized: "Uploading and indexing documents…")
                let created = try await library.create(name: files.first?.filename ?? "Documents", files: files) { value in
                    pending = value
                    OpenAIFileCollectionStore.update(value, binding: binding)
                    collections = OpenAIFileCollectionStore.load(binding: binding)
                    if !connectionIsCurrent(binding) {
                        operation?.cancel()
                    }
                }
                try Task.checkCancellation()
                guard connectionIsCurrent(binding) else { throw CancellationError() }
                tools = OpenAIFileLibrary.select(created.id, enabled: true, tools: tools)
            } catch {
                failure = error is CancellationError ? String(localized: "Upload canceled.") : error.localizedDescription
                if let pending {
                    do {
                        try await Task.detached {
                            try await library.remove(pending) { value in
                                OpenAIFileCollectionStore.update(value, binding: binding)
                            }
                        }.value
                        OpenAIFileCollectionStore.remove(pending.id, binding: binding)
                    } catch {
                        failure = String(localized: "Some uploaded files could not be removed. Use Delete to retry.")
                    }
                    collections = OpenAIFileCollectionStore.load(binding: binding)
                }
            }
        }
    }

    private func remove(_ collection: OpenAIFileCollection) {
        guard !busy, let library else { return }
        guard connectionIsCurrent(binding) else { connect(); return }
        tools = OpenAIFileLibrary.select(collection.id, enabled: false, tools: tools)
        busy = true
        failure = nil
        let binding = binding
        operation = Task {
            defer { busy = false; operation = nil }
            do {
                try await library.remove(collection) { value in
                    OpenAIFileCollectionStore.update(value, binding: binding)
                    collections = OpenAIFileCollectionStore.load(binding: binding)
                }
                OpenAIFileCollectionStore.remove(collection.id, binding: binding)
            } catch {
                failure = String(localized: "The collection could not be fully deleted. Use Delete to retry.")
            }
            collections = OpenAIFileCollectionStore.load(binding: binding)
        }
    }
}
