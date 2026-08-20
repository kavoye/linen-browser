// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

enum ModelChipMetrics {
    static let height = SettingsMetrics.controlHeight
    static let radius = Theme.Radius.control
    static let inset: CGFloat = 9
    static let markSize: CGFloat = 14
    static let markGap: CGFloat = 7

    static let textInset = inset + markSize + markGap
}

struct ModelChip: View {
    let coordinator: AppCoordinator

    @State private var isPresenting = false
    @State private var hovering = false

    private var provider: Provider {
        coordinator.selectedProvider
    }

    private var isAdjustable: Bool {
        !provider.isOnDevice
    }

    var body: some View {
        if isAdjustable {
            Button {
                isPresenting = true
            } label: {
                chip
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(Theme.Motion.quick, value: hovering)
            .help("Change the model or how much it thinks")
            .popover(isPresented: $isPresenting, arrowEdge: .top) {
                EnginePopover(coordinator: coordinator) { isPresenting = false }
            }
        } else {
            chip
        }
    }

    private var chip: some View {
        HStack(spacing: ModelChipMetrics.markGap) {
            ProviderBrandIcon(providerID: provider.id, size: ModelChipMetrics.markSize)

            Text(verbatim: label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            if coordinator.supportsReasoningEffort {
                EffortMeter(effort: coordinator.selectedEffort)
                Text(coordinator.selectedEffort.label)
                    .font(Theme.Font.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .layoutPriority(-1)
            }

            Spacer(minLength: 0)

            if !coordinator.isUsingSelectedProvider {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.warning)
                    .help(Text(verbatim: coordinator.statusMessage ?? String(localized: "Not in use right now.")))
            }

            if isAdjustable {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, ModelChipMetrics.inset)
        .frame(height: ModelChipMetrics.height)
        .background {
            if isAdjustable {
                let shape = RoundedRectangle(cornerRadius: ModelChipMetrics.radius)
                shape
                    .fill(hovering || isPresenting ? SettingsMetrics.fillHover : SettingsMetrics.fill)
                    .overlay(
                        shape.strokeBorder(
                            hovering || isPresenting ? SettingsMetrics.borderHover : SettingsMetrics.border,
                            lineWidth: 1
                        )
                    )
            }
        }
        .contentShape(Rectangle())
    }

    private var label: String {
        if provider.isOnDevice {
            return provider.name
        }
        let model = coordinator.selectedModel
        return model.isEmpty ? String(localized: "Choose a model") : model
    }
}

struct EffortMeter: View {
    let effort: LLMSettings.ReasoningEffort

    private var lit: Int {
        switch effort {
        case .none:
            1
        case .low:
            2
        case .medium:
            3
        case .high:
            4
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(index < lit ? Theme.Wash.scrim : Theme.Wash.strong)
                    .frame(width: 2, height: 3 + CGFloat(index) * 2)
            }
        }
        .frame(height: 9, alignment: .bottom)
        .animation(Theme.Motion.settle, value: lit)
        .accessibilityHidden(true)
    }
}

// MARK: - The popover

private enum PopoverMetrics {
    static let inset: CGFloat = 12
    static let plateInset: CGFloat = 7
    static let rowHeight: CGFloat = 26
    static let sectionGap: CGFloat = 10
    static let visibleCatalogRows = 5

    static let plateRadius = Theme.Radius.nested(in: Theme.Radius.panel, inset: plateInset)
}

private struct EnginePopover: View {
    let coordinator: AppCoordinator
    let dismiss: () -> Void

    @State private var fetched: [String] = []
    @State private var isLoading = false
    @State private var loadError: String?

    private var provider: Provider {
        coordinator.selectedProvider
    }
    private var selectedModel: String {
        coordinator.selectedModel
    }

    private var pinned: [Provider.ModelSuggestion] {
        var models = provider.suggestedModels
        if !selectedModel.isEmpty, !models.contains(where: { $0.id == selectedModel }) {
            models.insert(.init(id: selectedModel, name: selectedModel, detail: ""), at: 0)
        }
        return models
    }

    private var rest: [String] {
        let known = Set(pinned.map(\.id))
        return fetched.filter { !known.contains($0) }
    }

    private var catalogHeight: CGFloat {
        CGFloat(min(rest.count, PopoverMetrics.visibleCatalogRows)) * PopoverMetrics.rowHeight
    }

    private var catalogTitle: LocalizedStringResource {
        let title: LocalizedStringResource = provider.isLocal
            ? "Pulled locally"
            : "Available to this key"
        return title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PopoverSectionHeader("Model")

            ForEach(pinned) { suggestion in
                EngineRow(
                    title: suggestion.id,
                    detail: suggestion.detail,
                    isSelected: suggestion.id == selectedModel
                ) {
                    choose(model: suggestion.id)
                }
            }

            if !rest.isEmpty {
                PopoverSectionHeader(catalogTitle)
                    .padding(.top, PopoverMetrics.sectionGap)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(rest, id: \.self) { id in
                            EngineRow(title: id, detail: "", isSelected: id == selectedModel) {
                                choose(model: id)
                            }
                        }
                    }
                }
                .frame(height: catalogHeight)
                .scrollBounceBehavior(.basedOnSize)
            } else {
                PlainRow(
                    title: "Show all models",
                    symbol: "arrow.down.circle",
                    isBusy: isLoading
                ) {
                    Task { await load() }
                }
                .disabled(isLoading)
            }

            if let loadError {
                Text(verbatim: loadError)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, PopoverMetrics.inset)
                    .padding(.top, 6)
            }

