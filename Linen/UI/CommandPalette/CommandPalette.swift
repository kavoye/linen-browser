// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct CommandPalette: View {
    let containerSize: CGSize

    @State private var model: CommandPaletteModel
    @State private var shortcutMonitor: Any?
    @State private var focused = false

    init(
        browser: BrowserModel,
        coordinator: AppCoordinator,
        containerSize: CGSize,
        dismiss: @escaping () -> Void
    ) {
        self.containerSize = containerSize
        _model = State(initialValue: CommandPaletteModel(
            browser: browser,
            coordinator: coordinator,
            dismiss: dismiss
        ))
    }

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
                onCommandSubmit: model.submit,
                onMoveSelection: model.moveSelection,
                onMoveSection: model.moveSection,
                onChipsChange: model.mentionsDidChange,
                onDismiss: model.dismiss
            )
            .frame(height: CommandPaletteLayout.fieldHeight)

            CommandPaletteResultsView(
                sections: model.sections,
                query: model.interaction.query,
                selection: model.interaction.selection,
                maxHeight: layout.maxListHeight,
                onSelect: { model.interaction.selection = $0 },
                onRun: model.run
            )

            AskContextStrip(pages: model.contextPages)
        }
        .frame(width: layout.panelWidth)
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.Radius.panel))
        .shadow(color: .black.opacity(0.4), radius: 44, y: 18)
        .padding(.top, layout.topInset)
        .onAppear {
            model.prepare()
            watchForShortcuts(dismiss: model.dismiss)
        }
        .task {
            focused = true
            try? await Task.sleep(for: .milliseconds(120))
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

    private func watchForShortcuts(dismiss: @escaping () -> Void) {
        guard shortcutMonitor == nil else { return }
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let shouldDismiss = CommandPaletteShortcutPolicy.shouldDismiss(
                modifiers: event.modifierFlags,
                key: event.charactersIgnoringModifiers ?? ""
            )
            if shouldDismiss {
                MainActor.assumeIsolated { dismiss() }
            }
            return event
        }
    }
}
