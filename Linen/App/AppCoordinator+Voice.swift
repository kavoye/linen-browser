// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

extension AppCoordinator {
    var canUseOpenAIVoice: Bool {
        openAIVoiceProviderID != nil
    }

    func openAIVoiceCredentials() -> (provider: Provider, endpoint: URL, key: String)? {
        let candidates = [selectedProvider] + ProviderCatalog.shared.all.filter { $0.id != selectedProvider.id }
        for provider in candidates where provider.adapter == .openAIResponses {
            if let endpoint = provider.baseURL, let key = CredentialStore.key(for: provider), !key.isEmpty {
                return (provider, endpoint, key)
            }
        }
        return nil
    }

    func previewOpenAIVoice(_ voice: String) {
        let replaying = previewingVoice == voice
        stopVoicePreview()
        guard !replaying, let credentials = openAIVoiceCredentials() else { return }
        var settings = OpenAISettingsStore.load(providerID: credentials.provider.id).voice
        settings.voice = voice
        let output = OpenAISpeechOutput(
            client: OpenAIVoiceClient(endpoint: credentials.endpoint, key: credentials.key, settings: settings)
        )
        output.onSpeakingChange = { [weak self, weak output] speaking in
            guard let self, !speaking, voicePreview === output else { return }
            voicePreview = nil
            previewingVoice = nil
        }
        output.onFailure = { [weak self] in
            self?.statusMessage = String(localized: "Couldn’t play the OpenAI voice. Check your voice settings and connection.")
        }
        stopAgentSpeech()
        readerListener.stop()
        voicePreview = output
        previewingVoice = voice
        output.speak(String(localized: "Hi, I’m \(voice.capitalized). This is how I sound in Linen."))
    }

    func stopVoicePreview() {
        voicePreview?.stopSpeaking()
        voicePreview = nil
        previewingVoice = nil
    }

    func configureVoice() {
        let preferences = voicePreferences
        let credentials = openAIVoiceCredentials()
        let provider = credentials?.provider ?? selectedProvider
        openAIVoiceProviderID = credentials?.provider.id
        dictatesWithOpenAI = canUseOpenAIVoice && preferences.dictation == .openAI
        readsWithOpenAI = canUseOpenAIVoice && preferences.reading == .openAI
        let openAI: (endpoint: URL, key: String, options: OpenAIVoiceSettings)?
        if let credentials, dictatesWithOpenAI || readsWithOpenAI {
            openAI = (credentials.endpoint, credentials.key, OpenAISettingsStore.load(providerID: provider.id).voice)
        } else {
            openAI = nil
        }
        var identity = "apple:" + provider.id
        if let openAI {
            identity = OpenAIConversationState.binding(endpoint: openAI.endpoint, model: provider.id, credential: openAI.key)
                + ((try? OpenAIJSON.encode(openAI.options).text()) ?? "")
        }
        identity += "|\(dictatesWithOpenAI)|\(readsWithOpenAI)"
        guard voiceConfigurationID != identity else { return }
        endVoiceConversation()
        conversationVoice = nil
        voiceConfigurationID = identity
        voicePreparation?.cancel()
        voiceInput.cancel()
        speech.stopSpeaking()
        readerListener.stop()
        let client = openAI.map { OpenAIVoiceClient(endpoint: $0.endpoint, key: $0.key, settings: $0.options) }
        let transcriber: any TranscriberEngine
        if dictatesWithOpenAI, let client {
            transcriber = OpenAITranscriberEngine(client: client)
        } else {
            transcriber = AppleTranscriberEngine()
        }
        if readsWithOpenAI, let client {
            let output = OpenAISpeechOutput(client: client)
            output.onFailure = { [weak self] in
                self?.statusMessage = String(localized: "Couldn’t play the OpenAI voice. Check your voice settings and connection.")
            }
            speech.use(output)
            readerSpeech.setAssistantOutput { [weak self] in
                let readerOutput = OpenAISpeechOutput(client: client)
                readerOutput.onFailure = {
                    self?.readerListener.stop()
                    output.onFailure?()
                }
                return readerOutput
            }
        } else {
            speech.use(AppleSpeechOutput())
            readerSpeech.setAssistantOutput(nil)
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
        canUseOpenAIVoice && voicePreferences.allowsConversation
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
        guard let credentials = openAIVoiceCredentials() else {
            statusMessage = String(localized: "Add an OpenAI API key in Settings to start a voice conversation.")
            voiceConversationMessage = statusMessage
            return
        }
        let (provider, endpoint, key) = credentials
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