            if coordinator.supportsReasoningEffort {
                PopoverDivider()

                PopoverSectionHeader("Thinking")

                SegmentedControl(
                    items: LLMSettings.ReasoningEffort.allCases.map {
                        .init(value: $0, label: $0.label)
                    },
                    selection: coordinator.selectedEffort,
                    onSelect: choose(effort:)
                )
                .padding(.horizontal, PopoverMetrics.inset)
                .help(Text(coordinator.selectedEffort.caption))
            }

            PopoverDivider()

            HStack(spacing: 7) {
                ProviderBrandIcon(providerID: provider.id, size: 12)

                Text(verbatim: provider.name)
                    .font(Theme.Font.label)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Button {
                    dismiss()
                    coordinator.openSettings(.provider)
                } label: {
                    Text("Change in Settings…")
                        .font(Theme.Font.label)
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, PopoverMetrics.inset)
        }
        .padding(.vertical, PopoverMetrics.sectionGap)
        .frame(width: 300)
        .task {
            if fetched.isEmpty {
                await load()
            }
        }
    }

    private func choose(model id: String) {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        LLMSettings.setModel(trimmed, for: provider)
        coordinator.configureEngines()
        dismiss()
    }

    private func choose(effort: LLMSettings.ReasoningEffort) {
        guard effort != coordinator.selectedEffort else { return }
        LLMSettings.reasoningEffort = effort
        coordinator.configureEngines()
    }

    private func load() async {
        guard !isLoading else { return }
        let engine = coordinator.engine(for: provider)
        guard case .available = engine.availability else {
            loadError = String(localized: "Add an API key for \(provider.name) in Settings to see its models.")
            return
        }

        isLoading = true
        loadError = nil
        do {
            let models = try await engine.availableModels()
            guard provider.id == coordinator.selectedProvider.id else { return }
            fetched = models
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }
}

private struct PopoverSectionHeader: View {
    let title: LocalizedStringResource

    init(_ title: LocalizedStringResource) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(Theme.Font.badge)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, PopoverMetrics.inset)
            .padding(.bottom, 5)
    }
}

private struct PopoverDivider: View {
    var body: some View {
        Divider()
            .padding(.horizontal, PopoverMetrics.plateInset)
            .padding(.vertical, PopoverMetrics.sectionGap)
    }
}

private struct EngineRow: View {
    let title: String
    let detail: String
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 10)
                    .opacity(isSelected ? 1 : 0)

                Text(verbatim: title)
                    .font(.system(size: 11.5, weight: isSelected ? .medium : .regular, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 8)

                if !detail.isEmpty {
                    Text(verbatim: detail)
                        .font(Theme.Font.micro)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .layoutPriority(-1)
                }
            }
            .padding(.horizontal, PopoverMetrics.inset)
            .frame(height: PopoverMetrics.rowHeight)
            .background {
                RoundedRectangle(cornerRadius: PopoverMetrics.plateRadius)
                    .fill(hovering ? Theme.Wash.hover : Theme.Wash.none)
                    .padding(.horizontal, PopoverMetrics.plateInset)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct PlainRow: View {
    let title: LocalizedStringResource
    let symbol: String
    var isBusy = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Group {
                    if isBusy {
                        Spinner(size: 10)
                    } else {
                        Image(systemName: symbol)
                            .font(Theme.Font.micro)
                    }
                }
                .frame(width: 10)

                Text(title)
                    .font(Theme.Font.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, PopoverMetrics.inset)
            .frame(height: PopoverMetrics.rowHeight)
            .background {
                RoundedRectangle(cornerRadius: PopoverMetrics.plateRadius)
                    .fill(hovering && isEnabled ? Theme.Wash.hover : Theme.Wash.none)
                    .padding(.horizontal, PopoverMetrics.plateInset)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
