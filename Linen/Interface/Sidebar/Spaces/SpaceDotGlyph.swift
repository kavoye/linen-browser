// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import QuartzCore
import SwiftUI

enum SpaceDotMotion: Equatable {
    case follow
    case track
    case glide(turn: Int, velocity: Double)
}

struct SpaceDotGlyph: NSViewRepresentable {
    let symbol: String
    let growth: CGFloat
    let isHovered: Bool
    let isHoverActive: Bool
    let motion: SpaceDotMotion
    var taps = 0

    static let size = CGSize(width: 20, height: 28)

    func makeNSView(context: Context) -> SpaceDotGlyphView {
        let view = SpaceDotGlyphView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: SpaceDotGlyphView, context: Context) {
        view.update(
            style: SpaceDotGlyphView.Style(
                symbol: symbol,
                isHovered: isHovered,
                isDark: context.environment.colorScheme == .dark
            ),
            growth: growth,
            isHoverActive: isHoverActive,
            motion: motion == .track && context.transaction.animation != nil ? .follow : motion
        )
        if view.taps != taps {
            view.taps = taps
            view.bounce()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SpaceDotGlyphView, context: Context) -> CGSize? {
        Self.size
    }
}

final class SpaceDotGlyphView: NSView {
    struct Style: Hashable {
        let symbol: String
        let isHovered: Bool
        let isDark: Bool
    }

    private let dot = CAShapeLayer()
    private let glyph = CALayer()
    private var style: Style?
    private var growth: Spring?
    private var lift: Spring?
    private var glideTurn: Int?
    private var wasHoverActive = false
    var taps = 0

    private struct Spring {
        var start: CFTimeInterval = 0
        var from: CGFloat
        var to: CGFloat
        var omega: Double = 1
        var velocity: Double = 0
        var duration: Double = 0

        init(at value: CGFloat) {
            from = value
            to = value
        }

        func value(at time: CFTimeInterval) -> (value: CGFloat, speed: CGFloat) {
            let t = time - start
            guard t < duration else { return (to, 0) }
            let decay = exp(-omega * t)
            let slope = velocity - omega
            let progress = 1 + (slope * t - 1) * decay
            let rate = (slope + omega - omega * slope * t) * decay
            return (from + (to - from) * progress, (to - from) * rate)
        }

