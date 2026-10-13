// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os

extension AppCoordinator {
    func engine(for configuration: Provider) -> any ModelProvider {
        modelProviders.resolve(configuration)
    }

    func configureEngines() {
        LLMSettings.$scoped.withValue(modelSettings) {
            configureWindowEngines()
        }
    }

    func reloadAssistantConfiguration() {
        let targets = application?.windows.filter { $0.browser.context === browser.context } ?? [self]
        targets.forEach { $0.configureEngines() }
    }

    private func configureWindowEngines() {
        linkPeek.canPreviewPullRequests = { [weak self] in
            guard let self else { return false }
            return settings.showsGitHub && github.canPreview
        }
        linkPeek.previewPullRequest = { [weak self] reference in
            await self?.github.preview(reference)
        }
        linkPeek.makeModel = { [weak self] in
            guard let self else { return UtilityModelSource.onDevice() }
            let selected = modelProviders.resolve(engine.selectedProvider)
            if let model = selected.makeUtilityModel(
                model: modelSettings.model(for: selected.configuration)
            ) {
                return model
            }
            return UtilityModelSource.onDevice()
        }
        let toolkit = AgentToolkit(
            browser: browser,
            media: media,
            log: conversationLog,
            questions: agentQuestions
        )
        agentTurns.onCancel = { [weak self] in self?.agentQuestions.abandon() }
        engine.selectedProvider = ProviderCatalog.shared.selected
        engine.selectedModel = LLMSettings.model(for: engine.selectedProvider)
        engine.selectedEffort = ReasoningCatalog.resolve(
            LLMSettings.reasoningEffort(for: engine.selectedProvider),
            for: engine.selectedProvider,
            model: engine.selectedModel
        )

        let selected = modelProviders.resolve(engine.selectedProvider)
        engine.supportsReasoningEffort = selected.capabilities.contains(.reasoning)
        let onDeviceFallback = modelProviders.resolve(ProviderCatalog.appleOnDevice)
        let hostedFallback = modelProviders.resolve(ProviderCatalog.openAI)
        let decision = AgentProviderSelection.decide(
            selected: AgentProviderCandidate(
                configuration: selected.configuration,
                availability: selected.availability
            ),
            onDeviceFallback: AgentProviderCandidate(
                configuration: onDeviceFallback.configuration,
                availability: onDeviceFallback.availability
            ),
            hostedFallback: AgentProviderCandidate(
                configuration: hostedFallback.configuration,
                availability: hostedFallback.availability
            )
        )

        func use(_ provider: any ModelProvider) {
            let configuration = provider.configuration
            let built = provider.makeAgent(
                model: LLMSettings.model(for: configuration),
                reasoningEffort: LLMSettings.reasoningEffort(for: configuration),
                toolkit: toolkit,
                log: conversationLog
            )
            built.prepare()
            agentTurns.use(built)
            engine.activeProvider = configuration
            engine.isUsingSelectedProvider = configuration.id == engine.selectedProvider.id
        }

        func unavailable() {
            agentTurns.use(nil)
            engine.activeProvider = nil
            engine.isUsingSelectedProvider = false
        }

        switch decision {
        case .use(let configuration, let notice):
            use(modelProviders.resolve(configuration))
            engine.activeNotice = notice
        case .unavailable(let message):
            engine.activeNotice = message
            unavailable()
        }
        statusMessage = selected.availability == .needsCredentials ? nil : engine.activeNotice
        configureRemoteTools(for: engine.activeProvider ?? engine.selectedProvider)
        configureVoice()
        Pipeline.log.notice("Assistant engine configured")
        discoverContextWindow()
    }

    private func discoverContextWindow() {
        guard let provider = engine.activeProvider, !provider.isOnDevice else { return }
        let context = browser.context
        let modelSettings = context.modelSettings
        let model = modelSettings.model(for: provider)
        guard !model.isEmpty,
              modelSettings.discoveredContextWindow(for: provider, model: model) == nil
        else { return }
        Task { [weak self] in
            guard let window = await ProviderContextProbe().effectiveWindow(
                    for: provider, model: model, apiKey: CredentialStore.key(for: provider)
                  ),
                  window != modelSettings.discoveredContextWindow(for: provider, model: model)
            else { return }
            modelSettings.setDiscoveredContextWindow(window, for: provider, model: model)
            Pipeline.log.notice("Model context window discovered")
            guard let self, browser.context === context, !isClosed else { return }
            reloadAssistantConfiguration()
        }
    }
}
