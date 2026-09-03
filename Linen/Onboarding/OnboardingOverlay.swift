// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct OnboardingOverlay: View {
    let coordinator: AppCoordinator
    let model: OnboardingModel

    @State private var clock = ShimmerClock()

    var body: some View {
        ZStack {
            Theme.windowBackground
            OnboardingShimmer(clock: clock)
            OnboardingUI.StepView(coordinator: coordinator, model: model, clock: clock)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            OnboardingUI.HUD(model: model)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture {}
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let location):
                clock.movePointer(to: location)
            case .ended:
                clock.releasePointer()
            }
        }
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

    static func advance(model: OnboardingModel, coordinator: AppCoordinator, clock: ShimmerClock) {
        if model.step == .model {
            applyModelChoice(model: model, coordinator: coordinator)
        }

        guard model.isLastStep else {
            clock.emphasize()
            withAnimation(.default) { model.advance() }
            return
        }

        finish(model: model, coordinator: coordinator)
    }

    static func back(model: OnboardingModel) {
        withAnimation(.default) { model.back() }
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
            .opacity(model.showsNavigation ? 1 : 0)
            .animation(Theme.Motion.drift, value: model.showsNavigation)
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
        let clock: ShimmerClock

        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            screen
                .id(model.step)
                .transition(reduceMotion ? .opacity : Self.rise)
        }

        @ViewBuilder
        private var screen: some View {
            switch model.step {
            case .welcome:
                WelcomeScreen(coordinator: coordinator, model: model, clock: clock)
            case .model:
                ModelScreen(coordinator: coordinator, model: model, clock: clock)
            case .extensions:
                ExtensionsScreen(coordinator: coordinator, model: model, clock: clock)
            case .bookmarks:
                BookmarksScreen(coordinator: coordinator, model: model, clock: clock)
            case .finish:
                FinishScreen(coordinator: coordinator, model: model)
            case nil:
                EmptyView()
            }
        }

        private static var rise: AnyTransition {
            .asymmetric(
                insertion: AnyTransition
                    .modifier(active: Rise(offset: 30), identity: Rise(offset: 0))
                    .animation(.easeOut(duration: 0.3).delay(0.05)),
                removal: AnyTransition
                    .modifier(active: Rise(offset: -30), identity: Rise(offset: 0))
                    .animation(.easeIn(duration: 0.2))
            )
        }
    }

    private struct Rise: ViewModifier {
        let offset: CGFloat

        func body(content: Content) -> some View {
            content
                .offset(y: offset)
                .blur(radius: offset == 0 ? 0 : 8)
                .opacity(offset == 0 ? 1 : 0)
        }
    }
}
