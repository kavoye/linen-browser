// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

extension OnboardingUI {
    struct WelcomeScreen: View {
        let coordinator: AppCoordinator
        let model: OnboardingModel

        var body: some View {
            Screen {
                AppMark()
                    .padding(.bottom, 24)

                Heading(
                    title: "Welcome to Linen",
                    caption: "A quiet browser with an assistant built in. Setup takes two choices."
                )

                Actions(
                    primary: "Continue",
                    primaryAction: { OnboardingUI.advance(model: model, coordinator: coordinator) },
                    secondary: "Skip Setup",
                    secondaryAction: { OnboardingUI.finish(model: model, coordinator: coordinator) }
                )
            }
        }
    }

    struct ModelScreen: View {
        let coordinator: AppCoordinator
        let model: OnboardingModel

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
                    primaryAction: { OnboardingUI.advance(model: model, coordinator: coordinator) }
                )
            }
        }
    }

    struct HistoryScreen: View {
        let coordinator: AppCoordinator
        let model: OnboardingModel

        var body: some View {
            Screen {
                Heading(
                    title: "Bring your browsing over",
                    caption: "Import what you already have, and open links from other apps in Linen."
                )

                SettingsCard {
                    ForEach(BrowserImport.Source.allCases, id: \.self) { source in
                        if source != BrowserImport.Source.allCases.first {
                            RowSeparator()
                        }
                        ImportRow(source: source, browser: coordinator.browser)
                    }

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
                    primary: "Done",
                    primaryAction: { OnboardingUI.advance(model: model, coordinator: coordinator) }
                )
            }
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
        var body: some View {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 104, height: 104)
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
                .background(fill, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card)
                        .strokeBorder(border, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(Theme.Motion.quick, value: hovering)
        }

        private var fill: Color {
            if isSelected {
                return SettingsMetrics.fillSelected
            }
            return hovering ? SettingsMetrics.fill : Theme.Wash.faint
        }

        private var border: Color {
            isSelected ? SettingsMetrics.borderHover : SettingsMetrics.border
        }
    }
}

extension OnboardingUI {
    struct ImportRow: View {
        let source: BrowserImport.Source
        let browser: BrowserModel

        @State private var payload: BrowserImport.Payload?
        @State private var status: String?
        @State private var needsFullDiskAccess = false
        @State private var isScanning = false
        @State private var isImported = false

        var body: some View {
            DetailRow(verbatimTitle: source.name, verbatimCaption: caption) {
                control
                    .frame(width: OnboardingUI.actionWidth, alignment: .trailing)
            }
            .task { await scan() }
        }

        @ViewBuilder
        private var control: some View {
            if isScanning {
                Spinner(size: 12)
                    .foregroundStyle(.secondary)
            } else if isImported {
                Text("Imported")
                    .font(Theme.Font.body)
                    .foregroundStyle(.tertiary)
            } else if needsFullDiskAccess {
                SettingsButton(
                    title: "Open System Settings",
                    minWidth: OnboardingUI.actionWidth
                ) {
                    let pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
                    if let url = URL(string: pane) {
                        NSWorkspace.shared.open(url)
                    }
                }
            } else {
                SettingsButton(title: "Import", minWidth: OnboardingUI.actionWidth) {
                    guard let payload else { return }
                    BrowserImport.apply(payload, into: browser)
                    isImported = true
                }
                .disabled(payload == nil)
            }
        }

        private var caption: String {
            if let status {
                return status
            }
            if let payload {
                return payload.summary.phrase + "."
            }
            return String(localized: source.caption)
        }

        private func scan() async {
            guard source.isPresent, payload == nil, !needsFullDiskAccess else { return }
            isScanning = true
            let result = await Task.detached { Result { try source.scan() } }.value
            isScanning = false
            switch result {
            case .success(let found) where found.summary.isEmpty:
                status = String(localized: "Nothing to import.")
            case .success(let found):
                payload = found
            case .failure(BrowserImport.Failure.needsFullDiskAccess):
                needsFullDiskAccess = true
                status = String(localized: "Needs Full Disk Access.")
            case .failure:
                status = String(localized: "Couldn’t read these files.")
            }
        }
    }
}
