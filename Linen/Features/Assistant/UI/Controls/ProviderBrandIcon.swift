// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct ProviderBrandIcon: View {
    let providerID: String
    var size: CGFloat = 16
    var tint: Color?

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
                    .font(.system(size: size * 0.88))
                    .foregroundStyle(tint ?? .primary)
                    .offset(y: -size * 0.03)
            } else if let assetName {
                Image(assetName)
                    .resizable()
                    .renderingMode(tint == nil ? .original : .template)
                    .interpolation(.high)
                    .scaledToFit()
                    .foregroundStyle(tint ?? .primary)
            } else {
                Image(systemName: "globe")
                    .font(.system(size: size * 0.7))
                    .foregroundStyle(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.tertiary))
            }
        }
        .frame(width: size, height: size)
    }
}
