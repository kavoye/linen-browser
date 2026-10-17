// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class SpaceGlide {
    fileprivate weak var stage: SpaceGlideView?

    func run(
        from outgoing: UUID,
        to incoming: UUID,
        forward: Bool,
        offset: CGFloat,
        width: CGFloat,
        scroll: CGFloat,
        velocity: Double,
        landed: @escaping () -> Void
    ) -> Bool {
        guard let stage, stage.isReady else { return false }
        stage.run(
            from: outgoing,
            to: incoming,
            forward: forward,
            offset: offset,
            width: width,
            scroll: scroll,
            velocity: velocity,
            landed: landed
        )
        return true
    }

    @discardableResult
    func track(from outgoing: UUID, to incoming: UUID?, forward: Bool, offset: CGFloat, width: CGFloat, scroll: CGFloat) -> Bool {
        guard let stage, stage.isReady else { return false }
        stage.track(from: outgoing, to: incoming, forward: forward, offset: offset, width: width, scroll: scroll)
        return true
    }

    func settleBack(settled: @escaping () -> Void) {
        guard let stage else {
            settled()
            return
        }
        stage.settleBack(settled: settled)
    }

    func prewarm(_ ids: [UUID]) {
        stage?.prewarm(ids)
    }

    func finish() {
        stage?.finish()
    }
}

private struct SpaceGlideLayout: Equatable {
    let from: UUID
    let to: UUID?
    let step: CGFloat
    let scroll: CGFloat
}

private struct SpaceGlidePage: View {
    let coordinator: AppCoordinator
    let spaceID: UUID
    let contentInsets: EdgeInsets
    let environment: EnvironmentValues

    var body: some View {
        SpacePage(coordinator: coordinator, spaceID: spaceID, contentInsets: contentInsets)
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
            .environment(\.self, environment)
    }
}

struct SpaceGlideStage: NSViewRepresentable {
    let coordinator: AppCoordinator
    let contentInsets: EdgeInsets

    func makeNSView(context: Context) -> SpaceGlideView {
        let view = SpaceGlideView(coordinator: coordinator)
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: SpaceGlideView, context: Context) {
        view.update(contentInsets: contentInsets, environment: context.environment)
        coordinator.spaceSlider.glide.stage = view
    }

    static func dismantleNSView(_ view: SpaceGlideView, coordinator: ()) {
        view.finish()
    }
}

final class SpaceGlideView: NSView {
    private unowned let coordinator: AppCoordinator
    private var contentInsets = EdgeInsets()
    private var environment = EnvironmentValues()
    private var pages: [UUID: NSHostingView<SpaceGlidePage>] = [:]
    private var arrangement: SpaceGlideLayout?
    private var turn = 0
    private var pendingLanding: (() -> Void)?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        alphaValue = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    fileprivate var isReady: Bool {
        window != nil && bounds.width > 0
    }

    private var isMoving: Bool {
        alphaValue > 0
    }

    func update(contentInsets: EdgeInsets, environment: EnvironmentValues) {
        self.contentInsets = contentInsets
        self.environment = environment
        guard !isMoving else { return }
        for (id, host) in pages {
            host.rootView = root(for: id)
        }
    }

    override func layout() {
        super.layout()
        place()
    }

    private func root(for id: UUID) -> SpaceGlidePage {
        SpaceGlidePage(coordinator: coordinator, spaceID: id, contentInsets: contentInsets, environment: environment)
    }

    private func page(for id: UUID) -> NSHostingView<SpaceGlidePage> {
        if let host = pages[id] {
            return host
        }
        let host = NSHostingView(rootView: root(for: id))
        host.safeAreaRegions = []
        host.sizingOptions = []
        host.isHidden = true
        host.frame = bounds
        addSubview(host)
        pages[id] = host
        return host
    }

    fileprivate func prewarm(_ ids: [UUID]) {
        guard !isMoving else { return }
        for (id, host) in pages where !ids.contains(id) {
            host.removeFromSuperview()
            pages[id] = nil
        }
        for id in ids {
            _ = page(for: id)
        }
        arrangement = nil
        place()
    }

    private func arrange(_ next: SpaceGlideLayout) {
        guard arrangement != next else { return }
        arrangement = next
        _ = page(for: next.from)
        if let to = next.to {
            _ = page(for: to)
        }
        place()
        layoutSubtreeIfNeeded()
    }

    private func place() {
        for (id, host) in pages {
            guard let arrangement, id == arrangement.from || id == arrangement.to else {
                host.isHidden = true
                host.frame = bounds
                continue
            }
            host.isHidden = false
            host.frame = id == arrangement.from
                ? CGRect(x: 0, y: -arrangement.scroll, width: bounds.width, height: bounds.height + arrangement.scroll)
                : bounds.offsetBy(dx: arrangement.step, dy: 0)
        }
    }

    private func show(translation: CGFloat) {
        guard let layer else { return }
        layer.removeAnimation(forKey: "glide")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.sublayerTransform = CATransform3DMakeTranslation(translation, 0, 0)
        CATransaction.commit()
        alphaValue = 1
    }

    fileprivate func track(from outgoing: UUID, to incoming: UUID?, forward: Bool, offset: CGFloat, width: CGFloat, scroll: CGFloat) {
        turn += 1
        arrange(SpaceGlideLayout(from: outgoing, to: incoming, step: forward ? width : -width, scroll: scroll))
        show(translation: offset)
    }

    fileprivate func run(
        from outgoing: UUID,
        to incoming: UUID,
        forward: Bool,
        offset: CGFloat,
        width: CGFloat,
        scroll: CGFloat,
        velocity: Double,
        landed: @escaping () -> Void
    ) {
        turn += 1
        let turn = turn
        let step = forward ? width : -width
        arrange(SpaceGlideLayout(from: outgoing, to: incoming, step: step, scroll: scroll))
        show(translation: -step)
        pendingLanding = landed
        animate(from: offset, to: -step, velocity: velocity) { [weak self] in
            guard let self, self.turn == turn, let landed = pendingLanding else { return }
            pendingLanding = nil
            landed()
        }
    }

    fileprivate func settleBack(settled: @escaping () -> Void) {
        turn += 1
        let turn = turn
        guard let layer, isMoving else {
            settled()
            return
        }
        let from = (layer.presentation()?.sublayerTransform ?? layer.sublayerTransform).m41
        show(translation: 0)
        animate(from: from, to: 0, velocity: 0) { [weak self] in
            guard let self, self.turn == turn else { return }
            finish()
            settled()
        }
    }

    private func animate(from: CGFloat, to: CGFloat, velocity: Double, completion: @escaping () -> Void) {
        guard let layer else { return }
        let spring = CASpringAnimation(perceptualDuration: 0.25, bounce: 0)
        spring.keyPath = "sublayerTransform.translation.x"
        spring.fromValue = from
        spring.toValue = to
        spring.initialVelocity = velocity
        spring.duration = 0.34
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        layer.add(spring, forKey: "glide")
        CATransaction.commit()
    }

    func finish() {
        turn += 1
        alphaValue = 0
        layer?.removeAnimation(forKey: "glide")
        layer?.sublayerTransform = CATransform3DIdentity
        arrangement = nil
        place()
        let landed = pendingLanding
        pendingLanding = nil
        landed?()
    }
}
