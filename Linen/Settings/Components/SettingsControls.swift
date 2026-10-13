// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

// MARK: - Buttons

struct SettingsButton: View {
    private let titleText: Text
    var isProminent = false
    var isDestructive = false
    var tint: Color?
    var symbol: String?
    var minWidth: CGFloat?
    let action: () -> Void

    init(
        title: LocalizedStringResource,
        isProminent: Bool = false,
        isDestructive: Bool = false,
        tint: Color? = nil,
        symbol: String? = nil,
        minWidth: CGFloat? = nil,
        action: @escaping () -> Void
    ) {
        titleText = Text(title)
        self.isProminent = isProminent
        self.isDestructive = isDestructive
        self.tint = tint
        self.symbol = symbol
        self.minWidth = minWidth
        self.action = action
    }

    init(
        verbatimTitle: String,
        isProminent: Bool = false,
        isDestructive: Bool = false,
        tint: Color? = nil,
        symbol: String? = nil,
        minWidth: CGFloat? = nil,
        action: @escaping () -> Void
    ) {
        titleText = Text(verbatim: verbatimTitle)
        self.isProminent = isProminent
        self.isDestructive = isDestructive
        self.tint = tint
        self.symbol = symbol
        self.minWidth = minWidth
        self.action = action
    }

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    private var label: AnyShapeStyle {
        if !isEnabled {
            return AnyShapeStyle(.secondary)
        }
        if isDestructive {
            return hovering ? AnyShapeStyle(Theme.danger) : AnyShapeStyle(.primary)
        }
        if let tint {
            return AnyShapeStyle(tint)
        }
        return AnyShapeStyle(.primary)
    }

    private var hoverGlassTint: Color? {
        isDestructive ? nil : tint
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(Theme.Font.badge)
                }
                titleText
                    .font(.system(size: 12, weight: isProminent ? .semibold : .medium))
            }
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(label)
            .padding(.horizontal, 12)
            .frame(minWidth: minWidth)
            .frame(height: SettingsMetrics.controlHeight)
            .settingsSurface(
                isActive: hovering && isEnabled,
                tint: hoverGlassTint,
                isLifted: true,
                in: RoundedRectangle(cornerRadius: SettingsMetrics.controlRadius, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = isEnabled && $0 }
        .animation(Theme.Motion.quick, value: hovering)
    }
}

struct IconButton: View {
    let symbol: String
    var help: LocalizedStringResource?
    var isBusy = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Group {
                if isBusy {
                    Spinner(size: 12)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: SettingsMetrics.controlHeight, height: SettingsMetrics.controlHeight)
            .settingsSurface(isActive: hovering && isEnabled, isLifted: true, in: Circle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { hovering = isEnabled && $0 }
        .animation(Theme.Motion.quick, value: hovering)
        .help(help.map(Text.init) ?? Text(verbatim: ""))
    }
}

struct SegmentedControl<Value: Hashable>: View {
    struct Item: Identifiable {
        let value: Value
        let label: LocalizedStringResource
        var isEnabled = true
        var help: LocalizedStringResource?

        var id: Value {
            value
        }
    }

    let items: [Item]
    let selection: Value
    let onSelect: (Value) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                let isSelected = item.value == selection

                Button {
                    onSelect(item.value)
                } label: {
                    Text(item.label)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .selectionBackground(
                            isSelected: isSelected,
                            isHovering: false,
                            in: RoundedRectangle(cornerRadius: SettingsMetrics.controlRadius - 2, style: .continuous)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!item.isEnabled)
                .opacity(item.isEnabled ? 1 : 0.4)
                .help(item.help.map(Text.init) ?? Text(verbatim: ""))
            }
        }
        .padding(2)
        .settingsSurface(
            in: RoundedRectangle(cornerRadius: SettingsMetrics.controlRadius, style: .continuous)
        )
        .animation(.snappy(duration: 0.18), value: selection)
    }
}

// MARK: - Fields

extension View {
    func fieldPlaceholder(_ text: LocalizedStringResource, isShowing: Bool) -> some View {
        fieldPlaceholder(Text(text), isShowing: isShowing)
    }

    func fieldPlaceholder(verbatim text: String, isShowing: Bool) -> some View {
        fieldPlaceholder(Text(verbatim: text), isShowing: isShowing)
    }

    private func fieldPlaceholder(_ text: Text, isShowing: Bool) -> some View {
        overlay(alignment: .leading) {
            if isShowing {
                text
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .allowsHitTesting(false)
            }
        }
    }
}

struct SearchFieldChrome<Content: View>: View {
    var height: CGFloat = SettingsMetrics.controlHeight
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)

            content
        }
        .padding(.horizontal, 9)
        .frame(height: height)
        .glassSurface(
            in: RoundedRectangle(cornerRadius: SettingsMetrics.controlRadius, style: .continuous)
        )
    }
}

struct FieldChrome<Content: View>: View {
    let isFocused: Bool
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 10)
            .frame(height: SettingsMetrics.controlHeight)
            .settingsSurface(
                isActive: isFocused,
                isLifted: true,
                in: RoundedRectangle(cornerRadius: SettingsMetrics.controlRadius, style: .continuous)
            )
            .animation(Theme.Motion.settle, value: isFocused)
    }
}

struct MenuChrome<Content: View>: View {
    @ViewBuilder let content: Content

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 7) {
            content

            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .frame(height: SettingsMetrics.controlHeight)
        .settingsSurface(
            isActive: hovering,
            isLifted: true,
            in: RoundedRectangle(cornerRadius: SettingsMetrics.controlRadius, style: .continuous)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(Theme.Motion.quick, value: hovering)
    }
}

struct SettingsToggle: View {
    @Binding var isOn: Bool

    init(_ isOn: Binding<Bool>) {
        _isOn = isOn
    }

    var body: some View {
        Toggle("", isOn: $isOn)
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
    }
}

struct SettingsMenu<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        let label: String
        var detail: String = ""

        var id: Value {
            value
        }
    }

    let options: [Option]
    @Binding var selection: Value
    var placeholder: LocalizedStringResource = "Choose"

    private func chosen(_ option: Option) -> Binding<Bool> {
        Binding {
            option.value == selection
        } set: { isOn in
            guard isOn else { return }
            selection = option.value
        }
    }

    private func title(for option: Option) -> String {
        guard !option.detail.isEmpty else { return option.label }
        return String(
            localized: "menu.option.labelAndDetail",
            defaultValue: "\(option.label) — \(option.detail)",
            comment: """
                One line of an open pop-up menu: %1$@ is the choice \
                itself (often a model or endpoint name), %2$@ a short \
                note about it. Only the separator is ours to change.
                """
        )
    }

    private var current: Option? {
        options.first { $0.value == selection }
    }

    var body: some View {
        Menu {
            ForEach(options) { option in
                Toggle(isOn: chosen(option)) {
                    Text(verbatim: title(for: option))
                }
            }
        } label: {
            MenuChrome {
                (current.map { Text(verbatim: $0.label) } ?? Text(placeholder))
                    .font(Theme.Font.body)
                    .foregroundStyle(current == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize(horizontal: false, vertical: true)
    }
}
