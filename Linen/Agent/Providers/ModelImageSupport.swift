// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation

nonisolated enum ModelImageSupport {
    static func acceptsImages(for provider: Provider, model: String) -> Bool {
        guard !provider.isOnDevice else { return false }
        return LLMSettings.defaults.object(forKey: key(provider, model)) as? Bool ?? true
    }

    static func record(_ supported: Bool, for provider: Provider, model: String) {
        LLMSettings.defaults.set(supported, forKey: key(provider, model))
    }

    private static func key(_ provider: Provider, _ model: String) -> String {
        "llm.imageInput.\(provider.id).\(provider.baseURL?.absoluteString ?? "").\(model)"
    }

    static func declaredSupport(in entry: [String: Any]) -> Bool? {
        if let architecture = entry["architecture"] as? [String: Any],
           let inputs = architecture["input_modalities"] as? [String], !inputs.isEmpty {
            return inputs.contains("image")
        }
        if let capabilities = entry["capabilities"] as? [String: Any], let vision = capabilities["vision"] as? Bool {
            return vision
        }
        return nil
    }

    static func isImageRejection(_ error: any Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        let mentionsImages = ["image", "vision", "multimodal", "multi-modal"].contains { message.contains($0) }
        let unsupported = [
            "does not support", "doesn't support", "not supported", "unsupported", "not support",
            "only supports text", "text-only", "not a multimodal", "not a vision",
        ].contains { message.contains($0) }
        let invalidFile = ["image format", "image size", "invalid image", "mime", "encoding", "base64"].contains {
            message.contains($0)
        }
        return mentionsImages && unsupported && !invalidFile
    }

    static func containsImages(_ transcript: Transcript) -> Bool {
        transcript.contains { entry in
            guard case .prompt(let prompt) = entry else { return false }
            return prompt.segments.contains {
                if case .image = $0 {
                    return true
                }
                return false
            }
        }
    }

    static func textOnly(_ transcript: Transcript) -> Transcript {
        Transcript(entries: transcript.map { entry in
            guard case .prompt(var prompt) = entry else { return entry }
            let filtered = prompt.segments.filter {
                if case .image = $0 {
                    return false
                }
                return true
            }
            guard filtered.count != prompt.segments.count else { return entry }
            prompt.segments = filtered + [.text(.init(content: "Only extracted text is available for these attachments; visual details are unavailable."))]
            return .prompt(prompt)
        })
    }
}
