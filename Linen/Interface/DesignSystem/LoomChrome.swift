// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

enum LoomChrome {
    nonisolated static let canvasInset: CGFloat = 6
    nonisolated static let resizeGrabWidth: CGFloat = 8

    nonisolated static var sidebarContentBalanceOffset: CGFloat {
        canvasInset / 2
    }

    nonisolated static var canvasTop: CGFloat {
        Theme.topBarHeight
    }

    static var canvasRadius: CGFloat {
        Theme.Radius.nested(in: Theme.Radius.window, inset: canvasInset)
    }

    static var canvasShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: canvasRadius, style: .continuous)
    }

    static func sampledColor(_ color: NSColor?, scheme: ColorScheme) -> NSColor {
        let fallbackIsLight = scheme == .light
        guard let color = color?.usingColorSpace(.sRGB), color.alphaComponent > 0.05 else {
            return neutral(isLight: fallbackIsLight)
        }

        let isLight = PageInk.isLight(color, scheme: scheme)
        let neutral = neutral(isLight: isLight)

        let floor: CGFloat = isLight ? 0.55 : 0.02
        let ceiling: CGFloat = isLight ? 1 : 0.82
        let tint = NSColor(
            hue: color.hueComponent,
            saturation: min(color.saturationComponent, 0.55),
            brightness: min(max(color.brightnessComponent, floor), ceiling),
            alpha: 1
        )
        return neutral.blended(withFraction: 0.85, of: tint) ?? neutral
    }

    static func blend(_ from: NSColor?, _ to: NSColor?, by fraction: Double) -> NSColor? {
        guard from != nil || to != nil else { return nil }
        let isLight = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
        let start = (from ?? neutral(isLight: isLight)).usingColorSpace(.sRGB) ?? neutral(isLight: isLight)
        let end = (to ?? neutral(isLight: isLight)).usingColorSpace(.sRGB) ?? neutral(isLight: isLight)
        return start.blended(withFraction: min(max(fraction, 0), 1), of: end)
    }

    private static func neutral(isLight: Bool) -> NSColor {
        if isLight {
            NSColor(srgbRed: 0.94, green: 0.94, blue: 0.955, alpha: 1)
        } else {
            NSColor(srgbRed: 0.105, green: 0.105, blue: 0.125, alpha: 1)
        }
    }
}

struct LoomTint: Equatable {
    var from: NSColor?
    var to: NSColor?
    var fraction: Double

    static func solid(_ color: NSColor?) -> LoomTint {
        LoomTint(from: color, to: color, fraction: 0)
    }

    static let none = solid(nil)

    var color: NSColor? {
        fraction > 0 ? LoomChrome.blend(from, to, by: fraction) : from
    }
}

struct LoomResizePill: View {
    let axis: Axis
    let isVisible: Bool
    let isDragging: Bool
    var thickness: CGFloat = 3
    var length: CGFloat = 64
    var onLightPage: Bool = false

    private var ink: Color {
        onLightPage ? .black : .white
    }

    private var halo: Color {
        (onLightPage ? Color.white : Color.black).opacity(0.35)
    }

    var body: some View {
        Capsule()
            .fill(ink)
            .overlay(Capsule().strokeBorder(halo, lineWidth: 0.5))
            .frame(
                width: axis == .vertical ? thickness : length,
                height: axis == .vertical ? length : thickness
            )
            .opacity(isVisible ? 1 : 0)
            .shadow(color: .black.opacity(isDragging ? 0.45 : 0.3), radius: 4, y: 1)
    }
}

