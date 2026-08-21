// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

extension AskSurface.Placement {
    var accessibilityLabel: LocalizedStringResource {
        switch self {
        case .toolbar:
            "Address and search"
        case .startPage:
            "Search or ask"
        }
    }
}

struct AskSurfaceRow: View {
    let model: AskSurfaceModel
    let sections: [OmniboxSection]
    let restingContent: AskRestingContent?
    let placeholder: String
    let accessibilityValue: String
    let security: PageSecurity

    private static let centredAddressInset: CGFloat = 78

    var body: some View {
        @Bindable var model = model
        let placement = model.placement

        HStack(alignment: .top, spacing: placement.controlSpacing) {
            MicButton(coordinator: model.coordinator, orbSize: placement.orbSize)
                .padding(.leading, placement == .startPage ? 4 : 0)
                .frame(width: placement.iconSlot, height: placement.rowHeight)

            ZStack(alignment: .leading) {
                MentionField(
                    text: $model.interaction.text,
                    chips: model.mentionChips,
                    placeholder: placeholder,
                    fontSize: placement.textSize,
                    isFocused: model.isFocused,
                    selectAllToken: model.selectAllToken,
                    accessibilityLabel: String(localized: placement.accessibilityLabel),
                    onFocusChange: { model.fieldFocusDidChange($0) },
                    onChipsChange: { model.mentionsDidChange($0) },
                    onSubmit: { model.submit(in: sections) },
                    onCommandSubmit: { model.askWhateverIsTyped() },
                    onCancel: { model.cancelEditing() },
                    onMove: { delta, bySection in
                        if bySection {
                            model.moveSection(by: delta, in: sections)
                        } else {
                            model.moveSelection(by: delta, in: sections)
                        }
                    }
                )
                .opacity(restingContent == nil ? 1 : 0)
                .allowsHitTesting(restingContent == nil)
                .accessibilityValue(Text(verbatim: accessibilityValue))

                if let restingContent, !restingContent.isCentred {
                    AskRestingLine(
                        placement: placement,
                        content: restingContent,
                        security: security
                    )
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 5)
            .frame(minHeight: placement.rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { model.focusForEditing() }

            HStack(spacing: placement.controlSpacing) {
                if placement.showsSiteControls {
                    PinBadge(browser: model.browser)
                        .frame(width: placement.iconSlot)
                    PermissionBadge(browser: model.browser)
                        .frame(width: placement.iconSlot)
                    SiteControlsMenu(browser: model.browser, coordinator: model.coordinator)
                        .frame(width: placement.iconSlot)
                    TabPictureBadge(browser: model.browser, coordinator: model.coordinator)
                        .frame(width: placement.iconSlot)
                    TabAudioBadge(browser: model.browser, coordinator: model.coordinator)
                        .frame(width: placement.iconSlot)
                }

                if placement.showsKeyHints, !model.isListening {
                    AskKeyHints(
                        typed: model.interaction.trimmedText,
                        agentOnly: model.agentOnly,
                        onReturn: { model.submit(in: sections) },
                        onCommandReturn: { model.askWhateverIsTyped() }
                    )
                    .fixedSize()
                }
            }
            .frame(height: placement.rowHeight)
        }
        .padding(.horizontal, placement.rowInset)
        .overlay {
            if let restingContent, restingContent.isCentred {
                AskRestingLine(
                    placement: placement,
                    content: restingContent,
                    security: security
                )
                .padding(.horizontal, Self.centredAddressInset)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .frame(minHeight: placement.rowHeight)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
            model.interaction.rowHeight = $0
        }
    }
}

struct AskSurfaceAddressMenu: View {
    let model: AskSurfaceModel

    var body: some View {
        if model.placement.mirrorsPageURL {
            Button {
                model.coordinator.copyCurrentURL()
            } label: {
                Label("Copy Link", systemImage: "doc.on.doc")
            }
            .disabled(model.currentURL.isEmpty)

            if let pastedText {
                Button {
                    model.replaceTextAndFocus(pastedText)
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }

                Button {
                    model.navigate(pastedText)
                } label: {
                    Label(pasteTitle(for: pastedText), systemImage: pasteSymbol(for: pastedText))
                }
            }
        }
    }

    private var pastedText: String? {
        let value = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    private func pasteTitle(for text: String) -> LocalizedStringResource {
        Omnibox.location(for: text) == nil ? "Paste and Search" : "Paste and Go"
    }

    private func pasteSymbol(for text: String) -> String {
        Omnibox.location(for: text) == nil ? "magnifyingglass" : "arrow.right.doc.on.clipboard"
    }
}
