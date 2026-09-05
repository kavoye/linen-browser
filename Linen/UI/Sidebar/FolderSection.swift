// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct FolderSection: View {
    let folder: TabFolder
    let depth: Int
    let context: SidebarRowContext

    @State private var isRenaming = false
    @State private var draftName = ""
    @FocusState private var renameFocused: Bool

    @Environment(\.sidebarStyle) private var sidebarStyle
    @Environment(\.windowColorScheme) private var windowColorScheme
    @State private var hovering = false
    @State private var windowFrame: CGRect = .zero

    private var browser: BrowserModel {
        context.browser
    }
    private var item: SidebarItem {
        .folder(folder.id)
    }
    private var isSelected: Bool {
        context.isSelected(item)
    }

    static let outlineInset: CGFloat = 2

    static let tintOpacity: Double = 0.11
    static let fillOpacity: Double = 0.03
    static let edgeOpacity: Double = 0.14

    static func outlineRadius(depth: Int) -> CGFloat {
        var radius = Theme.Radius.control
        for _ in 0..<max(depth, 0) {
            radius = Theme.Radius.nested(in: radius, inset: outlineInset)
        }
        return radius
    }

    static func rowRadius(depth: Int) -> CGFloat {
        Theme.Radius.nested(in: outlineRadius(depth: depth), inset: outlineInset)
    }

    private var outlineRadius: CGFloat {
        Self.outlineRadius(depth: depth)
    }

    private var audibleTab: BrowserTab? {
        guard !folder.isExpanded else { return nil }
        return browser.allTabs(in: folder).first { $0.isPlayingAudio }
    }

    @ViewBuilder
    private func countBadge(_ count: Int) -> some View {
        if count == 0 {
            Text("empty")
        } else {
            Text(count, format: .number)
        }
    }

    var body: some View {
        let rows = browser.rows(in: folder)
        let audible = audibleTab
        let showsOutline = folder.isExpanded && !rows.isEmpty

        VStack(spacing: 1) {
            HStack(spacing: 7) {
                Image(systemName: audible == nil
                    ? (folder.isExpanded ? "folder" : "folder.fill")
                    : "speaker.wave.2.fill")
                    .font(Theme.Font.caption)
                    .foregroundStyle(folder.color.tint)
                    .contentTransition(.symbolEffect(.replace))
                    .animation(Theme.Motion.settle, value: audible?.id)
                    .help(audible.map { Text("“\($0.title)” is playing") } ?? Text(verbatim: ""))

                if sidebarStyle == .icons {
                    EmptyView()
                } else if isRenaming {
                    TextField("", text: $draftName)
                        .fieldPlaceholder("Folder name", isShowing: draftName.isEmpty)
                        .textFieldStyle(.plain)
                        .font(Theme.Font.control)
                        .focused($renameFocused)
                        .onSubmit(commitRename)
                        .onKeyPress(.escape) {
                            isRenaming = false
                            renameFocused = false
                            return .handled
                        }
                        .onChange(of: renameFocused) { _, focused in
                            if !focused {
                                commitRename()
                            }
                        }
                } else {
                    Text(verbatim: folder.name)
                        .font(Theme.Font.control)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if sidebarStyle == .full {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .rotationEffect(.degrees(folder.isExpanded ? 90 : 0))
                        .foregroundStyle(.tertiary)

                    Spacer(minLength: 0)
                    countBadge(rows.count)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Theme.Wash.hairline, in: Capsule())
                }
            }
            .padding(.horizontal, SidebarMetrics.rowContentPadding(style: sidebarStyle))
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .sidebarRowSelectionEffect(
                isSelected: isSelected,
                isHovering: hovering,
                hoverTint: folder.color.tint,
                radius: showsOutline ? Self.rowRadius(depth: depth) : Theme.Radius.hover
            )
            .contentShape(Rectangle())
            .onHover { over in
                hovering = over
                if over {
                    context.coordinator.tabPreview.hover(
                        .folder(folder, browser.tabs(in: folder)),
                        anchor: windowFrame
                    )
                } else {
                    context.coordinator.tabPreview.unhover(folder.id)
                }
            }
            .onDisappear { context.coordinator.tabPreview.unhover(folder.id) }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(context.space)) } action: {
                context.frames.record(item, at: $0)
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                windowFrame = frame
                context.coordinator.tabPreview.moved(folder.id, anchor: frame)
            }
            .onTapGesture { tapped() }
            .overlay {
                FolderContextMenuCatcher {
                    FolderContextMenu.make(
                        folder: folder,
                        browser: browser,
                        coordinator: context.coordinator,
                        selected: context.selection.count > 1 && isSelected
                            ? Array(context.selection.items)
                            : [],
                        onRename: beginRename
                    )
                }
            }

            if folder.isExpanded {
                contents
            }
        }
        .padding(showsOutline ? Self.outlineInset : 0)
        .background {
            if showsOutline {
                let shape = RoundedRectangle(cornerRadius: outlineRadius, style: .continuous)
                ZStack {
                    Color.clear
                        .glassEffect(
                            .clear.tint(folder.color.tint.opacity(Self.tintOpacity)),
                            in: shape
                        )
                    shape.fill(folder.color.tint.opacity(Self.fillOpacity))
                    shape.strokeBorder(
                        folder.color.tint.opacity(Self.edgeOpacity),
                        lineWidth: 1
                    )
                }
                .environment(\.colorScheme, windowColorScheme)
            }
        }
        .opacity(context.isLifted(item) ? 0 : 1)
    }

    private var contents: AnyView {
        AnyView(SidebarRows(items: browser.rows(in: folder), depth: depth + 1, context: context))
    }

    private func tapped() {
        let modifiers = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.shift) {
            context.selection.hold(context.activeItem)
            context.selection.extend(to: item, in: browser.sidebarTree) {
                browser.folder(id: $0)?.isExpanded ?? false
            }
        } else if modifiers.contains(.command) {
            context.selection.hold(context.activeItem)
            context.selection.toggle(item)
        } else {
            context.selection.anchor(on: item)
            withAnimation(Theme.Motion.settle) {
                folder.isExpanded.toggle()
            }
        }
    }

    private func beginRename() {
        draftName = folder.name
        isRenaming = true
        renameFocused = true
    }

    private func commitRename() {
        guard isRenaming else { return }
        isRenaming = false
        browser.renameFolder(folder, to: draftName)
    }
}

