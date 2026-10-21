// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import os

extension AppCoordinator {
    // MARK: - Voice input

    static let speechNotReadyMessage = String(localized: "Speech recognition is starting. Try again shortly.")

    static let microphoneDeniedMessage = String(
        localized: "Allow Linen to use the microphone under Privacy & Security > Microphone."
    )

    func microphoneIsReady() -> Bool {
        switch MicrophoneAccess.state {
        case .allowed:
            return true
        case .undecided:
            askForMicrophone()
            return false
        case .denied:
            statusMessage = Self.microphoneDeniedMessage
            MicrophoneAccess.openSystemSettings()
            return false
        }
    }

    func askForMicrophone() {
        guard !isAskingForMicrophone else { return }
        isAskingForMicrophone = true
        Task { [weak self] in
            let granted = await MicrophoneAccess.request()
            guard let self else { return }
            isAskingForMicrophone = false
            if granted, voiceConversation.isPresented {
                statusMessage = nil
                startVoiceConversation()
            } else if granted {
                statusMessage = String(localized: "Hold \(ActivationSettings.talk.phrase) again to speak.")
            } else {
                statusMessage = Self.microphoneDeniedMessage
                if voiceConversation.isPresented {
                    voiceConversation.message = statusMessage
                }
            }
        }
    }

    func handleVoiceFailure(_ failure: VoiceInputModel.Failure) {
        switch failure {
        case .notReady:
            statusMessage = Self.speechNotReadyMessage
        case .capture(let description):
            statusMessage = String(localized: "Couldn’t start the microphone: \(description)")
        case .transcription:
            statusMessage = String(localized: "Couldn’t transcribe the recording.")
        }
    }

    @discardableResult
    func runAgent(
        with utterance: String,
        mentionedTabIDs: [UUID] = [],
        attachments: [AssistantAttachment] = [],
        attachmentTextOnly: Bool = false,
        trace: LatencyTrace?,
        showsInChrome: Bool = true
    ) -> Bool {
        mcpServer.cancelActiveCall()
        let started = agentTurns.run(
            utterance: utterance,
            mentionedTabIDs: mentionedTabIDs,
            attachments: attachments,
            attachmentTextOnly: attachmentTextOnly,
            trace: trace,
            showsInChrome: showsInChrome
        )
        guard started else {
            statusMessage = "Add an API key for \(engine.selectedProvider.name) in Settings, or enable Apple Intelligence."
            voiceInput.clearTranscript()
            return false
        }
        return true
    }

    // MARK: - Typed input

    func continueAgent() {
        endVoiceConversation()
        voiceInput.cancel()
        speech.stopSpeaking()
        mcpServer.cancelActiveCall()
        agentTurns.run(utterance: "", isContinuation: true, showsInChrome: false)
    }

    @discardableResult
    func handleTypedUtterance(
        _ raw: String,
        mentionedTabIDs: [UUID] = [],
        attachments: [AssistantAttachment] = [],
        showsInChrome: Bool = true
    ) async -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachmentTextOnly = !ModelImageSupport.acceptsImages(for: engine.selectedProvider, model: engine.selectedModel)
        guard !text.isEmpty || !attachments.isEmpty else { return false }
        do {
            try AttachmentRequest.validate(
                attachments, message: text, textOnly: attachmentTextOnly,
                windowTokens: ContextWindow.tokens(for: engine.selectedProvider, model: engine.selectedModel)
            )
        } catch {
            statusMessage = error.localizedDescription
            return false
        }

        endVoiceConversation()
        voiceInput.cancel()
        speech.stopSpeaking()
        agentTurns.cancel()
        Pipeline.log.notice("Typed request received")
        return runAgent(
            with: text.isEmpty ? String(localized: "Read the attached files.") : text,
            mentionedTabIDs: mentionedTabIDs,
            attachments: attachments,
            attachmentTextOnly: attachmentTextOnly,
            trace: LatencyTrace(),
            showsInChrome: showsInChrome
        )
    }
}
