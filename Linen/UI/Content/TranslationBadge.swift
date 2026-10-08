// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct TranslationBadge: View {
    let browser: BrowserModel
    let coordinator: AppCoordinator

    private var tab: BrowserTab? {
        guard let tab = browser.activeTab, tab.isMaterialised, !tab.isShowingSystemPage,
              tab.translation.isActive || !tab.translation.targets.isEmpty
        else { return nil }
        return tab
    }

    var body: some View {
        Group {
            if let tab {
                TranslationMenu(tab: tab, coordinator: coordinator)
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.7), value: tab?.id)
    }
}

private struct TranslationMenu: View {
    let tab: BrowserTab
    let coordinator: AppCoordinator

    @State private var hovering = false
    @Environment(\.chromeIsLight) private var chromeIsLight
    @Environment(\.chromeIconExtent) private var extent

    private var translation: PageTranslation {
        tab.translation
    }

    private var settings: BrowserSettings {
        tab.context.settings
    }

    private var style: AnyShapeStyle {
        guard translation.isActive else {
            return ChromeInk.glyph(onLight: chromeIsLight, hovering: hovering)
        }
        return AnyShapeStyle(chromeIsLight ? Theme.systemAccent.deepened(by: 0.28) : Theme.systemAccent)
    }

    private func isShowing(_ language: Locale.Language) -> Bool {
        guard translation.isActive, let target = translation.target else { return false }
        return TranslationLanguage.matches(target, language)
    }

    var body: some View {
        Menu {
            ForEach(translation.targets, id: \.self) { language in
                Button {
                    coordinator.translatePage(tab, to: language)
                } label: {
                    Text("Translate to \(TranslationLanguage.name(language))")
                }
                .disabled(isShowing(language))
            }

            Button {
                coordinator.openPreferredLanguages()
            } label: {
                Text("Preferred Languages…")
            }

            Divider()

            Button {
                coordinator.showOriginal(tab)
            } label: {
                Text("View Original")
            }
            .disabled(!translation.isActive)

            if let source = translation.detectedLanguage {
                Toggle(isOn: Binding(
                    get: { settings.alwaysTranslates(source) },
                    set: { settings.setAlwaysTranslates($0, source) }
                )) {
                    Text("Always Translate \(TranslationLanguage.name(source))")
                }
            }
        } label: {
            Image(systemName: "translate")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(style)
                .frame(width: extent, height: extent)
                .hoverBackground(isActive: hovering)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
        .help("Translate Page")
    }
}
