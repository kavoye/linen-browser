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
                            caption: "Browse the web and ask about any page."
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

    struct StyleScreen: View {
        let coordinator: AppCoordinator
        let model: OnboardingModel
        let clock: ShimmerClock

        var body: some View {
            Screen(usesStage: true) {
                Heading(
                    title: "Choose a layout",
                    caption: "You can change this later in Settings."
                )

                VStack(spacing: 10) {
                    ChoiceCard(
                        title: "Standard",
                        caption: "A sidebar for tabs and a toolbar above the page.",
                        isSelected: !isMinimal
                    ) {
                        model.prefersMinimal = false
                    }

                    ChoiceCard(
                        title: "Minimal",
                        caption: "The page fills the window, with a floating bar.",
                        isSelected: isMinimal
                    ) {
                        model.prefersMinimal = true
                    }
                }
                .frame(width: OnboardingUI.columnWidth)
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

        private var isMinimal: Bool {
            model.prefersMinimal ?? coordinator.settings.isMinimal
        }
    }

    struct ExtensionsScreen: View {
        let coordinator: AppCoordinator
        let model: OnboardingModel
        let clock: ShimmerClock

        var body: some View {
            Screen(usesStage: true) {
                Heading(
                    title: "Add extensions",
                    caption: "Linen supports extensions from the Chrome Web Store and Firefox Add-ons."
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
            Screen(usesStage: true) {
                Heading(
                    title: "Import your bookmarks",
                    caption: "Bring bookmarks from another browser, and make Linen your default."
                )

                SettingsCard {
                    BookmarkImportRow(
                        browser: coordinator.browser,
                        caption: "Choose an exported HTML file.",
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

        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var revealed = false

        var body: some View {
            Screen {
                AppMark(size: 64)
                    .padding(.bottom, 24)
                    .introReveal(revealed, delay: 0)

                Heading(title: "You’re all set", caption: "Here are a few shortcuts to get you started.")
                    .introReveal(revealed, delay: 0.08)

                FirstMoves()
                    .padding(.top, 28)
                    .introReveal(revealed, delay: 0.16)

                Text(AIDisclosure.onboardingCaption)
                    .font(Theme.Font.secondary)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 420)
                    .padding(.top, 24)
                    .introReveal(revealed, delay: 0.2)

                Actions(
                    primary: "Start Browsing",
                    primaryAction: {
                        OnboardingUI.handOff(model: model, coordinator: coordinator, reduceMotion: reduceMotion)
                    },
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
                text: "Hold Shift over a link to see a summary."
            ),
            .init(
                id: "peek",
                symbol: "rectangle.on.rectangle",
                text: "Shift-click a link to preview it."
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
        let usesStage: Bool
        let content: Content

        @Environment(\.onboardingColumnX) private var columnX

        init(usesStage: Bool = false, @ViewBuilder content: () -> Content) {
            self.usesStage = usesStage
            self.content = content()
        }

        var body: some View {
            if usesStage, let columnX {
                VStack(alignment: .leading, spacing: 0) {
                    content
                }
                .frame(width: OnboardingUI.columnWidth, alignment: .leading)
                .padding(.leading, columnX)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                .environment(\.onboardingLeads, true)
            } else {
                VStack(spacing: 0) {
                    content
                }
                .multilineTextAlignment(.center)
                .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    struct Heading: View {
        let title: LocalizedStringKey
        let caption: LocalizedStringKey

        @Environment(\.onboardingLeads) private var leads

        var body: some View {
            VStack(alignment: leads ? .leading : .center, spacing: 10) {
                Text(title)
                    .font(.system(size: 30, weight: .bold))

                Text(caption)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: OnboardingUI.columnWidth, alignment: leads ? .leading : .center)
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
            HStack(spacing: 12) {
                if let secondary, let secondaryAction {
                    Button(action: secondaryAction) {
                        Text(secondary)
                            .frame(minWidth: 72)
                    }
                    .buttonStyle(.bordered)
                }

                Button(action: primaryAction) {
                    Text(primary)
                        .frame(minWidth: 112)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.extraLarge)
            .padding(.top, 32)
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

    struct ChoiceCard: View {
        let title: LocalizedStringResource
        let caption: LocalizedStringResource
        let isSelected: Bool
        let select: () -> Void

        @State private var hovering = false

        var body: some View {
            Button(action: select) {
                VStack(alignment: .leading, spacing: 8) {

                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 14, weight: .semibold))

                        Spacer(minLength: 0)

                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(Theme.Font.badge)
                        }
                    }

                    Text(caption)
                        .font(.system(size: 12.5))
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