nonisolated struct LoomShellGeometry {
    let containerWidth: CGFloat
    let sidebarWidth: CGFloat
    let preferredPanelWidth: CGFloat
    let isSidebarVisible: Bool
    let isPanelVisible: Bool
    let isPanelExpanded: Bool

    var panelWidth: CGFloat {
        guard isPanelExpanded else { return preferredPanelWidth }
        return max(
            containerWidth - (isSidebarVisible ? sidebarWidth : 0) - LoomChrome.canvasInset * 2,
            0
        )
    }

    var canvasTrailingInset: CGFloat {
        guard isPanelVisible, !isPanelExpanded else { return 0 }
        return panelWidth + LoomChrome.canvasInset
    }

    var sidebarResizeLeading: CGFloat {
        sidebarWidth + (LoomChrome.canvasInset - LoomChrome.resizeGrabWidth) / 2
    }

    var panelCoversPage: Bool {
        isPanelVisible && isPanelExpanded
    }

    var panelResizeLeading: CGFloat {
        containerWidth
            - panelWidth
            - LoomChrome.canvasInset
            - (LoomChrome.canvasInset + LoomChrome.resizeGrabWidth) / 2
    }
}

struct LoomSpaceBackdrop: View {
    let browser: BrowserModel
    let coordinator: AppCoordinator
    var isFloating = false

    var body: some View {
        let tint = ChromeBand.tint(browser: browser, coordinator: coordinator)
        if isFloating {
            LoomFloatingFill(tint: tint, settings: coordinator.settings)
        } else {
            LoomAmbientBackdrop(tint: tint, settings: coordinator.settings)
        }
    }
}

struct LoomAmbientBackdrop: View {
    let tint: LoomTint
    let settings: BrowserSettings

    var body: some View {
        switch settings.loomStyle {
        case .standard:
            LoomTintedBackdrop(tint: websiteTint, isFloating: false)
        case .transparent:
            LoomTransparentBackdrop(
                sampledPageColor: websiteTint.color,
                opacity: settings.transparency,
                isFloating: false
            )
        }
    }

    private var websiteTint: LoomTint {
        settings.matchesWebsiteColor ? tint : .none
    }
}

struct LoomFloatingFill: View {
    let tint: LoomTint
    let settings: BrowserSettings

    var body: some View {
        switch settings.loomStyle {
        case .standard:
            LoomTintedBackdrop(tint: websiteTint, isFloating: true)
        case .transparent:
            LoomTransparentBackdrop(
                sampledPageColor: websiteTint.color,
                opacity: settings.transparency,
                isFloating: true
            )
        }
    }

    private var websiteTint: LoomTint {
        settings.matchesWebsiteColor ? tint : .none
    }
}

private struct LoomTintedBackdrop: View {
    let tint: LoomTint
    let isFloating: Bool

    @Environment(\.colorScheme) private var scheme

    private func ground(of color: NSColor?) -> (wash: NSColor, opacity: CGFloat) {
        let wash = LoomChrome.sampledColor(color, scheme: scheme)
        if let color, color.alphaComponent > 0.05 {
            return (wash, isFloating ? 0.72 : 0.92)
        }
        if isFloating {
            return (wash, 0.55)
        }
        return (wash, PageInk.isLight(wash, scheme: scheme) ? 0.34 : 0.28)
    }

