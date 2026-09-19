// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation

nonisolated enum AttachmentRequest {
    static func images(_ attachments: [AssistantAttachment], textOnly: Bool) -> [Transcript.ImageSegment] {
        guard !textOnly else { return [] }
        return attachments.flatMap(\.images).map { .init(data: $0.data, mimeType: $0.mimeType) }
    }

    static func validate(
        _ attachments: [AssistantAttachment], message: String, textOnly: Bool, windowTokens: Int
    ) throws {
        try AssistantAttachment.validate(attachments)
        guard !attachments.isEmpty else { return }
        if textOnly, attachments.contains(where: { !$0.images.isEmpty && $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            throw AttachmentFailure.message(String(localized: "No readable text was found in an image. Choose a model that can read images to send it."))
        }
        let characters = AssistantAttachment.prompt(message, attachments: attachments, textOnly: textOnly).count
        let imageTokens = textOnly ? 0 : attachments.reduce(0) { $0 + $1.images.count * 1_600 }
        guard characters / 3 + imageTokens < windowTokens / 2 else {
            throw AttachmentFailure.message(String(localized: "These attachments exceed this model’s context budget. Attach fewer pages or choose a model with a larger context window."))
        }
    }
}
