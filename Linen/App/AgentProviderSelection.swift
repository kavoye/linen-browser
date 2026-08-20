// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

struct AgentProviderCandidate: Equatable {
    let configuration: Provider
    let availability: ModelProviderAvailability
}

enum AgentProviderDecision: Equatable {
    case use(Provider, notice: String?)
    case unavailable(String)
}

enum AgentProviderSelection {
    static func decide(
        selected: AgentProviderCandidate,
        onDeviceFallback: AgentProviderCandidate,
        hostedFallback: AgentProviderCandidate
    ) -> AgentProviderDecision {
        switch selected.availability {
        case .available:
            return .use(selected.configuration, notice: nil)

        case .needsCredentials:
            guard onDeviceFallback.availability == .available else {
                return .unavailable(
                    String(
                        localized: "Add an API key for \(selected.configuration.name) in Settings, or enable Apple Intelligence"
                    )
                )
            }
            return .use(
                onDeviceFallback.configuration,
                notice: String(
                    localized: "No \(selected.configuration.name) key yet, using Apple Intelligence"
                )
            )

        case .unavailable(let reason):
            if selected.configuration.isOnDevice {
                guard hostedFallback.availability == .available else {
                    return .unavailable(String(localized: "\(reason). Pick another provider in Settings."))
                }
                return .use(
                    hostedFallback.configuration,
                    notice: String(localized: "Apple Intelligence unavailable, using OpenAI")
                )
            }

            guard onDeviceFallback.availability == .available else {
                return .unavailable(String(localized: "\(reason). Pick another provider in Settings."))
            }
            return .use(
                onDeviceFallback.configuration,
                notice: String(
                    localized: "\(selected.configuration.name) unavailable, using Apple Intelligence"
                )
            )
        }
    }
}
