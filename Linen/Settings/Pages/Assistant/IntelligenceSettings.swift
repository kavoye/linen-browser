// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Observation
import SwiftUI

struct AssistantSettings: View {
    @Bindable var model: IntelligenceViewModel
    let coordinator: AppCoordinator
    @Environment(\.settingsHighlight) private var highlight
    @Environment(\.settingsRouter) private var router

    var body: some View {
        Group {
            switch model.destination {
            case .overview:
                AssistantOverview(model: model, coordinator: coordinator)
            case .provider:
                ProviderPage(model: model, coordinator: coordinator)
            case .picker:
                AddProviderPage(model: model)
            case .editor:
                CustomProviderEditor(model: model)
            case .tools:
                AgentToolsPage(model: model)
            case .grants:
                AssistantGrantsPage(policy: coordinator.browser.context.actionPolicy, onBack: { model.showOverview() })
            case .openAI(let page):
                OpenAISettingsPageView(model: model, page: page)
            }
        }
        .task { await model.onAppear() }
        .onChange(of: router.path, initial: true) { _, path in
            model.follow(path)
        }
        .onChange(of: model.path) { _, path in
            guard !model.matches(router.path) else { return }
            if router.path.starts(with: path) {
                router.back(to: path)
            } else {
                router.open(path)
            }
        }
        .onChange(of: highlight, initial: true) { _, anchor in
            guard let anchor else { return }
            if anchor == "provider.connected" || anchor == "privacy.assistant" || anchor.hasPrefix("assistant.")
                || model.anchorsMissingFromSelected.contains(anchor) {
                router.back(to: [])
            } else if anchor.hasPrefix("provider.") {
                router.open(anchor == "provider.tools" ? [model.selected.id, "tools"] : [model.selected.id])
            } else if anchor.hasPrefix("openai."),
                      let provider = model.providers.first(where: { $0.adapter == .openAIResponses }) {
                router.open([provider.id] + (OpenAISettingsPage(anchor: anchor).map { [$0.slug] } ?? []))
            }
        }
    }
}

private extension IntelligenceViewModel {
    var anchorsMissingFromSelected: [String] {
        var hidden: [String] = []
        if selected.isOnDevice {
            hidden += ["provider.model", "provider.thinking"]
        }
        if selected.isOnDevice || !selected.needsKey {
            hidden.append("provider.key")
        }
        if selected.isOnDevice || !selected.isCustom {
            hidden.append("provider.endpoint")
        }
        if !providers.contains(where: { $0.adapter == .openAIResponses }) {
            hidden += SettingsIndex.all.map(\.id).filter { $0.hasPrefix("openai.") }
        }
        return hidden
    }
}

// MARK: - Who answers

private struct AssistantOverview: View {
    @Bindable var model: IntelligenceViewModel
    let coordinator: AppCoordinator

    var body: some View {
        SettingsPageHeader(title: "Assistant")

        AnsweringNotice(model: model, coordinator: coordinator)

        SettingsSection(title: "Providers", symbol: "link") {
            ForEach(model.connected) { provider in
                SettingsProviderRow(
                    provider: provider,
                    summary: model.summary(for: provider),
                    isInUse: provider.id == model.selectedID
                ) {
                    model.open(provider)
                }

                RowSeparator()
            }

            AddRow(title: "Add Provider…") { model.showPicker() }
        }
        .settingsAnchor("provider.connected", standingInFor: model.anchorsMissingFromSelected)
        .padding(.top, 6)

        BehaviourSection(settings: coordinator.settings)

        AssistantExecutionSettings()

        SettingsSection(title: "Acting on websites", symbol: "hand.raised") {
            DrillInRow(
                title: "Allowed without asking",
                detail: AssistantGrantsPage.summary(for: coordinator.browser.context.actionPolicy)
            ) {
                model.showGrants()
            }
            .settingsAnchor("privacy.assistant")
        }

        Footnote(AIDisclosure.settingsCaption)
    }
}

private struct AnsweringNotice: View {
    @Bindable var model: IntelligenceViewModel
    let coordinator: AppCoordinator

    private var active: Provider? {
        coordinator.engine.activeProvider
    }

    var body: some View {
        if active?.id == model.selectedID {
            EmptyView()
        } else {
            SettingsCard {
                state
            }
            .padding(.top, 6)
        }
    }

    @ViewBuilder
    private var state: some View {
        if let active {
            StatusRow(
                tint: Theme.warning,
                symbol: "exclamationmark",
                title: "\(model.selected.name) isn’t ready",
                caption: "Linen is using \(active.name) instead."
            ) {
                SettingsButton(title: "Set Up…", isProminent: true) {
                    model.open(model.selected)
                }
            }
        } else {
            StatusRow(
                tint: Theme.danger,
                symbol: "xmark",
                title: "No provider is ready",
                caption: "Add a provider, or fix the one you chose."
            ) {
                SettingsButton(title: "Add Provider…", isProminent: true) {
                    model.showPicker()
                }
            }
        }
    }
}

private struct BehaviourSection: View {
    @Bindable var settings: BrowserSettings

    var body: some View {
        SettingsSection(title: "Links", symbol: "link") {
            DetailRow(
                title: "Summarize a link on hover",
                caption: "Hold Shift while pointing at a link to get a summary before opening it."
            ) {
                SettingsToggle($settings.peeksAtLinks)
            }
            .settingsAnchor("assistant.linkPeek")
        }
    }
}

struct ThinkingSection: View {
    @Bindable var model: IntelligenceViewModel

    var body: some View {
        SettingsSection(title: "Thinking", symbol: "brain") {
            OptionList(
                options: model.availableEfforts.map {
                    .init(value: $0, label: $0.label, caption: $0.caption)
                },
                selection: model.resolvedEffort,
                onSelect: model.selectReasoningEffort
            )
        }
        .settingsAnchor("provider.thinking")
    }
}
