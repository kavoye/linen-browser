// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

@MainActor
struct AgentProviderSelectionTests {
    private let apple = ProviderCatalog.appleOnDevice
    private let openAI = ProviderCatalog.openAI

    @Test func availableSelectionRunsWithoutANotice() {
        let decision = decide(selected: candidate(openAI, .available))

        #expect(decision == .use(openAI, notice: nil))
    }

    @Test func missingCredentialsUseTheOnDeviceFallback() {
        let custom = provider(id: "hosted", name: "Hosted Models")

        let decision = decide(
            selected: candidate(custom, .needsCredentials),
            apple: candidate(apple, .available)
        )

        #expect(
            decision == .use(
                apple,
                notice: "No Hosted Models key yet, using Apple Intelligence"
            )
        )
    }

    @Test func missingCredentialsExplainHowToRecoverWhenNoFallbackIsReady() {
        let custom = provider(id: "hosted", name: "Hosted Models")

        let decision = decide(
            selected: candidate(custom, .needsCredentials),
            apple: candidate(apple, .unavailable("Not supported"))
        )

        #expect(
            decision == .unavailable(
                "Add an API key for Hosted Models in Settings, or enable Apple Intelligence"
            )
        )
    }

    @Test func unavailableOnDeviceSelectionUsesTheHostedFallback() {
        let decision = decide(
            selected: candidate(apple, .unavailable("Not supported")),
            openAI: candidate(openAI, .available)
        )

        #expect(
            decision == .use(
                openAI,
                notice: "Apple Intelligence unavailable, using OpenAI"
            )
        )
    }

    @Test func unavailableHostedSelectionUsesTheOnDeviceFallback() {
        let custom = provider(id: "hosted", name: "Hosted Models")

        let decision = decide(
            selected: candidate(custom, .unavailable("Service offline")),
            apple: candidate(apple, .available)
        )

        #expect(
            decision == .use(
                apple,
                notice: "Hosted Models unavailable, using Apple Intelligence"
            )
        )
    }

    @Test func unavailableSelectionKeepsTheReasonWhenNoFallbackIsReady() {
        let custom = provider(id: "hosted", name: "Hosted Models")

        let decision = decide(
            selected: candidate(custom, .unavailable("Service offline")),
            apple: candidate(apple, .needsCredentials)
        )

        #expect(decision == .unavailable("Service offline. Pick another provider in Settings."))
    }

    private func decide(
        selected: AgentProviderCandidate,
        apple: AgentProviderCandidate? = nil,
        openAI: AgentProviderCandidate? = nil
    ) -> AgentProviderDecision {
        AgentProviderSelection.decide(
            selected: selected,
            onDeviceFallback: apple ?? candidate(self.apple, .unavailable("Unavailable")),
            hostedFallback: openAI ?? candidate(self.openAI, .needsCredentials)
        )
    }

    private func candidate(
        _ configuration: Provider,
        _ availability: ModelProviderAvailability
    ) -> AgentProviderCandidate {
        AgentProviderCandidate(configuration: configuration, availability: availability)
    }

    private func provider(id: String, name: String) -> Provider {
        Provider(
            id: id,
            name: name,
            blurb: "",
            symbol: "server.rack",
            baseURL: URL(string: "https://models.example/v1"),
            wire: .chatCompletions,
            auth: .bearer
        )
    }
}
