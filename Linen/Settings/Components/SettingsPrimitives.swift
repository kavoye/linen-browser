// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

extension EnvironmentValues {
    @Entry var settingsDescriptionLineLimit: Int?
}

enum SettingsMetrics {
    static let navWidth: CGFloat = 220
    static let navIconsWidth: CGFloat = 46

    static let twoColumnMinWidth: CGFloat = 520
    static let detailWidth: CGFloat = 660
    static let pageInset: CGFloat = 32
    static let compactPageInset: CGFloat = 10
    static let sectionSpacing: CGFloat = 28
    static let headerGap: CGFloat = 7

    static let controlWidth: CGFloat = 250
    static let rowPaddingV: CGFloat = 14
    static let cardInset: CGFloat = 16
    static var separatorInset: CGFloat {
        rowContentInset
    }
    static let compactCardInset: CGFloat = 10
    static let cardInsetV: CGFloat = 2
    static let rowPaddingH: CGFloat = 0
    static let rowContentInset: CGFloat = 8
    static let pickerHorizontalInset: CGFloat = 0
    static let pickerLabelGap: CGFloat = 6
    static let pickerVerticalInset: CGFloat = 9
    static let pickerItemPaddingV: CGFloat = 5

    static var controlRadius: CGFloat {
        Theme.Radius.control
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
        modifier(SettingsSurface(isActive: isActive, tint: tint, isLifted: isLifted, shape: shape))
    }
}

private struct SettingsSurface<S: InsettableShape>: ViewModifier {
    let isActive: Bool
    let tint: Color?
    let isLifted: Bool
    let shape: S

    @Environment(\.settingsSurfaceIsFlat) private var isFlat

    private var wash: Color {
        (tint ?? .primary).opacity(isActive ? 0.07 : 0.04)
    }

    private var outline: Color {
        (tint ?? .primary).opacity(isActive ? 0.20 : 0.12)
    }

    func body(content: Content) -> some View {
        if isFlat {
            content
                .background(shape.fill(wash))
                .overlay { shape.strokeBorder(outline, lineWidth: 1) }
                .contentShape(shape)
        } else {
            content.controlGlassSurface(isActive: isActive, tint: tint, isLifted: isLifted, in: shape)
        }
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    @Environment(\.settingsSectionLit) private var isLit
    @Environment(\.settingsIsCompact) private var isCompact

    private var inset: CGFloat {
        isCompact ? SettingsMetrics.compactCardInset : SettingsMetrics.cardInset
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .environment(\.settingsCardInset, inset)
        .environment(\.settingsSectionLit, false)
        .padding(.horizontal, inset)
        .padding(.vertical, SettingsMetrics.cardInsetV)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isLit ? Theme.Wash.hover : Theme.Wash.faint,
            in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        )
        .animation(.easeOut(duration: 0.28), value: isLit)
    }
}

private struct SettingsRowTarget: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }
}

extension View {
    func settingsRowTarget() -> some View {
        modifier(SettingsRowTarget())
    }
}

struct SettingsPageHeader: View {
    @Environment(\.settingsDescriptionLineLimit) private var descriptionLineLimit
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
                        .lineLimit(descriptionLineLimit)
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
    @Environment(\.settingsDescriptionLineLimit) private var descriptionLineLimit
    let title: LocalizedStringResource
    let symbol: String
    var footnote: LocalizedStringResource?
    var isLongList = false
    @ViewBuilder let accessory: Accessory
    @ViewBuilder let content: Content

    @Environment(\.settingsIsCompact) private var isCompact

    init(
        title: LocalizedStringResource,
        symbol: String,
        footnote: LocalizedStringResource? = nil,
        isLongList: Bool = false,
        @ViewBuilder content: () -> Content
    ) where Accessory == EmptyView {
        self.title = title
        self.symbol = symbol
        self.footnote = footnote
        self.isLongList = isLongList
        self.accessory = EmptyView()
        self.content = content()
    }

    init(
        title: LocalizedStringResource,
        symbol: String,
        footnote: LocalizedStringResource? = nil,
        isLongList: Bool = false,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.symbol = symbol
        self.footnote = footnote
        self.isLongList = isLongList
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.headerGap) {
            Group {
                if isCompact, Accessory.self != EmptyView.self {
                    VStack(alignment: .leading, spacing: 8) {
                        heading
                        accessory
                    }
                } else {
                    HStack(spacing: 6) {
                        heading
                        Spacer(minLength: 8)
                        accessory
                    }
                }
            }
            .foregroundStyle(.secondary)

            if isLongList {
                SettingsList { content }
            } else {
                SettingsCard { content }
            }

            if let footnote {
                Text(footnote)
                    .lineLimit(descriptionLineLimit)
                    .font(Theme.Font.label)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 1)
            }
        }
    }
}

extension SettingsSection {
    @ViewBuilder
    fileprivate var heading: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(Theme.Font.caption)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .kerning(0.3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct DetailRow<Content: View>: View {
    @Environment(\.settingsDescriptionLineLimit) private var descriptionLineLimit
    enum Layout {
        case trailing
        case stacked
    }

    private var title: Text?
    private var caption: Text?
    var layout: Layout = .trailing
    var isMuted = false
    var controlWidth: CGFloat? = SettingsMetrics.controlWidth

    @ViewBuilder let content: Content

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.settingsIsCompact) private var isCompact

    init(
        title: LocalizedStringResource? = nil,
        caption: LocalizedStringResource? = nil,
        layout: Layout = .trailing,
        controlWidth: CGFloat? = SettingsMetrics.controlWidth,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title.map(Text.init)
        self.caption = caption.map(Text.init)
        self.layout = layout
        self.controlWidth = controlWidth
        self.content = content()
    }

    init(
        title: LocalizedStringResource,
        attributedCaption: AttributedString,
        isMuted: Bool = false,
        layout: Layout = .trailing,
        @ViewBuilder content: () -> Content
    ) {
        self.title = Text(title)
        caption = Text(attributedCaption)
        self.isMuted = isMuted
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
            switch isCompact ? .stacked : layout {
            case .trailing:
                HStack(alignment: .center, spacing: 24) {
                    label
                        .frame(maxWidth: .infinity, alignment: .leading)

                    trailingContent
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
    private var trailingContent: some View {
        if let controlWidth {
            content
                .frame(maxWidth: controlWidth, alignment: .trailing)
        } else {
            content
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var isLit: Bool {
        isEnabled && !isMuted
    }

    @ViewBuilder
    private var label: some View {
        if title != nil || caption != nil {
            VStack(alignment: .leading, spacing: 3) {
                if let title {
                    title
                        .font(Theme.Font.rowTitle)
                        .foregroundStyle(isLit ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                }

                if let caption {
                    caption
                        .lineLimit(descriptionLineLimit)
                        .font(Theme.Font.secondary)
                        .foregroundStyle(isLit ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

extension View {
    func separated(above: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if above {
                RowSeparator()
            }
            self
        }
    }
}

struct RowSeparator: View {
    var inset: CGFloat = SettingsMetrics.separatorInset

    var body: some View {
        Rectangle()
            .fill(SettingsMetrics.hairline)
            .frame(height: 1)
            .padding(.horizontal, inset)
    }
}