@MainActor
private enum FolderContextMenu {
    static func make(
        folder: TabFolder,
        browser: BrowserModel,
        coordinator: AppCoordinator,
        selected: [SidebarItem],
        onRename: @escaping () -> Void
    ) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        if !selected.isEmpty {
            addSelectionItems(selected, to: menu, browser: browser, coordinator: coordinator)
            return menu
        }

        menu.addItem(actionItem(
            title: String(localized: "Rename"),
            symbol: "pencil",
            action: onRename
        ))
        menu.addItem(.separator())

        let colors = NSMenuItem()
        colors.view = FolderColorMenuItemView(selected: folder.color) { [weak browser, weak folder] color in
            guard let browser, let folder else { return }
            browser.setFolderColor(color, for: folder)
        }
        menu.addItem(colors)
        menu.addItem(.separator())

        addFolderItems([.folder(folder.id)], to: menu, browser: browser)
        menu.addItem(.separator())

        let kept = browser.allTabs(in: folder).count
        if kept > 0 {
            menu.addItem(closeTabsItem([.folder(folder.id)], count: kept, browser: browser))
        }
        menu.addItem(actionItem(
            title: String(localized: "Delete Folder…"),
            symbol: "trash",
            action: { [weak browser, weak folder] in
                guard let browser, let folder else { return }
                let kept = browser.allTabs(in: folder).count
                let detail: LocalizedStringResource = switch kept {
                case 0:
                    "The folder is empty."
                default:
                    "Its \(kept) tabs stay in the sidebar."
                }
                Task {
                    guard await ConfirmAlert.destructive(
                        "Delete “\(folder.name)”?",
                        detail: detail,
                        verb: "Delete Folder"
                    ) else { return }
                    browser.deleteFolder(folder)
                }
            }
        ))
        return menu
    }

    private static func addSelectionItems(
        _ selected: [SidebarItem],
        to menu: NSMenu,
        browser: BrowserModel,
        coordinator: AppCoordinator
    ) {
        let linkable = browser.tabs(under: selected).filter { coordinator.linkURL(for: $0) != nil }
        if !linkable.isEmpty {
            let title: LocalizedStringResource = linkable.count == 1 ? "Copy Link" : "Copy Links"
            menu.addItem(actionItem(
                title: String(localized: title),
                symbol: "doc.on.doc",
                action: { [weak coordinator] in coordinator?.copyLinks(for: linkable) }
            ))
            menu.addItem(.separator())
        }

        addFolderItems(selected, to: menu, browser: browser)
        menu.addItem(.separator())

        menu.addItem(closeTabsItem(
            selected,
            count: browser.tabCount(in: selected),
            browser: browser
        ))
    }

    private static func addFolderItems(
        _ items: [SidebarItem],
        to menu: NSMenu,
        browser: BrowserModel
    ) {
        let move = NSMenu()
        move.autoenablesItems = false
        let targets = browser.folders.filter { browser.sidebarTree.canHold($0.id, items) }
        for folder in targets {
            let target = folder
            move.addItem(actionItem(
                title: folder.name,
                symbol: "folder",
                action: { [weak browser, weak target] in
                    guard let browser, let target else { return }
                    browser.move(items, into: target)
                }
            ))
        }
        if !targets.isEmpty {
            move.addItem(.separator())
        }
        move.addItem(actionItem(
            title: String(localized: "New Folder…"),
            symbol: "folder.badge.plus",
            action: { [weak browser] in browser?.createFolder(containing: items) }
        ))
        let moveItem = NSMenuItem(title: String(localized: "Move to Folder"), action: nil, keyEquivalent: "")
        moveItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        moveItem.submenu = move
        menu.addItem(moveItem)

        if items.contains(where: { browser.sidebarTree.parent(of: $0) != nil }) {
            menu.addItem(actionItem(
                title: String(localized: "Remove from Folder"),
                symbol: "folder.badge.minus",
                action: { [weak browser] in browser?.moveOut(items) }
            ))
        }
    }

    private static func closeTabsItem(
        _ items: [SidebarItem],
        count: Int,
        browser: BrowserModel
    ) -> NSMenuItem {
        actionItem(
            title: String(localized: "Close \(count) Tabs"),
            symbol: "xmark",
            action: { [weak browser] in
                guard let browser else { return }
                Task {
                    guard await ConfirmAlert.destructive(
                        "Close \(count) tabs?",
                        verb: "Close Tabs"
                    ) else { return }
                    browser.close(items)
                }
            }
        )
    }

    private static func actionItem(
        title: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> NSMenuItem {
        let target = FolderMenuAction(action)
        let item = NSMenuItem(
            title: title,
            action: #selector(FolderMenuAction.runFolderMenuAction),
            keyEquivalent: ""
        )
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        item.target = target
        item.representedObject = target
        item.isEnabled = true
        return item
    }
}

