// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import UniformTypeIdentifiers

struct AssistantComposer: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let coordinator: AppCoordinator
    @Binding var seed: ConversationLog.TaskTrace?

    @State private var attachments = AttachmentDraft()
    @State private var dropTargeted = false
    @State private var isSending = false
    @State private var draft = ""
    @State private var mentions: [AssistantMention] = []
    @State private var mentionSelection = 0
    @State private var mentionsDismissed = false
    @State private var writing = false

    private var trimmed: String {
        MentionText.resolved(draft, chips: chips)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var chips: [MentionChip] {
        mentions.map { MentionChip(id: $0.id, title: $0.title, host: $0.host) }
    }

    private var isWorking: Bool {
        coordinator.browser.activeTab?.isAgentWorking == true
    }

    private var isAnsweringAQuestion: Bool {
        coordinator.agentQuestions.ask(inSpace: coordinator.browser.activeSpaceID) != nil
    }

    private var mentionFragment: String? {
        AskSurfaceInteraction.mentionFragment(in: draft)
    }

    private var mentionable: [BrowserTab] {
        guard !mentionsDismissed, let fragment = mentionFragment else { return [] }
        return AskSurfaceInteraction.mentionCandidates(
            fragment: fragment,
            tabs: coordinator.browser.tabs,
            mentionedTabIDs: Set(mentions.map(\.id)),
            activeTabID: coordinator.browser.activeTab?.id
        )
    }

    private var attached: [UUID] {
        mentions.map(\.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !mentionable.isEmpty {
                AssistantMentionList(
                    tabs: mentionable,
                    selection: selected,
                    onPick: attach
                )
            }

            field
        }
        .onDrop(of: [UTType.fileURL, UTType.image], isTargeted: $dropTargeted, perform: attachments.drop)
        .onChange(of: coordinator.browser.activeSpaceID) { _, _ in
            attachments.clear()
            draft = ""
            mentions = []
        }
        .onDisappear { attachments.clear() }
        .onChange(of: mentionFragment) { _, _ in
            mentionSelection = 0
            mentionsDismissed = false
        }
        .onChange(of: seed) { _, prompt in
            guard let prompt else { return }
            draft = prompt.prompt
            attachments.clear()
            attachments.files = prompt.attachments
            mentions = []
            seed = nil
            writing = true
        }
    }

    private var selected: UUID? {
        guard !mentionable.isEmpty else { return nil }
        return mentionable[min(max(mentionSelection, 0), mentionable.count - 1)].id
    }

    private var field: some View {
        VStack(alignment: .leading, spacing: 7) {
            AttachmentComposerStatus(attachments: attachments, isTextOnly: effectiveTextOnly)
            AssistantTextEditor(
                text: $draft,
                chips: chips,
                placeholder: placeholder,
                fontSize: 12.5,
                isFocused: writing,
                showsMentions: !mentionable.isEmpty,
                onFocusChange: focus(_:),
                onChipsChange: keep(_:),
                onSubmit: submit,
                onCancel: dismissMentions,
                onMove: move(by:jumping:),
                onAttachmentPaste: attachments.paste
            )

            AssistantComposerToolbar(
                coordinator: coordinator, attachments: attachments,
                stops: stops,
                canSend: stops || (!attachments.isImporting && !isSending && (!trimmed.isEmpty || !attachments.files.isEmpty)),
                offersVoice: trimmed.isEmpty && attachments.files.isEmpty && !attachments.isImporting && !isSending && !isAnsweringAQuestion
            ) {
                if stops {
                    stop()
                } else {
                    send()
                }
            }
        }
        .padding(.leading, 12)
        .padding(.top, 10)
        .padding([.trailing, .bottom], 8)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Wash.hairline)
        )
        .background(
            Theme.windowBackground.opacity(reduceTransparency ? 1 : (coordinator.sidePanel.isExpanded ? 0.96 : 0)),
            in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(
                    dropTargeted ? Color.accentColor : Color.primary.opacity(
                        contrast == .increased ? 0.4 : (writing ? 0.18 : 0.08)
                    ),
                    lineWidth: dropTargeted ? 2 : 1
                )
                .allowsHitTesting(false)
        }
        .animation(reduceMotion ? nil : Theme.Motion.quick, value: writing)
        .contentShape(Rectangle())
        .onTapGesture { writing = true }
    }

    private var stops: Bool {
        isWorking && trimmed.isEmpty && attachments.files.isEmpty
    }

    private var placeholder: String {
        isAnsweringAQuestion ? String(localized: "Answer…") : String(localized: "Ask anything")
    }

    private func submit() {
        if let id = selected, let tab = mentionable.first(where: { $0.id == id }) {
            attach(tab)
            return
        }
        send()
    }

    private func focus(_ focused: Bool) {
        guard writing != focused else { return }
        writing = focused
    }

    private func keep(_ ids: [UUID]) {
        guard ids != mentions.map(\.id) else { return }
        let known = Dictionary(mentions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        mentions = ids.compactMap { known[$0] }
    }

    private func move(by step: Int, jumping: Bool) {
        let count = mentionable.count
        guard count > 0 else { return }
        if jumping {
            mentionSelection = step < 0 ? 0 : count - 1
            return
        }
        mentionSelection = (min(max(mentionSelection, 0), count - 1) + step + count) % count
    }

    private func dismissMentions() {
        guard !mentionable.isEmpty else { return }
        mentionsDismissed = true
    }

    private func attach(_ tab: BrowserTab) {
        let mention = AssistantMention(tab: tab)
        mentions.removeAll { $0.id == mention.id }
        mentions.append(mention)
        draft = MentionText.appending(to: draft)
        writing = true
    }

    private var effectiveTextOnly: Bool {
        !ModelImageSupport.acceptsImages(for: coordinator.selectedProvider, model: coordinator.selectedModel)
    }

    private func send() {
        let message = trimmed
        guard !attachments.isImporting, !isSending, !message.isEmpty || !attachments.files.isEmpty else { return }
        do {
            try AttachmentRequest.validate(
                attachments.files, message: message, textOnly: effectiveTextOnly,
                windowTokens: ContextWindow.tokens(for: coordinator.selectedProvider, model: coordinator.selectedModel)
            )
        } catch {
            attachments.error = error.localizedDescription
            return
        }
        if isAnsweringAQuestion && attachments.files.isEmpty {
            draft = ""
            mentions = []
            coordinator.agentQuestions.answer(message)
            return
        }
        let mentionedTabIDs = attached
        let files = attachments.files
        isSending = true
        Task {
            let started = await coordinator.handleTypedUtterance(
                message, mentionedTabIDs: mentionedTabIDs, attachments: files,
                showsInChrome: false
            )
            isSending = false
            if started {
                draft = ""
                mentions = []
                attachments.clear()
            } else {
                attachments.error = coordinator.statusMessage
            }
        }
    }

    private func stop() {
        coordinator.stopAgent()
    }
}

