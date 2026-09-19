// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

extension AppCoordinator {
    func configureVoice(for provider: Provider) {
        let options = OpenAISettingsStore.load(providerID: provider.id).voice
        let key = CredentialStore.key(for: provider) ?? ""
        let usesOpenAI = provider.adapter == .openAIResponses && options.usesOpenAI
        let identity: String
        if usesOpenAI, let endpoint = provider.baseURL {
            identity = OpenAIConversationState.binding(endpoint: endpoint, model: provider.id, credential: key)
                + ((try? OpenAIJSON.encode(options).text()) ?? "")
        } else {
            identity = "apple:" + provider.id
        }
        guard voiceConfigurationID != identity else { return }
        endVoiceConversation()
        conversationVoice = nil
        voiceConfigurationID = identity
        voicePreparation?.cancel()
        voiceInput.cancel()
        speech.stopSpeaking()
        let transcriber: any TranscriberEngine
        if usesOpenAI, let endpoint = provider.baseURL {
            let client = OpenAIVoiceClient(endpoint: endpoint, key: key, settings: options)
            transcriber = OpenAITranscriberEngine(client: client)
            let output = OpenAISpeechOutput(client: client)
            output.onFailure = { [weak self] in
                self?.statusMessage = String(localized: "Couldn’t play the OpenAI voice. Check your voice settings and connection.")
            }
            speech.use(output)
        } else {
            transcriber = AppleTranscriberEngine()
            speech.use(AppleSpeechOutput())
        }
        voicePreparation = Task { [weak self] in
            guard let self else { return }
            do {
                try await voiceInput.useTranscriber(transcriber)
                guard !Task.isCancelled else { return }
                if statusMessage == Self.speechNotReadyMessage {
                    statusMessage = nil
                }
            } catch {
                guard !Task.isCancelled else { return }
                statusMessage = String(localized: "Couldn’t prepare voice input. Check your voice settings.")
            }
        }
    }
}

extension AppCoordinator {
    var supportsVoiceConversation: Bool {
        let provider = activeProvider ?? selectedProvider
        return provider.adapter == .openAIResponses && OpenAISettingsStore.load(providerID: provider.id).voice.usesOpenAI
    }

    func startVoiceConversation() {
        guard supportsVoiceConversation else { return }
        isVoiceConversationPresented = true
        voiceConversationMessage = nil
        guard conversationVoice?.isActive != true else { return }
        conversationVoice = nil
        guard microphoneIsReady() else {
            voiceConversationMessage = statusMessage ?? Self.microphoneDeniedMessage
            return
        }
        let provider = activeProvider ?? selectedProvider
        guard let endpoint = provider.baseURL, let key = CredentialStore.key(for: provider), !key.isEmpty else {
            statusMessage = String(localized: "Add an OpenAI API key in Settings to start a voice conversation.")
            voiceConversationMessage = statusMessage
            return
        }
        voiceInput.cancel()
        speech.stopSpeaking()
        agentTurns.cancel()
        mcpServer.cancelActiveCall()
        let tab = browser.ensureActiveTab()
        let spaceID = browser.spaceID(of: tab.id)
        conversationSpaceID = spaceID
        let settings = OpenAISettingsStore.load(providerID: provider.id).voice
        let conversation = OpenAIRealtimeConversation(
            settings: settings,
            connect: OpenAIRealtimeConversation.connection(endpoint: endpoint, key: key, model: settings.conversationModel)
        ) { [weak self] request in
            guard let self, browser.activeSpaceID == spaceID else { throw CancellationError() }
            mcpServer.cancelActiveCall()
            let result = try await agentTurns.perform(utterance: request)
            let state = conversationLog.traces.first { $0.id == result.taskID }?.state.rawValue ?? "unknown"
            let output: OpenAIJSON = ["state": .string(state), "result": .string(result.text)]
            return try output.text()
        }
        conversation.onTranscriptChanged = conversationLog.voiceTranscriptWriter(tabID: spaceID, providerID: provider.id)
        conversation.onUsage = { [weak self] usage in
            self?.conversationLog.recordUsage(
                tabID: spaceID, input: max(0, usage["input_tokens"].int ?? 0),
                cached: max(0, usage["input_token_details"]["cached_tokens"].int ?? 0),
                output: max(0, usage["output_tokens"].int ?? 0)
            )
        }
        conversationVoice = conversation
        isVoiceConversationPresented = true
        conversation.start()
    }

    func endVoiceConversation() {
        conversationVoice?.stop()
        conversationLog.saveNow()
        isVoiceConversationPresented = false
        voiceConversationMessage = nil
    }
}
