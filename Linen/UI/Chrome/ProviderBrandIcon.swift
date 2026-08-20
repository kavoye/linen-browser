// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct ProviderBrandIcon: View {
    let providerID: String
    var size: CGFloat = 16

    private var assetName: String? {
        switch providerID {
        case "openai":
            "ProviderOpenAI"
        case "anthropic":
            "ProviderAnthropic"
        case "ollama":
            "ProviderOllama"
        case "lmstudio":
            "ProviderLMStudio"
        case "google":
            "ProviderGoogle"
        case "openrouter":
            "ProviderOpenRouter"
        case "groq":
            "ProviderGroq"
        case "xai":
            "ProviderXAI"
        case "deepseek":
            "ProviderDeepSeek"
        case "mistral":
            "ProviderMistral"
        default:
            nil
        }
    }

    var body: some View {
        ZStack {
            if providerID == ProviderCatalog.appleOnDevice.id {
                Image(systemName: "apple.logo")
                    .font(.system(size: size * 0.75))
                    .foregroundStyle(.secondary)
            } else if let assetName {
                Image(assetName)
                    .resizable()
                    .renderingMode(.original)
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "globe")
                    .font(.system(size: size * 0.7))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: size, height: size)
    }
}
