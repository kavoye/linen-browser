// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation
import ImageIO

@testable import Linen

@MainActor
enum OpenAIHostedLiveChecks {
    static func webSearch(_ client: OpenAIResponsesClient) async throws -> OpenAIJSON {
        let step = try await respond(client, tool: ["type": "web_search"], prompt:
            "Search the web for OpenAI Responses API documentation. Give one official documentation link with a citation.")
        let calls = step.state.items.filter { $0["type"] == "web_search_call" }
        let sources = step.state.presentation?.sources ?? []
        guard calls.contains(where: { $0["status"] == "completed" }),
            sources.contains(where: { ["developers.openai.com", "platform.openai.com"].contains($0.url.host ?? "") })
        else { throw OpenAIHostedLiveFailure.citation }
        return ["completed_calls": .integer(Int64(calls.count)), "cited_sources": .integer(Int64(sources.count))]
    }

    static func codeInterpreter(_ client: OpenAIResponsesClient) async throws -> OpenAIJSON {
        let container = try await client.api.request(["containers"], body: ["name": "linen-live-acceptance"])
        guard let id = container["id"].string else { throw OpenAIHostedLiveFailure.container }
        let result: Result<OpenAIJSON, any Error>
        do {
            result = .success(try await validateCodeArtifact(client, containerID: id))
        } catch {
            result = .failure(error)
        }
        do {
            _ = try await client.api.request(["containers", id], method: "DELETE")
        } catch {
            throw OpenAIHostedLiveFailure.cleanup
        }
        var metrics = try result.get()
        metrics["container_deleted"] = true
        return metrics
    }

    private static func validateCodeArtifact(_ client: OpenAIResponsesClient, containerID: String) async throws -> OpenAIJSON {
        let step = try await respond(client, tool: ["type": "code_interpreter", "container": .string(containerID)], prompt:
            "Use Python to calculate 17 * 19. Write /mnt/data/linen-result.csv with exactly two rows: "
            + "a,b,product and 17,19,323 (comma-separated, no spaces). Provide a download link to the CSV.")
        guard step.state.items.contains(where: {
            $0["type"] == "code_interpreter_call" && $0["status"] == "completed" && $0["container_id"].string == containerID
        }), let file = step.state.presentation?.files.first(where: {
            $0.containerID == containerID && URL(fileURLWithPath: $0.name).lastPathComponent == "linen-result.csv"
        }) else { throw OpenAIHostedLiveFailure.fileCitation }
        let downloaded = try await client.api.download(file)
        let text = String(data: downloaded.data, encoding: .utf8)?.replacingOccurrences(of: "\r\n", with: "\n")
        guard text?.trimmingCharacters(in: .whitespacesAndNewlines) == "a,b,product\n17,19,323" else {
            throw OpenAIHostedLiveFailure.fileContents
        }
        return ["downloaded_bytes": .integer(Int64(downloaded.data.count)), "csv_contents_verified": true]
    }

    static func imageGeneration(_ client: OpenAIResponsesClient) async throws -> OpenAIJSON {
        let step = try await respond(client,
            tool: ["type": "image_generation", "quality": "low", "size": "1024x1024", "output_format": "png"],
            prompt: "Generate one image: a solid blue circle on white.")
        guard step.state.items.contains(where: { $0["type"] == "image_generation_call" && $0["status"] == "completed" }),
            let picture = step.state.presentation?.pictures.first,
            let source = CGImageSourceCreateWithData(picture.data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil), image.width == 1_024, image.height == 1_024
        else { throw OpenAIHostedLiveFailure.imageDecode }
        return [
            "decoded_bytes": .integer(Int64(picture.data.count)), "width": .integer(Int64(image.width)),
            "height": .integer(Int64(image.height)), "format": .string(picture.format), "image_decoded": true,
        ]
    }

    private static func respond(_ client: OpenAIResponsesClient, tool: OpenAIJSON, prompt: String) async throws -> OpenAIModelStep {
        var hosted = client
        hosted.settings.hostedTools = [tool]
        hosted.settings.additionalParameters = ["tool_choice": "required", "max_tool_calls": 1]
        return try await hosted.respond(transcript: Transcript(), prompt: prompt, images: [],
            state: hosted.restoring(nil), tools: [], maxTokens: 2_048, onText: { _ in })
    }
}

nonisolated enum OpenAIHostedLiveFailure: String, Error {
    case citation, container, cleanup, fileCitation, fileContents, imageDecode
}
