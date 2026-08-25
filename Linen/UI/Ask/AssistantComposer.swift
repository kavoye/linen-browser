// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct AssistantComposer: View {
    private static let effortWidth: CGFloat = 46

    let coordinator: AppCoordinator
    @Binding var seed: String?

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
        var taken = Set(mentions.map(\.id))
        if let active = coordinator.browser.activeTab?.id {
            taken.insert(active)
        }
        let matches = coordinator.browser.tabs.filter { tab in
            guard !taken.contains(tab.id), !tab.isShowingSystemPage, !tab.hasNoPageYet else { return false }
            guard !fragment.isEmpty else { return true }
            return tab.title.lowercased().contains(fragment)
                || tab.urlString.lowercased().contains(fragment)
        }
        return Array(matches.prefix(5))
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
        .onChange(of: mentionFragment) { _, _ in
            mentionSelection = 0
            mentionsDismissed = false
        }
        .onChange(of: seed) { _, prompt in
            guard let prompt else { return }
            draft = prompt
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
        VStack(alignment: .leading, spacing: 9) {
            MentionField(
                text: $draft,
                chips: chips,
                placeholder: placeholder,
                fontSize: 12.5,
                isFocused: writing,
                accessibilityLabel: placeholder,
                wraps: true,
                onFocusChange: focus(_:),
                onChipsChange: keep(_:),
                onSubmit: submit,
                onCancel: dismissMentions,
                onMove: move(by:jumping:)
            )

            HStack(spacing: 2) {
                AssistantPicker(sections: .providers, coordinator: coordinator) { _ in
                    ProviderBrandIcon(providerID: coordinator.selectedProvider.id, size: 14)
                }
                .padding(.leading, -4)
                .padding(.trailing, -4)

                AssistantPicker(
                    sections: .models,
                    coordinator: coordinator,
                    isPickable: !coordinator.selectedProvider.isOnDevice
                ) { hovering in
                    Text(verbatim: modelLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(hovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .layoutPriority(-1)

                if coordinator.supportsReasoningEffort {
                    AssistantPicker(sections: .thinking, coordinator: coordinator) { hovering in
                        EffortMeter(effort: coordinator.selectedEffort)

                        Text(coordinator.selectedEffort.label)
                            .font(Theme.Font.caption)
                            .foregroundStyle(hovering ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                            .lineLimit(1)
                            .frame(width: Self.effortWidth, alignment: .leading)
                    }
                }

                Spacer(minLength: 0)

                SendButton(stops: stops, isEnabled: !trimmed.isEmpty || isWorking) {
                    if stops {
                        stop()
                    } else {
                        send()
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Wash.hairline)
        )
        .contentShape(Rectangle())
        .onTapGesture { writing = true }
    }

    private var stops: Bool {
        isWorking && trimmed.isEmpty
    }

    private var placeholder: String {
        isAnsweringAQuestion ? String(localized: "Answer…") : String(localized: "Ask anything")
    }

    private var modelLabel: String {
        let provider = coordinator.selectedProvider
        if provider.isOnDevice {
            return provider.name
        }
        let model = coordinator.selectedModel
        return model.isEmpty ? String(localized: "Choose a model") : model
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

    private func send() {
        let message = trimmed
        guard !message.isEmpty else { return }
        let mentionedTabIDs = attached
        draft = ""
        mentions = []
        if isAnsweringAQuestion {
            coordinator.agentQuestions.answer(message)
            return
        }
        Task {
            await coordinator.handleTypedUtterance(
                message,
                mentionedTabIDs: mentionedTabIDs,
                showsInChrome: false
            )
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

private struct SendButton: View {
    let stops: Bool
    let isEnabled: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color.primary.opacity(isEnabled ? (hovering ? 1 : 0.88) : 0.55))
                .frame(width: 24, height: 24)
                .overlay {
                    Image(systemName: stops ? "square.fill" : "arrow.up")
                        .font(.system(size: stops ? 8 : 11, weight: .bold))
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.quick, value: hovering)
        .help(Text(stops ? LocalizedStringResource("Stop") : LocalizedStringResource("Send")))
    }
}

private struct AssistantPicker<Label: View>: View {
    let sections: EnginePopover.Sections
    let coordinator: AppCoordinator
    var isPickable = true
    @ViewBuilder let label: (Bool) -> Label

    @State private var isPresenting = false
    @State private var hovering = false

    private var help: LocalizedStringResource {
        if sections.contains(.providers) {
            return "Choose which assistant answers"
        }
        if sections.contains(.models) {
            return "Choose the model"
        }
        return "Choose how much it thinks"
    }

    var body: some View {
        if isPickable {
            Button {
                isPresenting = true
            } label: {
                plate
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(Theme.Motion.quick, value: hovering)
            .help(Text(help))
            .popover(isPresented: $isPresenting, arrowEdge: .bottom) {
                EnginePopover(coordinator: coordinator, sections: sections) {
                    isPresenting = false
                }
            }
        } else {
            plate
        }
    }

    private var plate: some View {
        HStack(spacing: 4) {
            label(isPickable && (hovering || isPresenting))
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}
