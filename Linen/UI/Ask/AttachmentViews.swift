// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import PDFKit
import SwiftUI

struct AttachmentList: View {
    let files: [AssistantAttachment]
    var onRemove: ((UUID) -> Void)?
    @State private var preview: AssistantAttachment?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(files) { file in
                    HStack(spacing: 6) {
                        Button { preview = file } label: {
                            AttachmentLabel(file: file)
                        }
                        .buttonStyle(.plain)
                        .help(Text("Preview \(file.name)"))
                        if let onRemove {
                            Button { onRemove(file.id) } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .semibold))
                                    .frame(width: 20, height: 24)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("Remove \(file.name)"))
                        }
                    }
                    .padding(6)
                    .background(Theme.Wash.hairline, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .scrollIndicators(.hidden)
        .sheet(item: $preview) { file in
            AttachmentPreview(file: file)
        }
    }
}

private struct AttachmentLabel: View {
    let file: AssistantAttachment

    var body: some View {
        HStack(spacing: 6) {
            if let bytes = file.images.first?.data, let image = NSImage(data: bytes) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 30)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: file.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(verbatim: ByteCountFormatter.string(fromByteCount: Int64(file.byteCount), countStyle: .file))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 150, alignment: .leading)
        }
        .contentShape(Rectangle())
    }
}

private struct AttachmentPreview: View {
    let file: AssistantAttachment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(verbatim: file.name).font(.headline).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if file.isPDF {
                AttachmentPDFPreview(data: file.data)
            } else if let image = file.images.first, let native = NSImage(data: image.data) {
                Image(nsImage: native).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    Text(verbatim: file.text)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(16)
        .frame(width: 620, height: 520)
    }
}

private struct AttachmentPDFPreview: NSViewRepresentable {
    let data: Data

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(data: data)
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {}
}

struct AttachmentComposerStatus: View {
    @Bindable var attachments: AttachmentDraft
    let isTextOnly: Bool

    var body: some View {
        if !attachments.files.isEmpty {
            AttachmentList(files: attachments.files) { id in
                attachments.files.removeAll { $0.id == id }
                attachments.error = nil
            }
            if isTextOnly, attachments.files.contains(where: { !$0.images.isEmpty }) {
                Text("This model can only read text. Visual details won’t be included.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        if attachments.isImporting {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Preparing attachments…").font(.caption).foregroundStyle(.secondary)
            }
        }
        if let error = attachments.error {
            HStack(alignment: .top) {
                Text(verbatim: error).font(.caption).foregroundStyle(.red)
                Spacer(minLength: 0)
                Button { attachments.error = nil } label: {
                    Image(systemName: "xmark").font(.caption)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss Error")
            }
        }
    }
}
