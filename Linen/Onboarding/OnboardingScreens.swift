// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

extension OnboardingUI {
    struct WelcomeScreen: View {
        let coordinator: AppCoordinator
        let model: OnboardingModel
        let clock: ShimmerClock

        var body: some View {
            Screen {
                WelcomeIntro(model: model) { revealed in
                    VStack(spacing: 0) {
                        Heading(
                            title: "Welcome to Linen",
                            caption: "A quiet browser with an assistant built in."
                        )
                        .introReveal(revealed, delay: 0)

                        Actions(
                            primary: "Continue",
                            primaryAction: {
                                OnboardingUI.advance(model: model, coordinator: coordinator, clock: clock)
                            },
                            secondary: "Skip Setup",
                            secondaryAction: { OnboardingUI.finish(model: model, coordinator: coordinator) }
                        )
                        .introReveal(revealed, delay: 0.12)
                    }
                }
            }
        }
    }

    struct ModelScreen: View {
        let coordinator: AppCoordinator
        let model: OnboardingModel
        let clock: ShimmerClock

        var body: some View {
            Screen {
                Heading(
                    title: "Choose a model",
                    caption: "You can change this later in Settings."
                )

                HStack(alignment: .top, spacing: 14) {
                    ModelChoiceCard(
                        tag: "On Device",
                        title: "Apple Intelligence",
                        caption: "Private, offline, and no API key. Best for short answers.",
                        isSelected: model.modelChoice == .onDevice
                    ) {
                        model.modelChoice = .onDevice
                    }

                    ModelChoiceCard(
                        tag: "API key required",
                        title: "Remote model",
                        caption: "Best for longer, complex tasks. Your key stays in your Keychain.",
                        isSelected: model.modelChoice == .remote
                    ) {
                        model.modelChoice = .remote
                    }
                }
                .frame(width: OnboardingUI.columnWidth)
                .padding(.top, 24)

                Text(AIDisclosure.onboardingCaption)
                    .font(Theme.Font.secondary)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: OnboardingUI.columnWidth)
                    .padding(.top, 16)

                Actions(
                    primary: "Continue",
                    primaryAction: {
                        OnboardingUI.advance(model: model, coordinator: coordinator, clock: clock)
                    },
                    secondary: "Back",
                    secondaryAction: { OnboardingUI.back(model: model) }
                )
            }
        }
    }

    struct ExtensionsScreen: View {
        let coordinator: AppCoordinator
        let model: OnboardingModel
        let clock: ShimmerClock

        var body: some View {
            Screen {
                Heading(
                    title: "Add extensions",
                    caption: "These come from the Chrome and Firefox stores. Visit either store to add more."
                )

                SettingsCard {
                    ForEach(Array(ExtensionPicks.all.enumerated()), id: \.element.id) { index, pick in
                        if index > 0 {
                            RowSeparator()
                        }

                        ExtensionPickRow(manager: coordinator.extensions, pick: pick)
                    }
                }
                .frame(width: OnboardingUI.columnWidth)
                .multilineTextAlignment(.leading)
                .padding(.top, 24)

                Actions(
                    primary: "Continue",
                    primaryAction: {
                        OnboardingUI.advance(model: model, coordinator: coordinator, clock: clock)
                    },
                    secondary: "Back",
                    secondaryAction: { OnboardingUI.back(model: model) }
                )
            }
        }
    }

    struct BookmarksScreen: View {
        let coordinator: AppCoordinator
        let model: OnboardingModel
        let clock: ShimmerClock

        var body: some View {
            Screen {
                Heading(
                    title: "Bring your bookmarks over",
                    caption: "Import bookmarks from another browser, and open links from other apps in Linen."
                )

                SettingsCard {
                    BookmarkImportRow(
                        browser: coordinator.browser,
                        caption: "An HTML file from another browser.",
                        actionWidth: OnboardingUI.actionWidth
                    )

                    RowSeparator()

                    DetailRow(
                        title: "Default browser",
                        caption: "Open links from other apps in Linen."
                    ) {
                        SettingsButton(
                            title: "Set as Default",
                            minWidth: OnboardingUI.actionWidth
                        ) {
                            model.requestDefaultBrowser()
                        }
                    }
                }
                .frame(width: OnboardingUI.columnWidth)
                .multilineTextAlignment(.leading)
                .padding(.top, 24)

                if model.handedOverToSystemSettings {
                    Text("In System Settings, choose Linen as the default web browser.")
                        .font(Theme.Font.label)
                        .foregroundStyle(.secondary)
                        .padding(.top, 10)
                }

                Actions(
                    primary: "Continue",
                    primaryAction: {
                        OnboardingUI.advance(model: model, coordinator: coordinator, clock: clock)
                    },
                    secondary: "Back",
                    secondaryAction: { OnboardingUI.back(model: model) }
                )
            }
        }
    }

    struct FinishScreen: View {
        let coordinator: AppCoordinator
        let model: OnboardingModel

        @State private var revealed = false

        var body: some View {
            Screen {
                AppMark(size: 64)
                    .padding(.bottom, 24)
                    .introReveal(revealed, delay: 0)

                Heading(title: "You’re set", caption: "Three things to try.")
                    .introReveal(revealed, delay: 0.08)

                FirstMoves()
                    .padding(.top, 26)
                    .introReveal(revealed, delay: 0.16)

                Actions(
                    primary: "Start Browsing",
                    primaryAction: { OnboardingUI.finish(model: model, coordinator: coordinator) },
                    secondary: "Back",
                    secondaryAction: { OnboardingUI.back(model: model) }
                )
                .introReveal(revealed, delay: 0.24)
            }
            .task { revealed = true }
        }
    }

    struct FirstMoves: View {
        private struct Move: Identifiable {
            let id: String
            let symbol: String
            let text: LocalizedStringResource
        }

        private static let moves: [Move] = [
            .init(
                id: "search",
                symbol: "magnifyingglass",
                text: "Press ⌘K to search, open a page, or ask a question."
            ),
            .init(
                id: "summary",
                symbol: "cursorarrow",
                text: "Hold Shift and point at a link to read what the page says."
            ),
            .init(
                id: "peek",
                symbol: "rectangle.on.rectangle",
                text: "Hold Shift and click a link to read it over the page."
            ),
        ]

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Self.moves) { move in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Image(systemName: move.symbol)
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                            .frame(width: 18)
                            .accessibilityHidden(true)

                        Text(move.text)
                            .font(Theme.Font.row)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension OnboardingUI {
    struct ExtensionPickRow: View {
        let manager: ExtensionManager
        let pick: ExtensionPick

        var body: some View {
            HStack(spacing: 12) {
                Image(systemName: pick.symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                    .accessibilityHidden(true)

                DetailRow(verbatimTitle: pick.name, verbatimCaption: caption) {
                    control
                }
            }
        }

        private var caption: String {
            if case .failed(let id, let message) = manager.installState, id == pick.id {
                return message
            }
            return String(localized: pick.caption)
        }

        private var isInstalling: Bool {
            manager.installState == .installing(id: pick.id)
        }

        @ViewBuilder
        private var control: some View {
            Group {
                if isInstalling {
                    Spinner(size: 12)
                        .foregroundStyle(.secondary)
                } else if manager.isInstalled(pick.id) {
                    SettingsButton(title: "Added", minWidth: OnboardingUI.actionWidth) {}
                        .disabled(true)
                } else {
                    SettingsButton(title: "Add", minWidth: OnboardingUI.actionWidth) {
                        Task { await manager.install(id: pick.id, from: pick.store) }
                    }
                }
            }
            .frame(width: OnboardingUI.actionWidth, alignment: .trailing)
        }
    }
}

extension OnboardingUI {
    struct Screen<Content: View>: View {
        let content: Content

        init(@ViewBuilder content: () -> Content) {
            self.content = content()
        }

        var body: some View {
            VStack(spacing: 0) {
                content
            }
            .multilineTextAlignment(.center)
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    struct Heading: View {
        let title: LocalizedStringKey
        let caption: LocalizedStringKey

        var body: some View {
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 26, weight: .semibold))

                Text(caption)
                    .font(Theme.Font.row)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: OnboardingUI.columnWidth)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    struct Actions: View {
        let primary: LocalizedStringResource
        let primaryAction: () -> Void
        var secondary: LocalizedStringResource?
        var secondaryAction: (() -> Void)?

        var body: some View {
            HStack(spacing: 10) {
                Button(primary, action: primaryAction)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)

                if let secondary, let secondaryAction {
                    Button(secondary, action: secondaryAction)
                        .buttonStyle(.bordered)
                }
            }
            .controlSize(.large)
            .padding(.top, 24)
        }
    }

    struct AppMark: View {
        var size: CGFloat = 104

        var body: some View {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }

    struct ModelChoiceCard: View {
        let tag: LocalizedStringResource
        let title: LocalizedStringResource
        let caption: LocalizedStringResource
        let isSelected: Bool
        let select: () -> Void

        @State private var hovering = false

        var body: some View {
            Button(action: select) {
                VStack(alignment: .leading, spacing: 8) {
                    Tag(tag)

                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))

                        Spacer(minLength: 0)

                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(Theme.Font.badge)
                        }
                    }

                    Text(caption)
                        .font(Theme.Font.secondary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .selectionBackground(
                    isSelected: isSelected,
                    isHovering: hovering,
                    rests: true,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(Theme.Motion.quick, value: hovering)
        }
    }
}