struct AssistantMention: Identifiable, Equatable {
    let id: UUID
    let title: String
    let host: String?

    init(tab: BrowserTab) {
        id = tab.id
        title = tab.title
        host = URL(string: tab.urlString)?.displayHost
    }
}

private struct AssistantMentionList: View {
    let tabs: [BrowserTab]
    let selection: UUID?
    let onPick: (BrowserTab) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Attach Tab")
                .font(Theme.Font.badge)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 10)
                .padding(.bottom, 4)

            ForEach(tabs) { tab in
                AssistantMentionRow(tab: tab, isSelected: tab.id == selection) { onPick(tab) }
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Wash.hairline)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Wash.strong, lineWidth: 1)
        )
    }
}

private struct AssistantMentionRow: View {
    let tab: BrowserTab
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    private var host: String? {
        URL(string: tab.urlString)?.displayHost
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                OmniboxFavicon(host: host ?? "", fallback: "square.on.square", size: 13, isSelected: false)

                Text(verbatim: tab.title)
                    .font(Theme.Font.body)
                    .lineLimit(1)

                if let host {
                    Text(verbatim: host)
                        .font(Theme.Font.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .layoutPriority(-1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(height: 24)
            .hoverBackground(
                isActive: hovering || isSelected,
                in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
            )
            .contentShape(Rectangle())
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
