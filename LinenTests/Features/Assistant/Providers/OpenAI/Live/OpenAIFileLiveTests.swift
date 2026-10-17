// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import AppKit
import CoreText
import Foundation
import Testing

@testable import Linen

@MainActor
struct OpenAIFileLiveTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["LINEN_OPENAI_LIVE_CONFIG"] != nil))
    func nativePDFInput() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["LINEN_OPENAI_LIVE_CONFIG"])
        let config = try OpenAIJSON.decode(Data(contentsOf: URL(fileURLWithPath: path)))
        guard config["live"].bool == true, config["files_only"].bool == true else { return }
        let url = URL(fileURLWithPath: try #require(config["report_path"].string))
        let model = config["model"].string ?? LLMSettings.model(for: ProviderCatalog.openAI)
        let key = ProcessInfo.processInfo.environment["LINEN_OPENAI_LIVE_KEY"] ?? CredentialStore.key(for: ProviderCatalog.openAI)
        let recorder = OpenAILiveRecorder(requestLimit: 5)
        var report: OpenAIJSON = [
            "mode": "live_file_acceptance", "model": .string(model), "reasoning_effort": "low", "store": false,
            "max_requests": 5, "max_output_tokens_per_response": 2_048, "status": "running",
            "synthetic_prompts": true, "synthetic_usage": false, "competitive_score": false,
            "source_sha256": config["source_sha256"], "checks": [], "requests": [],
        ]
        func save() throws {
            report["requests"] = .array(recorder.snapshot)
            try report.data().write(to: url, options: .atomic)
        }
        guard let key, !key.isEmpty else {
            report["status"] = "blocked_missing_credential"
            try save()
            return
        }
        let endpoint = URL(string: "https://api.openai.com/v1")!
        let transport = OpenAILiveTransport(base: OpenAIHTTPTransport(baseURL: endpoint, apiKey: key), recorder: recorder)
        let client = OpenAIResponsesClient(endpoint: endpoint, apiKey: key, model: model, transport: transport)
        var checks: [OpenAIJSON] = []
        try save()
        do {
            recorder.select("native_pdf_input")
            let file = try AttachmentImporter.prepare(data: syntheticPDF(), name: "linen-marker.pdf")
            let input = try #require(try OpenAIAttachmentInput.make(prompt: "What exact document marker is written in this PDF?",
                attachments: [file], textOnly: false))
            let step = try await client.respond(transcript: Transcript(), prompt: "Read the attached PDF.", images: [],
                state: client.restoring(nil), tools: [], maxTokens: 2_048, attachmentInput: input, onText: { _ in })
            guard step.text.contains("MAPLE_85") else { throw OpenAILiveFailure.invariant }
            checks.append(["name": "native_pdf_input", "passed": true, "pdf_bytes": .integer(Int64(file.data.count))])
            report["checks"] = .array(checks)
            try save()

            report["status"] = "passed"
        } catch {
            report["status"] = "failed"
            report["error"] = .string(OpenAILiveRecorder.errorCode(error))
            Issue.record("Live file acceptance failed. See the sanitized report.")
        }
        try save()
    }

    private func syntheticPDF() throws -> Data {
        let data = NSMutableData()
        let consumer = try #require(CGDataConsumer(data: data))
        var bounds = CGRect(x: 0, y: 0, width: 600, height: 300)
        let context = try #require(CGContext(consumer: consumer, mediaBox: &bounds, nil))
        context.beginPDFPage(nil)
        context.textPosition = CGPoint(x: 30, y: 150)
        let text = NSAttributedString(string: "Linen document marker: MAPLE_85.", attributes: [.font: NSFont.systemFont(ofSize: 24)])
        CTLineDraw(CTLineCreateWithAttributedString(text), context)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }
}
