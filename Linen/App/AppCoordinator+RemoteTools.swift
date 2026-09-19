// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

extension AppCoordinator {
    func configureRemoteTools(for provider: Provider) {
        let settings = OpenAISettingsStore.load(providerID: provider.id)
        let identity: String
        if provider.adapter == .openAIResponses, !settings.mcpServers.isEmpty, let endpoint = provider.baseURL {
            let tokens = settings.mcpServers.map {
                CredentialStore.mcpAuthorization(providerID: provider.id, serverID: $0.id) ?? ""
            }.joined(separator: "\u{0}")
            identity = OpenAIConversationState.binding(
                endpoint: endpoint, model: (try? OpenAIJSON.encode(settings.mcpServers).text()) ?? "",
                credential: (CredentialStore.key(for: provider) ?? "") + "\u{0}" + tokens
            )
        } else {
            identity = "none"
        }
        if let previous = remoteToolConfigurationID, previous != identity {
            stopAgent()
        }
        remoteToolConfigurationID = identity
    }
}