    var body: some View {
        let start = ground(of: tint.from)
        let end = ground(of: tint.to)
        let fraction = CGFloat(min(max(tint.fraction, 0), 1))
        let wash = start.wash.blended(withFraction: fraction, of: end.wash) ?? start.wash
        let opacity = start.opacity + (end.opacity - start.opacity) * fraction
        ZStack {
            VisualEffectView(
                material: .underWindowBackground,
                blending: isFloating ? .withinWindow : .behindWindow
            )

            Color(nsColor: wash).opacity(opacity)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct LoomTransparentBackdrop: View {
    let sampledPageColor: NSColor?
    let opacity: Double
    let isFloating: Bool

    @Environment(\.colorScheme) private var scheme

    private var sampled: NSColor {
        LoomChrome.sampledColor(sampledPageColor, scheme: scheme)
    }

    private var isLight: Bool {
        PageInk.isLight(sampled, scheme: scheme)
    }

    private var level: CGFloat {
        let sliderLevel = CGFloat(min(max(opacity, 0), 1))
        return 0.82 + 0.18 * sliderLevel
    }

    private var intensity: CGFloat {
        level * level * level
    }

    private var substrateOpacity: CGFloat {
        0.12 + 0.82 * intensity
    }

    private var glassTintOpacity: CGFloat {
        let resting = isFloating ? (isLight ? 0.025 : 0.035) : (isLight ? 0.02 : 0.03)
        let maximum: CGFloat = isLight ? 0.32 : 0.38
        return resting + (maximum - resting) * intensity
    }

    private var tintWashOpacity: CGFloat {
        (isLight ? 0.34 : 0.42) * intensity
    }

    var body: some View {
        ZStack {
            VisualEffectView(
                material: .underWindowBackground,
                blending: .behindWindow,
                materialOpacity: substrateOpacity
            )

            AppKitGlassEffectView(
                style: .clear,
                tintColor: sampled.withAlphaComponent(glassTintOpacity)
            )

            Color(nsColor: sampled).opacity(tintWashOpacity)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct LoomPanelFill<S: Shape>: View {
    let shape: S
    var isVisible = true
    var emphasis: Double = 1
    var tint: Color?
    var isInteractive = false

    @Environment(\.colorScheme) private var colorScheme

    private var glass: Glass {
        guard isVisible else { return .identity }
        let resting = colorScheme == .dark ? 0.18 : 0.10
        let tinted = Glass.regular.tint(
            (tint ?? Theme.sidebarTint).opacity(min(1, resting * emphasis))
        )
        return isInteractive ? tinted.interactive() : tinted
    }

    var body: some View {
        Color.clear
            .glassEffect(glass, in: shape)
    }
}

struct LoomPageCanvas<Content: View>: View {
    let trailingInset: CGFloat
    let showsPanelFill: Bool
    let retraction: CGFloat
    @ViewBuilder let content: Content

    init(
        trailingInset: CGFloat = 0,
        showsPanelFill: Bool = false,
        retraction: CGFloat = 0,
        @ViewBuilder content: () -> Content
    ) {
        self.trailingInset = trailingInset
        self.showsPanelFill = showsPanelFill
        self.retraction = retraction
        self.content = content()
    }

    var body: some View {
        let keep = 1 - retraction
        let shape = RoundedRectangle(cornerRadius: LoomChrome.canvasRadius * keep, style: .continuous)

        content
            .background {
                LoomPanelFill(shape: shape, isVisible: showsPanelFill)
            }
            .clipShape(shape)
            .shadow(
                color: .black.opacity(0.18 * keep),
                radius: 12,
                y: 4
            )
            .padding(.top, LoomChrome.canvasTop * keep)
            .padding(.leading, LoomChrome.canvasInset * keep)
            .padding(.trailing, LoomChrome.canvasInset * keep + trailingInset)
            .padding(.bottom, LoomChrome.canvasInset * keep)
    }
}

struct LoomInk: ViewModifier {
    enum Reach {
        case scheme
        case window
        case full
    }

    let browser: BrowserModel
    let coordinator: AppCoordinator
    var reach = Reach.full

    @Environment(\.colorScheme) private var scheme

    @ViewBuilder
    func body(content: Content) -> some View {
        let loom = ChromeBand.loomWash(browser: browser, coordinator: coordinator, scheme: scheme)
        let loomScheme: ColorScheme = loom.isLight ? .light : .dark
        switch reach {
        case .scheme:
            content.environment(\.colorScheme, loomScheme)
        case .window:
            content.environment(\.windowColorScheme, loomScheme)
        case .full:
            content
                .environment(\.chromeIsLight, loom.isLight)
                .environment(\.chromeWash, loom)
                .environment(\.colorScheme, loomScheme)
        }
    }
}

struct LoomPageInkReader<Content: View>: View {
    let browser: BrowserModel
    let coordinator: AppCoordinator
    @ViewBuilder let content: (Bool) -> Content

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        content(PageInk.isLight(ChromeBand.pageColor(browser: browser, coordinator: coordinator), scheme: scheme))
    }
}