private final class FolderMenuAction: NSObject {
    private let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }

    @objc func runFolderMenuAction() {
        action()
    }
}

private struct FolderContextMenuCatcher: NSViewRepresentable {
    let menu: () -> NSMenu

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.menuProvider = menu
        return view
    }

    func updateNSView(_ nsView: CatcherView, context: Context) {
        nsView.menuProvider = menu
    }

    final class CatcherView: NSView {
        var menuProvider: (() -> NSMenu)?

        override var mouseDownCanMoveWindow: Bool {
            false
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard bounds.contains(point),
                  let event = window?.currentEvent ?? NSApp.currentEvent
            else { return nil }

            if event.type == .rightMouseDown {
                return self
            }
            if event.type == .leftMouseDown, event.modifierFlags.contains(.control) {
                return self
            }
            return nil
        }

        override func rightMouseDown(with event: NSEvent) {
            presentMenu(for: event)
        }

        override func mouseDown(with event: NSEvent) {
            guard event.modifierFlags.contains(.control) else { return }
            presentMenu(for: event)
        }

        private func presentMenu(for event: NSEvent) {
            guard let menu = menuProvider?() else { return }
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
    }
}

private final class FolderColorMenuItemView: NSView {
    private let choose: (TabFolderColor) -> Void

    init(selected: TabFolderColor, choose: @escaping (TabFolderColor) -> Void) {
        self.choose = choose
        super.init(frame: NSRect(x: 0, y: 0, width: 176, height: 30))

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fillEqually
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false

        for (index, color) in TabFolderColor.finderPalette.enumerated() {
            let button = NSButton(
                image: color.menuSwatch(isSelected: color == selected),
                target: self,
                action: #selector(selectColor(_:))
            )
            button.tag = index
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.setButtonType(.momentaryChange)
            button.toolTip = String(localized: color.title)
            button.setAccessibilityLabel(String(localized: color.title))
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 18).isActive = true
            button.heightAnchor.constraint(equalToConstant: 18).isActive = true
            stack.addArrangedSubview(button)
        }

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 176, height: 30)
    }

    @objc private func selectColor(_ sender: NSButton) {
        guard TabFolderColor.finderPalette.indices.contains(sender.tag) else { return }
        choose(TabFolderColor.finderPalette[sender.tag])
        enclosingMenuItem?.menu?.cancelTracking()
    }
}

