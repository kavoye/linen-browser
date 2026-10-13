// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct OnboardingOverlay: View {
    let coordinator: AppCoordinator
    let model: OnboardingModel

    @State private var clock = ShimmerClock()
    @State private var size: CGSize = .zero
    @State private var isOpen = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Theme.windowBackground
            ZStack {
                OnboardingShimmer(clock: clock)
                stage
                OnboardingUI.StepView(coordinator: coordinator, model: model, clock: clock)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(model.isHandingOff ? 0 : 1)
                OnboardingUI.HUD(model: model)
                    .opacity(model.isHandingOff ? 0 : 1)
            }
            .scaleEffect(isOpen ? 1 : 0.92)
            .opacity(isOpen ? 1 : 0)
        }
        .opacity(model.isRevealing ? 0 : 1)
        .onAppear(perform: open)
        .environment(\.onboardingColumnX, layout?.columnX)
        .ignoresSafeArea()
        .onGeometryChange(for: CGSize.self) {
            $0.size
        } action: {
            size = $0
        }
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
    }

    private func open() {
        guard !isOpen else { return }
        guard !reduceMotion, !model.isWindowReady else {
            isOpen = true
            model.markWindowReady()
            return
        }
        withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.8)) {
            isOpen = true
        } completion: {
            model.markWindowReady()
        }
    }

    @ViewBuilder
    private var stage: some View {
        if showsStage {
            let frame = stageFrame
            OnboardingUI.Stage(
                isMinimal: model.prefersMinimal ?? coordinator.settings.isMinimal,
                step: model.step,
                extensionSymbols: installedPicks.map(\.symbol),
                windowSize: size
            )
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            .transition(OnboardingUI.stageEntrance)
        }
    }

    private var installedPicks: [ExtensionPick] {
        ExtensionPicks.all.filter { coordinator.extensions.isInstalled($0.id) }
    }

    private var layout: OnboardingUI.SplitLayout? {
        OnboardingUI.SplitLayout(size: size)
    }

    private var showsStage: Bool {
        guard layout != nil, let step = model.step else { return false }
        return OnboardingUI.stageSteps.contains(step)
    }

    private var stageFrame: CGRect {
        layout?.stage ?? CGRect(origin: .zero, size: size)
    }
}

extension EnvironmentValues {
    @Entry var onboardingColumnX: CGFloat?
    @Entry var onboardingLeads = false
}

@MainActor
enum OnboardingUI {
    static let columnWidth: CGFloat = 420
    static let actionWidth: CGFloat = 120
    static let columnGap: CGFloat = 72
    static let stageSteps: Set<OnboardingModel.Step> = [.style, .extensions, .bookmarks]

    struct SplitLayout {
        let columnX: CGFloat
        let stage: CGRect

        private static let minVisibleStage: CGFloat = 380
        private static let stageHeightFraction: CGFloat = 0.78

        init?(size: CGSize) {
            guard size.width > 0, size.height > 0 else { return nil }
            let gutter = max(64, size.width * 0.07)
            let x = gutter + OnboardingUI.columnWidth + OnboardingUI.columnGap
            guard size.width - x >= Self.minVisibleStage else { return nil }
            let height = (size.height - 2 * Theme.topBarHeight) * Self.stageHeightFraction
            let width = height * size.width / size.height
            columnX = gutter
            stage = CGRect(x: x, y: (size.height - height) / 2, width: width, height: height)
        }
    }

    static var stageEntrance: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.94))
                .animation(.easeOut(duration: 0.45).delay(0.08)),
            removal: .opacity.animation(.easeIn(duration: 0.2))
        )
    }

    static func advance(model: OnboardingModel, coordinator: AppCoordinator, clock: ShimmerClock) {
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

    static func handOff(model: OnboardingModel, coordinator: AppCoordinator, reduceMotion: Bool) {
        guard model.isPresented, !model.isHandingOff else { return }
        guard !reduceMotion else {
            finish(model: model, coordinator: coordinator)
            return
        }
        let switchesLayout = model.prefersMinimal.map { $0 != coordinator.settings.isMinimal } ?? false
        if let prefersMinimal = model.prefersMinimal {
            coordinator.settings.isMinimal = prefersMinimal
        }
        withAnimation(.easeIn(duration: 0.25)) {
            model.beginHandOff()
        }
        coordinator.growWindowAfterOnboarding()
        Task {
            try? await Task.sleep(for: .milliseconds(switchesLayout ? 600 : 250))
            guard model.isHandingOff else { return }
            withAnimation(.easeOut(duration: 0.4)) {
                model.beginReveal()
            }
            try? await Task.sleep(for: .milliseconds(400))
            guard model.isHandingOff else { return }
            finish(model: model, coordinator: coordinator)
        }
    }

    static func complete(model: OnboardingModel, coordinator: AppCoordinator) {
        guard model.isPresented else { return }
        let prefersMinimal = model.prefersMinimal
        model.finish()
        if let prefersMinimal {
            coordinator.settings.isMinimal = prefersMinimal
        }
        coordinator.growWindowAfterOnboarding()
    }

    static func finish(model: OnboardingModel, coordinator: AppCoordinator) {
        guard model.isPresented else { return }
        complete(model: model, coordinator: coordinator)
        if !coordinator.isShowingSettings {
            coordinator.focusAddressBar()
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
            case .style:
                StyleScreen(coordinator: coordinator, model: model, clock: clock)
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
