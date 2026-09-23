// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

struct ProviderContextProbeTests {
    @Test func modelMetadataUsesTheReportedLimit() {
        #expect(ProviderContextProbe.window(inModel: Data(#"{"max_input_tokens":200000,"max_tokens":8192}"#.utf8)) == 200_000)
        #expect(ProviderContextProbe.window(inModel: Data(#"{"inputTokenLimit":1048576,"outputTokenLimit":65536}"#.utf8)) == 1_048_576)
        #expect(ProviderContextProbe.window(inModel: Data(#"{"context_window":131072}"#.utf8)) == 131_072)
    }

    @Test func catalogMetadataMatchesTheSelectedModel() {
        let data = Data(#"{"data":[{"id":"other","context_length":8192},{"id":"selected","context_length":1048576}]}"#.utf8)
        #expect(ProviderContextProbe.window(inModelList: data, model: "selected") == 1_048_576)
        #expect(ProviderContextProbe.window(inModelList: data, model: "missing") == nil)
    }

    @Test func openAIModelMetadataWithoutALimitStaysUnknown() {
        let data = Data(#"{"data":[{"id":"gpt-6-luna","object":"model","owned_by":"openai"}]}"#.utf8)
        #expect(ProviderContextProbe.window(inModelList: data, model: "gpt-6-luna") == nil)
    }

    @Test func officialModelPageCanSupplyThePublishedLimit() {
        let html = Data("<main><div>1,050,000</div><span>context window</span><div>128,000 max output tokens</div></main>".utf8)
        #expect(ProviderContextProbe.window(inDocumentation: html) == 1_050_000)
        #expect(ProviderContextProbe.window(inDocumentation: Data("<main>No limit listed</main>".utf8)) == nil)
    }
}
