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
        velocity: Double,
        landed: @escaping () -> Void
    ) -> Bool {
        guard let stage, stage.window != nil, stage.bounds.width > 0 else { return false }
        stage.run(from: outgoing, to: incoming, forward: forward, offset: offset, width: width, velocity: velocity, landed: landed)
        return true
    }

    func prepare(from outgoing: UUID, to incoming: UUID, forward: Bool, width: CGFloat) {
        guard let stage, stage.window != nil, stage.bounds.width > 0 else { return }
        stage.prepare(from: outgoing, to: incoming, forward: forward, width: width)
    }

    func finish() {
        stage?.finish()
    }
}

private struct SpaceGlidePair: Equatable {
    let from: UUID
    let to: UUID
    let step: CGFloat
    let size: CGSize
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
        view.contentInsets = contentInsets
        view.environment = context.environment
        coordinator.spaceSlider.glide.stage = view
    }

    static func dismantleNSView(_ view: SpaceGlideView, coordinator: ()) {
        view.finish()
    }
}

final class SpaceGlideView: NSView {
    private unowned let coordinator: AppCoordinator
    var contentInsets = EdgeInsets()
    var environment = EnvironmentValues()
    private var pages: [NSView] = []
    private var prepared: SpaceGlidePair?
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

    fileprivate func prepare(from outgoing: UUID, to incoming: UUID, forward: Bool, width: CGFloat) {
        let step = forward ? width : -width
        let pair = SpaceGlidePair(from: outgoing, to: incoming, step: step, size: bounds.size)
        guard prepared != pair else { return }
        clearPages()
        pages = [(outgoing, 0), (incoming, step)].map { id, x in
            let root = SpacePage(coordinator: coordinator, spaceID: id, contentInsets: contentInsets)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
                .environment(\.self, environment)
            let host = NSHostingView(rootView: root)
            host.safeAreaRegions = []
            host.sizingOptions = []
            host.frame = bounds.offsetBy(dx: x, dy: 0)
            addSubview(host)
            return host
        }
        layoutSubtreeIfNeeded()
        prepared = pair
    }

    fileprivate func run(
        from outgoing: UUID,
        to incoming: UUID,
        forward: Bool,
        offset: CGFloat,
        width: CGFloat,
        velocity: Double,
        landed: @escaping () -> Void
    ) {
        turn += 1
        let turn = turn
        let step = forward ? width : -width
        prepare(from: outgoing, to: incoming, forward: forward, width: width)
        alphaValue = 1

        guard let layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.sublayerTransform = CATransform3DMakeTranslation(-step, 0, 0)
        CATransaction.commit()

        pendingLanding = landed
        let spring = CASpringAnimation(perceptualDuration: 0.25, bounce: 0)
        spring.keyPath = "sublayerTransform.translation.x"
        spring.fromValue = offset
        spring.toValue = -step
        spring.initialVelocity = velocity
        spring.duration = 0.34
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, self.turn == turn, let landed = pendingLanding else { return }
            pendingLanding = nil
            landed()
        }
        layer.add(spring, forKey: "glide")
        CATransaction.commit()
    }

    func finish() {
        turn += 1
        alphaValue = 0
        clearPages()
        layer?.removeAnimation(forKey: "glide")
        layer?.sublayerTransform = CATransform3DIdentity
        let landed = pendingLanding
        pendingLanding = nil
        landed?()
    }

    private func clearPages() {
        pages.forEach { $0.removeFromSuperview() }
        pages = []
        prepared = nil
    }
}
