// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

extension OpenAIResponseSettings {
    func forChat(endpoint: URL, model: String) -> Self {
        guard endpoint.scheme == "https", endpoint.host?.lowercased() == "api.openai.com",
              endpoint.port == nil || endpoint.port == 443,
              endpoint.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "v1" else { return self }
        var resolved = self
        resolved.useWebSocket = true
        resolved.useToolSearch = OpenAIToolSearch.supports(model) && !model.lowercased().contains("-pro")
        resolved.reasoningSummary = OpenAIModelSupport.reasoning(model)
        resolved.serviceTier = "auto"
        let model = model.lowercased()
        let supported = ["gpt-5.4", "gpt-5.5", "gpt-5.6-luna", "gpt-5.6-terra", "gpt-5.6-sol", "gpt-6-astra"]
        if supported.contains(where: { model == $0 || model.hasPrefix($0 + "-202") }) {
            let defaults: [OpenAIJSON] = [
                ["type": "web_search"],
                ["type": "code_interpreter", "container": ["type": "auto"]],
                ["type": "image_generation"],
            ]
            for tool in defaults {
                let type = tool["type"].string
                let present = resolved.hostedTools.contains {
                    $0["type"].string == type || (type == "web_search" && $0["type"].string == "web_search_preview")
                }
                if !present {
                    resolved.hostedTools.append(tool)
                }
            }
        }
        return resolved
    }
}