extension TabFolderColor {
    static let finderPalette: [Self] = [
        .green, .yellow, .red, .blue, .orange, .purple, .gray,
    ]

    var nsTint: NSColor {
        switch self {
        case .gray:
            .systemGray
        case .blue:
            .systemBlue
        case .purple:
            .systemPurple
        case .pink:
            .systemPink
        case .red:
            .systemRed
        case .orange:
            .systemOrange
        case .yellow:
            .systemYellow
        case .green:
            .systemGreen
        case .teal:
            .systemTeal
        }
    }

    var tint: Color {
        Color(nsTint)
    }

    func menuSwatch(isSelected: Bool) -> NSImage {
        let solid = nsTint.usingColorSpace(.sRGB) ?? nsTint
        let image = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            solid.withAlphaComponent(0.9).setFill()
            circle.fill()
            solid.withAlphaComponent(0.55).setStroke()
            circle.lineWidth = 1
            circle.stroke()

            if isSelected {
                let check = NSBezierPath()
                check.move(to: NSPoint(x: 3.5, y: 7))
                check.line(to: NSPoint(x: 6, y: 4.5))
                check.line(to: NSPoint(x: 10.5, y: 9.5))
                check.lineWidth = 1.35
                check.lineCapStyle = .round
                check.lineJoinStyle = .round
                NSColor.white.setStroke()
                check.stroke()
            }

            return true
        }
        image.isTemplate = false
        return image
    }

    var title: LocalizedStringResource {
        switch self {
        case .gray:
            "Gray"
        case .blue:
            "Blue"
        case .purple:
            "Purple"
        case .pink:
            "Pink"
        case .red:
            "Red"
        case .orange:
            "Orange"
        case .yellow:
            "Yellow"
        case .green:
            "Green"
        case .teal:
            "Teal"
        }
    }
}
