// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct AskSurface: View {
    enum Placement: Equatable {
        case toolbar
        case startPage

        var rowHeight: CGFloat {
            self == .toolbar ? 36 : 44
        }
        var orbSize: CGFloat {
            self == .toolbar ? 18 : 26
        }
        var cornerRadius: CGFloat {
            Theme.Radius.card
        }
        var textSize: CGFloat {
            self == .toolbar ? 12.5 : 13.5
        }
        var rowInset: CGFloat {
            self == .toolbar ? 6 : 8
        }
        var controlSpacing: CGFloat {
            self == .toolbar ? 6 : 10
        }
        var iconSlot: CGFloat {
            orbSize + 2
        }
        var messageLineLimit: Int {
            self == .toolbar ? 4 : 6
        }
        var placeholder: String {
            String(localized: "Search, “@” to ask, or paste a link")
        }
        var mirrorsPageURL: Bool {
            self == .toolbar
        }
        var showsSiteControls: Bool {
            self == .toolbar
        }
        var showsKeyHints: Bool {
            self == .startPage
        }
        var usesMaterial: Bool {
            self == .toolbar
        }
        var takesFocusOnAppear: Bool {
            self == .startPage
        }
        var liftRadius: CGFloat {
            self == .toolbar ? 14 : 22
        }
        var liftOffset: CGFloat {
            self == .toolbar ? 4 : 8
        }
    }

    @State private var model: AskSurfaceModel

    init(placement: Placement, browser: BrowserModel, coordinator: AppCoordinator) {
        _model = State(initialValue: AskSurfaceModel(
            placement: placement,
            browser: browser,
            coordinator: coordinator
        ))
    }

    var body: some View {
        let sections = model.resultSections()
        let activity = model.activity
        let restingContent = model.restingContent
        let status = surfaceStatus(activity: activity)
        let overhangs = model.interaction.rowHeight > model.placement.rowHeight + 1
        let contextPages = sections.contains { $0.id == "ask" } ? model.contextPages : []
        let isRaised = model.isFocused || !sections.isEmpty || overhangs
        let restingShadow = model.placement.usesMaterial
            ? (opacity: 0.10, radius: CGFloat(3), y: CGFloat(1))
            : (opacity: 0.0, radius: CGFloat(0), y: CGFloat(0))

        VStack(spacing: 0) {
            AskSurfaceRow(
                model: model,
                sections: sections,
                restingContent: restingContent,
                placeholder: model.placeholder,
                accessibilityValue: model.accessibilityValue,
                security: model.security
            )
            .contentShape(Rectangle())
            .contextMenu {
                AskSurfaceAddressMenu(model: model)
            }

            if !sections.isEmpty {
                Divider()
                    .padding(.horizontal, 12)

                OmniboxList(
                    sections: sections,
                    query: model.interaction.text,
                    selection: model.interaction.selection,
                    density: .compact,
                    containerRadius: model.placement.cornerRadius,
                    onSelect: { model.interaction.selection = $0 },
                    onRun: { model.run(at: $0, in: sections) }
                )
                .transition(.opacity)
            }

            AskContextStrip(pages: contextPages)
        }
        .frame(maxWidth: .infinity)
        .background {
            AskSurfaceBackdrop(
                placement: model.placement,
                status: status,
                isPrivate: model.isPrivate,
                isFocused: model.isFocused,
                hasResults: !sections.isEmpty,
                overhangs: overhangs,
                isThinking: activity.isThinking,
                isRunning: activity.isRunning
            )
        }
        .modifier(AskSurfaceMaterial(
            placement: model.placement,
            tint: status?.color,
            cornerRadius: model.placement.cornerRadius,
            isPrivate: model.isPrivate
        ))
        .overlay {
            AskSurfaceBorder(
                cornerRadius: model.placement.cornerRadius,
                isPrivate: model.isPrivate,
                status: status,
                isFocused: model.isFocused
            )
        }
        .transformEnvironment(\.colorScheme) { if model.isPrivate { $0 = .dark } }
        .transformEnvironment(\.chromeIsLight) { if model.isPrivate { $0 = false } }
        .contentShape(RoundedRectangle(cornerRadius: model.placement.cornerRadius))
        .compositingGroup()
        .shadow(
            color: .black.opacity(isRaised ? 0.34 : restingShadow.opacity),
            radius: isRaised ? model.placement.liftRadius : restingShadow.radius,
            y: isRaised ? model.placement.liftOffset : restingShadow.y
        )
        .fixedSize(horizontal: false, vertical: true)
        .frame(height: model.placement.rowHeight, alignment: .top)
        .animation(Theme.Motion.settle, value: model.isFocused)
        .animation(Theme.Motion.settle, value: model.isListening)
        .animation(Theme.Motion.drift, value: status)
        .animation(Theme.Motion.settle, value: model.agentMessage)
        .animation(Theme.Motion.settle, value: model.coordinator.notice)
        .onAppear { model.prepare() }
        .task {
            guard model.placement.takesFocusOnAppear else { return }
            try? await Task.sleep(for: .milliseconds(120))
            model.fieldFocusDidChange(true)
        }
        .onChange(of: model.currentURL) { _, url in
            model.currentURLDidChange(url)
        }
        .onChange(of: model.activeTabID) { _, _ in
            model.activeTabDidChange()
        }
        .onChange(of: model.coordinator.addressBarFocusToken) { _, _ in
            model.focusFromAddressCommand()
        }
    }

    private func surfaceStatus(activity: AskSurfaceActivity) -> AskSurfaceStatus? {
        if model.isListening {
            return .listening
        }
        if model.coordinator.statusMessage != nil {
            return .warning
        }
        if activity.isRunning {
            return .agent
        }
        return nil
    }
}
