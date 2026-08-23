// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

enum SettingsMetrics {
    static let navWidth: CGFloat = 220
    static let detailWidth: CGFloat = 660
    static let pageInset: CGFloat = 32
    static let sectionSpacing: CGFloat = 28
    static let headerGap: CGFloat = 7

    static let controlWidth: CGFloat = 250
    static let rowPaddingV: CGFloat = 14
    static let cardInset: CGFloat = 16
    static let cardInsetV: CGFloat = 2
    static let rowPaddingH: CGFloat = 0
    static let rowContentInset: CGFloat = 8
    static let rowHoverFrameInset: CGFloat = 6
    static let pickerHorizontalInset: CGFloat = 4
    static let pickerVerticalInset: CGFloat = 9
    static let pickerItemPaddingV: CGFloat = 5

    static var controlRadius: CGFloat {
        Theme.Radius.control
    }
    static var rowRadius: CGFloat {
        Theme.Radius.card
    }
    static let controlHeight: CGFloat = 28

    static let hairline = Color.primary.opacity(0.08)
}

// MARK: - Containers

extension View {
    func settingsSurface<S: InsettableShape>(
        isActive: Bool = false,
        tint: Color? = nil,
        isLifted: Bool = false,
        in shape: S
    ) -> some View {
        controlGlassSurface(isActive: isActive, tint: tint, isLifted: isLifted, in: shape)
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    @Environment(\.settingsSectionLit) private var isLit

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .environment(\.settingsCardInset, SettingsMetrics.cardInset)
        .environment(\.settingsSectionLit, false)
        .padding(.horizontal, SettingsMetrics.cardInset)
        .padding(.vertical, SettingsMetrics.cardInsetV)
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsSurface(
            isActive: isLit,
            in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        )
        .animation(.easeOut(duration: 0.28), value: isLit)
    }
}

private struct RowHoverShape: Shape {
    let radius: CGFloat
    let verticalInset: CGFloat

    nonisolated func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .path(in: rect.insetBy(dx: 0, dy: verticalInset))
    }
}

private struct SettingsRowHover: ViewModifier {
    let isActive: Bool
    let tint: Color?

    func body(content: Content) -> some View {
        let hoverBleed = SettingsMetrics.cardInset - SettingsMetrics.rowHoverFrameInset
        let verticalInset = SettingsMetrics.rowHoverFrameInset - SettingsMetrics.cardInsetV

        content
            .padding(.horizontal, hoverBleed + SettingsMetrics.rowContentInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hoverBackground(
                isActive: isActive,
                tint: tint,
                in: RowHoverShape(
                    radius: SettingsMetrics.rowRadius,
                    verticalInset: verticalInset
                )
            )
            .padding(.horizontal, -hoverBleed)
            .contentShape(Rectangle())
    }
}

extension View {
    func settingsRowHover(isActive: Bool, tint: Color? = nil) -> some View {
        modifier(SettingsRowHover(isActive: isActive, tint: tint))
    }
}

struct SettingsPageHeader: View {
    private let title: Text
    var detail: String?
    private var caption: Text?

    var icon: NSImage?

    init(
        title: LocalizedStringResource,
        detail: String? = nil,
        caption: LocalizedStringResource? = nil,
        icon: NSImage? = nil
    ) {
        self.title = Text(title)
        self.detail = detail
        self.caption = caption.map(Text.init)
        self.icon = icon
    }

