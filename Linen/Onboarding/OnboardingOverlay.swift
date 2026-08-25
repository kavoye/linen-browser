// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct OnboardingOverlay: View {
    let coordinator: AppCoordinator
    let model: OnboardingModel

    var body: some View {
        ZStack {
            Theme.windowBackground
            OnboardingUI.StepView(coordinator: coordinator, model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            OnboardingUI.HUD(model: model)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture {}
        .task {
            if !AnyLanguageModelAgent.isSystemModelAvailable {
                model.modelChoice = .remote
            }
        }
    }
}

@MainActor
enum OnboardingUI {
    static let columnWidth: CGFloat = 540
    static let actionWidth: CGFloat = 168

    static func advance(model: OnboardingModel, coordinator: AppCoordinator) {
        if model.step == .model {
            applyModelChoice(model: model, coordinator: coordinator)
        }

        guard model.isLastStep else {
            model.advance()
            return
        }

        finish(model: model, coordinator: coordinator)
    }

    static func finish(model: OnboardingModel, coordinator: AppCoordinator) {
        model.finish()
        if !coordinator.isShowingSettings {
            coordinator.focusAddressBar()
        }
    }

    private static func applyModelChoice(model: OnboardingModel, coordinator: AppCoordinator) {
        switch model.modelChoice {
        case .onDevice:
            LLMSettings.providerID = ProviderCatalog.appleOnDevice.id
            coordinator.configureEngines()
        case .remote:
            coordinator.openSettings(.provider)
        }
    }
}

extension OnboardingUI {
    struct HUD: View {
        let model: OnboardingModel

        var body: some View {
            VStack {
                ZStack {
                    HStack(spacing: 5) {
                        ForEach(OnboardingModel.Step.allCases, id: \.rawValue) { dot in
                            Circle()
                                .fill(dotStyle(for: dot))
                                .frame(width: 6, height: 6)
                        }
                    }

                    HStack(spacing: 4) {
                        KeyCap("esc")
                        Text("to skip")
                    }
                    .font(Theme.Font.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.horizontal, 20)
                .frame(height: Theme.topBarHeight)

                Spacer(minLength: 0)
            }
        }

        private func dotStyle(for dot: OnboardingModel.Step) -> Color {
            guard let step = model.step else { return Theme.Wash.selection }
            if dot == step {
                return .primary
            }
            return dot.rawValue < step.rawValue ? Theme.Wash.emphasis : Theme.Wash.selection
        }
    }

    struct StepView: View {
        let coordinator: AppCoordinator
        let model: OnboardingModel

        var body: some View {
            switch model.step {
            case .welcome:
                WelcomeScreen(coordinator: coordinator, model: model)
            case .model:
                ModelScreen(coordinator: coordinator, model: model)
            case .bookmarks:
                BookmarksScreen(coordinator: coordinator, model: model)
            case nil:
                EmptyView()
            }
        }
    }
}
