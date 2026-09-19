// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation

nonisolated struct OpenAIUtilityModel: LanguageModel {
    typealias UnavailableReason = Never
    let client: OpenAIResponsesClient
    let maxTokens: Int

    func respond<Content>(
        within session: LanguageModelSession, to prompt: Prompt, generating type: Content.Type,
        includeSchemaInPrompt: Bool, options: GenerationOptions
    ) async throws -> LanguageModelSession.Response<Content> where Content: Generable {
        guard session.tools.isEmpty else { throw OpenAIFailure(kind: .configuration) }
        let state = try client.restoring(nil).synchronizing(session.transcript)
        var body = try client.body(
            state: state, instructions: OpenAIConversationState.instructions(session.transcript), tools: [], maxTokens: maxTokens)
        if type != String.self {
            if body["text"].object == nil {
                body["text"] = [:]
            }
            body["text"]["format"] = [
                "type": "json_schema", "name": "result", "strict": true,
                "schema": try OpenAISchema.wrappedValue(type),
            ]
        }
        let response = try await client.api.createResponse(body) { _ in }
        guard response["status"].string == "completed" else { throw OpenAIFailure(kind: .incomplete) }
        let output = try OpenAIModelStep.output(response)
        guard output.calls.isEmpty else { throw OpenAIFailure(kind: .unsupportedAction) }
        let raw =
            type == String.self
            ? GeneratedContent(output.text)
            : try GeneratedContent(json: OpenAIJSON.decode(Data(output.text.utf8))["value"].text())
        let content = try type.init(raw)
        let entry = Transcript.Entry.response(.init(assetIDs: [], segments: [.text(.init(content: output.text))]))
        return .init(content: content, rawContent: raw, transcriptEntries: [entry][...])
    }

    func streamResponse<Content>(
        within session: LanguageModelSession, to prompt: Prompt, generating type: Content.Type,
        includeSchemaInPrompt: Bool, options: GenerationOptions
    ) -> sending LanguageModelSession.ResponseStream<Content> where Content: Generable {
        let stream = AsyncThrowingStream<LanguageModelSession.ResponseStream<Content>.Snapshot, any Error> { continuation in
            let task = Task {
                do {
                    let result = try await respond(
                        within: session, to: prompt, generating: type, includeSchemaInPrompt: includeSchemaInPrompt, options: options)
                    continuation.yield(.init(content: result.content.asPartiallyGenerated(), rawContent: result.rawContent))
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return .init(stream: stream)
    }
}
