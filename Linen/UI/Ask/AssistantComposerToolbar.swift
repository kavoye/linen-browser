// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct AssistantComposerToolbar: View {
    let coordinator: AppCoordinator
    let attachments: AttachmentDraft
    let stops: Bool
    let canSend: Bool
    var offersVoice = false
    let onSend: () -> Void

    private var contextProvider: Provider {
        coordinator.activeProvider ?? coordinator.selectedProvider
    }

    private var contextModel: String {
        contextProvider.id == coordinator.selectedProvider.id
            ? coordinator.selectedModel : LLMSettings.model(for: contextProvider)
    }

    private var modelLabel: String {
        let provider = coordinator.selectedProvider
        if provider.isOnDevice {
            return provider.name
        }
        let model = coordinator.selectedModel
        return model.isEmpty ? String(localized: "Choose a model") : model
    }

    var body: some View {
        HStack(spacing: 6) {
            AssistantAttachmentButton(attachments: attachments)

            ComposerPicker(
                sections: [.providers, .models], coordinator: coordinator,
                help: Text("Choose the provider and model"), isPill: true
            ) {
                ProviderBrandIcon(providerID: coordinator.selectedProvider.id, size: 12)
                    .accessibilityHidden(true)
                Text(verbatim: modelLabel)
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .layoutPriority(-1)
            .accessibilityLabel(Text("Model: \(modelLabel)"))

            if coordinator.supportsReasoningEffort {
                ComposerPicker(
                    sections: .thinking, coordinator: coordinator,
                    help: Text("Thinking: \(coordinator.selectedEffort.label)")
                ) {
                    EffortMeter(effort: coordinator.selectedEffort)
                }
                .accessibilityLabel("Thinking Effort")
                .accessibilityValue(Text(coordinator.selectedEffort.label))
            }

            Spacer(minLength: 0)

            AssistantContextIndicator(
                tokens: coordinator.browser.activeSpaceID.map {
                    coordinator.conversationLog.usage(forTab: $0).estimatedContextTokens
                } ?? 0,
                window: ContextWindow.resolve(for: contextProvider, model: contextModel),
                providerNotice: coordinator.isUsingSelectedProvider ? nil : String(localized: "Using \(contextProvider.name)"),
                canCompact: coordinator.agentTurns.supportsCompaction
                    && !coordinator.agentTurns.isRunning
                    && coordinator.agentTurns.compactingSpaceID == nil
                    && coordinator.browser.activeSpaceID.map {
                        coordinator.conversationLog.checkpoint(forTab: $0) != nil
                    } == true,
                isCompacting: coordinator.agentTurns.compactingSpaceID != nil
                    && coordinator.agentTurns.compactingSpaceID == coordinator.browser.activeSpaceID
                    || coordinator.agentReply.isCompacting
                    && coordinator.agentReply.spaceID == coordinator.browser.activeSpaceID,
                compactionMessage: coordinator.agentTurns.compactionMessageSpaceID == coordinator.browser.activeSpaceID
                    ? coordinator.agentTurns.compactionMessage : nil,
                onCompact: {
                    if let spaceID = coordinator.browser.activeSpaceID {
                        coordinator.agentTurns.compactContext(inSpace: spaceID)
                    }
                }
            )
            .id(coordinator.browser.activeSpaceID)

            ComposerSendButton(stops: stops, isVoice: offersVoice && !stops && coordinator.supportsVoiceConversation,
                               isEnabled: canSend || (offersVoice && coordinator.supportsVoiceConversation)) {
                if offersVoice && !stops && coordinator.supportsVoiceConversation {
                    coordinator.startVoiceConversation()
                } else {
                    onSend()
                }
            }
        }
        .frame(height: 28)
    }
}

private struct AssistantAttachmentButton: View {
    let attachments: AttachmentDraft

    @State private var hovering = false

    var body: some View {
        Button { attachments.chooseFiles() } label: {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(hovering ? .primary : .secondary)
                .frame(height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("Add Attachments")
        .help("Add Attachments")
    }
}

private struct ComposerPicker<Label: View>: View {
    let sections: EnginePopover.Sections
    let coordinator: AppCoordinator
    let help: Text
    var isPill = false
    @ViewBuilder let label: () -> Label

    @State private var isPresenting = false
    @State private var hovering = false

    var body: some View {
        Button { isPresenting = true } label: {
            HStack(spacing: 5) {
                label()
            }
            .foregroundStyle(hovering || isPresenting ? .primary : .secondary)
            .padding(.horizontal, isPill ? 8 : 0)
            .frame(width: isPill ? nil : 28, height: 28)
            .background(
                Color.primary.opacity(hovering || isPresenting ? 0.09 : (isPill ? 0.035 : 0)),
                in: Capsule()
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .popover(isPresented: $isPresenting, arrowEdge: .bottom) {
            EnginePopover(coordinator: coordinator, sections: sections) { isPresenting = false }
        }
    }
}

private struct ComposerSendButton: View {
    let stops: Bool
    let isVoice: Bool
    let isEnabled: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color.primary.opacity(isEnabled ? (hovering ? 1 : 0.9) : 0.06))
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: stops ? "square.fill" : (isVoice ? "waveform" : "arrow.up"))
                        .font(.system(size: stops ? 9 : 12, weight: .semibold))
                        .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.5))
                        .blendMode(isEnabled ? .destinationOut : .normal)
                }
                .compositingGroup()
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { hovering = $0 }
        .accessibilityLabel(Text(label))
        .help(Text(label))
    }

    private var label: LocalizedStringResource { stops ? "Stop" : (isVoice ? "Start voice conversation" : "Send") }
}
