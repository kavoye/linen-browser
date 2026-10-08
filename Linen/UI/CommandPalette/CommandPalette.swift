// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct CommandPalette: View {
    let browser: BrowserModel
    let coordinator: AppCoordinator
    let containerSize: CGSize
    let dismiss: () -> Void

    @State private var model: CommandPaletteModel?

    var body: some View {
        if let model {
            CommandPalettePanel(model: model, containerSize: containerSize)
        } else {
            Color.clear
                .onAppear {
                    model = CommandPaletteModel(browser: browser, coordinator: coordinator, dismiss: dismiss)
                }
        }
    }
}

private struct CommandPalettePanel: View {
    let model: CommandPaletteModel
    let containerSize: CGSize

    @State private var shortcutMonitor: Any?
    @State private var focused = false
    @State private var optionHeld = false

    var body: some View {
        @Bindable var model = model
        let layout = CommandPaletteLayout(containerSize: containerSize)

        VStack(spacing: 0) {
            CommandPaletteField(
                placeholder: model.placeholder,
                query: $model.interaction.query,
                chips: model.mentionChips,
                focused: $focused,
                onSubmit: model.submit,
                onCommandSubmit: model.askWhateverIsTyped,
                onMoveSelection: model.moveSelection,
                onMoveSection: model.moveSection,
                onChipsChange: model.mentionsDidChange,
                onDismiss: model.dismiss,
                searchSite: model.searchSite,
                suggestedSite: model.suggestedSite,
                onActivateSite: model.activateSiteSearch,
                onRemoveSite: model.removeSearchSite
            )
            .frame(height: CommandPaletteLayout.fieldHeight)

            CommandPaletteResultsView(
                sections: model.sections,
                query: model.resultQuery,
                selection: model.interaction.selection,
                optionHeld: optionHeld,
                maxHeight: layout.maxListHeight,
                onSelect: model.hoverSuggestion,
                onRun: model.run,
                onRunAlternate: model.runAlternate
            )

            AskContextStrip(pages: model.contextPages)
        }
        .frame(width: layout.panelWidth)
        .background {
            CommandPaletteGlass(referenceHeight: CommandPaletteLayout.fieldHeight + layout.maxListHeight)
        }
        .shadow(color: .black.opacity(0.4), radius: 44, y: 18)
        .padding(.top, layout.topInset)
        .onAppear {
            optionHeld = CommandPaletteShortcutPolicy.showsCurrentTab(modifiers: NSEvent.modifierFlags)
            model.prepare()
            watchForShortcuts(model: model)
        }
        .task {
            focused = true
        }
        .onDisappear {
            if let shortcutMonitor {
                NSEvent.removeMonitor(shortcutMonitor)
                self.shortcutMonitor = nil
            }
        }
        .modifier(CommandPaletteSuggestionSync(
            suggestions: model.suggestions,
            onChange: model.suggestionsDidChange
        ))
        .onKeyPress(.escape) {
            model.dismiss()
            return .handled
        }
    }

    private func watchForShortcuts(model: CommandPaletteModel) {
        guard shortcutMonitor == nil else { return }
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .flagsChanged {
                MainActor.assumeIsolated {
                    optionHeld = CommandPaletteShortcutPolicy.showsCurrentTab(modifiers: event.modifierFlags)
                }
                return event
            }
            let key = event.charactersIgnoringModifiers ?? ""
            if CommandPaletteShortcutPolicy.opensInCurrentTab(modifiers: event.modifierFlags, key: key) {
                MainActor.assumeIsolated { model.submitInCurrentTab() }
                return nil
            }
            if CommandPaletteShortcutPolicy.shouldDismiss(event) {
                MainActor.assumeIsolated { model.dismiss() }
            }
            return event
        }
    }
}
