// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

struct OllamaContextProbeTests {
    @Test func aRunningModelReportsItsLoadedContextLength() {
        let payload = Data("""
        {"models":[
            {"name":"llama3.1:latest","model":"llama3.1:latest","context_length":8192},
            {"name":"qwen3.5:latest","model":"qwen3.5:latest","context_length":32768}
        ]}
        """.utf8)

        #expect(OllamaContextProbe.window(inRunningModels: payload, model: "qwen3.5") == 32_768)
        #expect(OllamaContextProbe.window(inRunningModels: payload, model: "qwen3.5:latest") == 32_768)
        #expect(OllamaContextProbe.window(inRunningModels: payload, model: "llama3.1") == 8_192)
        #expect(OllamaContextProbe.window(inRunningModels: payload, model: "mistral") == nil)
    }

    @Test func aModelfileNumCtxIsReadFromShow() {
        let payload = Data("""
        {"parameters":"num_ctx                        16384\\nstop                           \\"<|im_end|>\\"",
         "model_info":{"qwen2.context_length":131072}}
        """.utf8)

        #expect(OllamaContextProbe.window(inShowResponse: payload) == 16_384)
    }

    @Test func theModelMaximumIsNotMistakenForTheEffectiveWindow() {
        let payload = Data("""
        {"parameters":"stop \\"<|im_end|>\\"","model_info":{"qwen2.context_length":131072}}
        """.utf8)

        #expect(OllamaContextProbe.window(inShowResponse: payload) == nil)
    }

    @Test func theNativeAPIBaseDropsTheOpenAISuffix() {
        let provider = Provider(
            id: "ollama",
            name: "Ollama",
            blurb: "",
            symbol: "desktopcomputer",
            baseURL: URL(string: "http://localhost:11434/v1"),
            wire: .chatCompletions,
            auth: .none,
            isLocal: true
        )

        #expect(
            OllamaContextProbe.nativeAPIBase(of: provider)?.absoluteString
                == "http://localhost:11434"
        )
    }
}
