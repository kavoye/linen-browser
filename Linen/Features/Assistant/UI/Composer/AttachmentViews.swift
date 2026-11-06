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

enum AttachmentPreviewLayout {
    static let document = CGSize(width: 620, height: 520)
    static let header: CGFloat = 44

    private static let maximum = CGSize(width: 900, height: 640)
    private static let minimum = CGSize(width: 360, height: 200)

    static func fitted(_ image: CGSize) -> CGSize {
        guard image.width > 0, image.height > 0 else { return document }
        let scale = min(maximum.width / image.width, maximum.height / image.height, 1)
        return CGSize(
            width: max((image.width * scale).rounded(), minimum.width),
            height: max((image.height * scale).rounded(), minimum.height)
        )
    }
}

private struct AttachmentPreview: View {
    let file: AssistantAttachment
    @Environment(\.dismiss) private var dismiss
    @State private var hoveringClose = false

    private var picture: NSImage? {
        guard !file.isPDF, let data = file.images.first?.data else { return nil }
        return NSImage(data: data)
    }

    var body: some View {
        let picture = picture
        let size = picture.map { AttachmentPreviewLayout.fitted($0.size) } ?? AttachmentPreviewLayout.document
        VStack(spacing: 0) {
            header
            Divider()
            content(picture)
                .frame(width: size.width, height: size.height)
        }
    }

    @ViewBuilder
    private func content(_ picture: NSImage?) -> some View {
        if let picture {
            Image(nsImage: picture)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
                .accessibilityLabel(Text(verbatim: file.name))
        } else if file.isPDF {
            AttachmentPDFPreview(data: file.data)
        } else {
            ScrollView {
                Text(verbatim: file.text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(verbatim: file.name)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(hoveringClose ? .primary : .secondary)
                    .hoverLift(hoveringClose)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hoveringClose = $0 }
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Close")
            .help("Close")
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(height: AttachmentPreviewLayout.header)
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
        } else if isTextOnly, attachments.isRecognizing {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Reading text in attachments…").font(.caption).foregroundStyle(.secondary)
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