    init(verbatimTitle: String, detail: String? = nil, verbatimCaption: String? = nil) {
        self.title = Text(verbatim: verbatimTitle)
        self.detail = detail
        self.caption = verbatimCaption.map { Text(verbatim: $0) }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 60, height: 60)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 6) {
                title
                    .font(.system(size: 21, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let detail {
                    Text(verbatim: detail)
                        .font(Theme.Font.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if let caption {
                    caption
                        .font(Theme.Font.row)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsSection<Content: View, Accessory: View>: View {
    let title: LocalizedStringResource
    let symbol: String
    var footnote: LocalizedStringResource?
    @ViewBuilder let accessory: Accessory
    @ViewBuilder let content: Content

    init(
        title: LocalizedStringResource,
        symbol: String,
        footnote: LocalizedStringResource? = nil,
        @ViewBuilder content: () -> Content
    ) where Accessory == EmptyView {
        self.title = title
        self.symbol = symbol
        self.footnote = footnote
        self.accessory = EmptyView()
        self.content = content()
    }

    init(
        title: LocalizedStringResource,
        symbol: String,
        footnote: LocalizedStringResource? = nil,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.symbol = symbol
        self.footnote = footnote
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.headerGap) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(Theme.Font.caption)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .kerning(0.3)

                Spacer(minLength: 8)

                accessory
            }
            .foregroundStyle(.secondary)

            SettingsCard { content }

            if let footnote {
                Text(footnote)
                    .font(Theme.Font.label)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 1)
            }
        }
    }
}

struct DetailRow<Content: View>: View {
    enum Layout {
        case trailing
        case stacked
    }

    private var title: Text?
    private var caption: Text?
    var layout: Layout = .trailing

    @ViewBuilder let content: Content

    @Environment(\.isEnabled) private var isEnabled

    init(
        title: LocalizedStringResource? = nil,
        caption: LocalizedStringResource? = nil,
        layout: Layout = .trailing,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title.map(Text.init)
        self.caption = caption.map(Text.init)
        self.layout = layout
        self.content = content()
    }

    init(
        verbatimTitle: String,
        verbatimCaption: String? = nil,
        layout: Layout = .trailing,
        @ViewBuilder content: () -> Content
    ) {
        self.title = Text(verbatim: verbatimTitle)
        self.caption = verbatimCaption.map { Text(verbatim: $0) }
        self.layout = layout
        self.content = content()
    }

    var body: some View {
        Group {
            switch layout {
            case .trailing:
                HStack(alignment: .center, spacing: 24) {
                    label
                        .frame(maxWidth: .infinity, alignment: .leading)

                    content
                        .frame(maxWidth: SettingsMetrics.controlWidth, alignment: .trailing)
                }
            case .stacked:
                VStack(alignment: .leading, spacing: 10) {
                    label

                    content
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.vertical, SettingsMetrics.rowPaddingV)
    }

    @ViewBuilder
    private var label: some View {
        if title != nil || caption != nil {
            VStack(alignment: .leading, spacing: 3) {
                if let title {
                    title
                        .font(Theme.Font.rowTitle)
                        .foregroundStyle(isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                }

                if let caption {
                    caption
                        .font(Theme.Font.secondary)
                        .foregroundStyle(isEnabled ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct RowSeparator: View {
    var body: some View {
        Rectangle()
            .fill(SettingsMetrics.hairline)
            .frame(height: 1)
    }
}

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
            return AnyShapeStyle(.tertiary)
        }
        if isDestructive {
            return AnyShapeStyle(Theme.danger.opacity(0.95))
        }
        if let tint {
            return AnyShapeStyle(tint)
        }
        return AnyShapeStyle(.primary)
    }

    private var hoverGlassTint: Color? {
        if isDestructive {
            return Theme.danger
        }
        if let tint {
            return tint
        }
        return nil
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
        .opacity(isEnabled ? 1 : 0.45)
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

// MARK: - Status

enum StatusLevel {
    case ready
    case attention
    case idle

    var color: Color {
        switch self {
        case .ready:
            .green
        case .attention:
            Theme.warning
        case .idle:
            .secondary
        }
    }
}

struct StatusDot: View {
    let level: StatusLevel
    var haloed = true

    init(_ level: StatusLevel, haloed: Bool = true) {
        self.level = level
        self.haloed = haloed
    }

    var body: some View {
        Circle()
            .fill(level.color)
            .frame(width: 6, height: 6)
            .overlay(
                Circle()
                    .stroke(level.color.opacity(haloed ? 0.25 : 0), lineWidth: 3)
            )
    }
}

struct Tag: View {
    let text: LocalizedStringResource

    init(_ text: LocalizedStringResource) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .settingsSurface(in: Capsule())
            .fixedSize()
    }
}

struct KeyCap: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
            .foregroundStyle(.primary)
            .padding(.horizontal, 6)
            .frame(height: 20)
            .settingsSurface(
                in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
            )
    }
}

struct SettingsNotice: View {
    let symbol: String
    let text: String
    var level: StatusLevel = .attention

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 9.5))
                .padding(.top, 1.5)
            Text(verbatim: text)
        }
        .font(Theme.Font.label)
        .foregroundStyle(level.color)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct Footnote: View {
    let text: LocalizedStringResource

    init(_ text: LocalizedStringResource) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(Theme.Font.label)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, -20)
    }
}