        mutating func retarget(_ target: CGFloat, at time: CFTimeInterval, duration perceptual: Double, velocity given: Double?) -> Bool {
            let current = value(at: time)
            guard abs(target - current.value) > 0.0005 else {
                self = Spring(at: target)
                return false
            }
            let distance = target - current.value
            start = time
            from = current.value
            to = target
            omega = 2 * Double.pi / perceptual
            velocity = max(-20, min(20, given ?? Double(current.speed / distance)))
            duration = 9.5 / omega
            return true
        }
    }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 20, height: 28))
        wantsLayer = true
        dot.bounds = CGRect(x: 0, y: 0, width: 5, height: 5)
        dot.path = CGPath(ellipseIn: dot.bounds, transform: nil)
        layer?.addSublayer(dot)
        layer?.addSublayer(glyph)
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

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        dot.position = center
        glyph.position = center
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if let style {
            self.style = nil
            restyle(style)
        }
    }

    func update(style: Style, growth target: CGFloat, isHoverActive: Bool, motion: SpaceDotMotion) {
        restyle(style)
        let liftTarget: CGFloat = style.isHovered ? 1.08 : 1
        guard var growth, var lift else {
            growth = Spring(at: target)
            lift = Spring(at: liftTarget)
            render()
            return
        }
        let now = CACurrentMediaTime()
        let hoverDriven = isHoverActive || wasHoverActive
        wasHoverActive = isHoverActive
        var moved = false
        switch motion {
        case .glide(let turn, let velocity):
            if glideTurn != turn {
                glideTurn = turn
                moved = growth.retarget(target, at: now, duration: 0.25, velocity: velocity) || moved
            }
        case .track:
            glideTurn = nil
            if target != growth.to {
                growth = Spring(at: target)
                moved = true
            }
        case .follow:
            glideTurn = nil
            if target != growth.to {
                moved = growth.retarget(target, at: now, duration: hoverDriven ? 0.32 : 0.18, velocity: nil) || moved
            }
        }
        if liftTarget != lift.to {
            moved = lift.retarget(liftTarget, at: now, duration: 0.32, velocity: nil) || moved
        }
        self.growth = growth
        self.lift = lift
        if moved {
            render(from: now)
        }
    }

    func bounce() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let animation = CAKeyframeAnimation(keyPath: "transform.scale")
        animation.isAdditive = true
        animation.values = [0, -0.16, 0.06, 0]
        animation.keyTimes = [0, 0.28, 0.64, 1]
        animation.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
        ]
        animation.duration = 0.38
        glyph.add(animation, forKey: "bounce")
    }

    private func restyle(_ next: Style) {
        guard next != style else { return }
        let previous = style
        style = next
        let appearance = NSAppearance(named: next.isDark ? .darkAqua : .aqua) ?? NSApp.effectiveAppearance
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        appearance.performAsCurrentDrawingAppearance {
            let image = Self.image(for: next)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            if let previous, previous.symbol == next.symbol, previous.isDark == next.isDark {
                let fade = CABasicAnimation(keyPath: "contents")
                fade.fromValue = glyph.presentation()?.contents ?? glyph.contents
                fade.duration = 0.22
                fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                glyph.add(fade, forKey: "contents")
            }
            dot.fillColor = NSColor.tertiaryLabelColor.cgColor
            glyph.contentsScale = scale
            glyph.contents = image?.layerContents(forContentsScale: scale)
            glyph.bounds = CGRect(origin: .zero, size: image?.size ?? .zero)
            CATransaction.commit()
        }
    }

    private static var images: [Style: NSImage] = [:]

    private static func image(for style: Style) -> NSImage? {
        if let cached = images[style] {
            return cached
        }
        let tint = NSColor(cgColor: (style.isHovered ? NSColor.labelColor : .secondaryLabelColor).cgColor) ?? .secondaryLabelColor
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [tint]))
        let symbol = NSImage(systemSymbolName: "\(style.symbol).fill", accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: style.symbol, accessibilityDescription: nil)
        let image = symbol?.withSymbolConfiguration(configuration)
        images[style] = image
        return image
    }

    private static func targets(_ growth: CGFloat, lift: CGFloat) -> [CGFloat] {
        [1 - 0.6 * growth, 1 - min(1, growth * 2), (0.4 + 0.6 * growth) * lift, min(1, growth / 0.6)]
    }

    private func render(from time: CFTimeInterval? = nil) {
        guard let growth, let lift else { return }
        let layers: [(CALayer, String)] = [
            (dot, "transform.scale"),
            (dot, "opacity"),
            (glyph, "transform.scale"),
            (glyph, "opacity"),
        ]
        let finals = Self.targets(growth.to, lift: lift.to)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for ((layer, keyPath), value) in zip(layers, finals) {
            layer.setValue(value, forKeyPath: keyPath)
            layer.removeAnimation(forKey: keyPath)
        }
        let end = max(growth.start + growth.duration, lift.start + lift.duration)
        guard let time, end > time else {
            CATransaction.commit()
            return
        }
        let duration = end - time
        let steps = 48
        let times = (0...steps).map { Double($0) / Double(steps) }
        let samples = times.map { fraction in
            let moment = time + fraction * duration
            return Self.targets(growth.value(at: moment).value, lift: lift.value(at: moment).value)
        }
        for (index, (layer, keyPath)) in layers.enumerated() {
            let animation = CAKeyframeAnimation(keyPath: keyPath)
            animation.values = samples.map { $0[index] } + [finals[index]]
            animation.keyTimes = (times.map { $0 * 0.999 } + [1]).map { NSNumber(value: $0) }
            animation.calculationMode = .linear
            animation.duration = duration
            layer.add(animation, forKey: keyPath)
        }
        CATransaction.commit()
    }
}
