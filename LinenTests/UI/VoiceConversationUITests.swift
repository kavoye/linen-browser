// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI
import Testing

@testable import Linen

@MainActor
struct VoiceConversationUITests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["LINEN_VOICE_UI_TEST"] == "1"))
    func voiceModeAndComposerRemainUsable() async throws {
        let coordinator = AppCoordinator()
        coordinator.conversationLog.adopt(database: .temporary())
        let space = UUID()
        let socket = ConversationSocketFixture()
        let capture = ConversationCaptureFixture()
        capture.usesEchoCancellation = false
        let player = ConversationPlaybackFixture()
        player.blocks = true
        let now = Date()
        let session = OpenAIRealtimeConversation(settings: .init(), capture: capture,
                                                 player: player, now: { now }, connect: { socket }) { _ in "" }
        session.onTranscriptChanged = coordinator.conversationLog.voiceTranscriptWriter(tabID: space, providerID: "openai")
        coordinator.conversationVoice = session
        coordinator.isVoiceConversationPresented = true
        session.start()
        defer { coordinator.endVoiceConversation() }
        try #require(await waitUntil { session.phase == .listening })
        try capture.emit(value: 0.04)
        await socket.push(["type": "conversation.item.input_audio_transcription.completed", "item_id": "user", "transcript": "Can you help me with this page?"])
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 360, height: 600),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Linen voice UI verification"
        window.contentView = NSHostingView(rootView: VoiceChatPreview(coordinator: coordinator, session: session, space: space)
            .frame(width: 360, height: 600))
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        try #require(await waitUntil(timeout: .seconds(60)) { session.isMicrophoneMuted })
        try #require(await waitUntil(timeout: .seconds(60)) { !session.isMicrophoneMuted })
        await socket.push(["type": "input_audio_buffer.committed", "item_id": "user"])
        try #require(await socket.waitFor("response.create"))
        await socket.push(["type": "response.created", "response": ["id": "response"]])
        await socket.push(["type": "response.output_audio.delta", "response_id": "response", "item_id": "audio", "content_index": 0, "delta": "AAABAA=="])
        await socket.push(["type": "response.output_audio_transcript.delta", "response_id": "response", "item_id": "audio", "delta": "I can help with this page."])
        try #require(await waitUntil { session.phase == .speaking })
        try #require(await waitUntil(timeout: .seconds(60)) { session.phase == .listening })
        #expect(await socket.waitFor("response.cancel"))
        try #require(await waitUntil(timeout: .seconds(60)) { !coordinator.isVoiceConversationPresented })
        #expect(session.phase == .stopped)
        #expect(coordinator.conversationLog.traces(forTab: space).count == 1)
        #expect(coordinator.conversationLog.traces(forTab: space).first?.response == "I can help with this page.")
        #expect(await waitUntil(timeout: .seconds(60)) { !window.isVisible })
    }
}

private struct VoiceChatPreview: View {
    let coordinator: AppCoordinator
    let session: OpenAIRealtimeConversation
    let space: UUID

    var body: some View {
        VStack {
            if coordinator.isVoiceConversationPresented {
                AssistantVoiceConversationView(coordinator: coordinator)
            } else {
                AgentActivityPanel(traces: coordinator.conversationLog.traces(forTab: space), tabID: space,
                                   browser: coordinator.browser, onRetry: { _ in }, onEdit: { _ in }, onSpeak: { _ in })
                AssistantComposer(coordinator: coordinator, seed: .constant(nil)).padding(12)
            }
        }
        .background {
            if coordinator.isVoiceConversationPresented {
                VoiceConversationBackdrop(session: session)
            }
        }
    }
}
