// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

/// The browser's chrome is one continuous surface: a top beam joined to the
/// sidebar, with the page fitted into the beam's inner elbow.
enum LoomChrome {
    /// The inset shared by chrome-owned surfaces.
    nonisolated static let canvasInset: CGFloat = 6
    nonisolated static let resizeGrabWidth: CGFloat = 8

    /// Visually balances sidebar rows against the canvas gutter without
    /// changing the resize handle's position inside that gutter.
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

        // A real page chooses the chrome's tonal family too. In particular,
        // black and grey headers carry useful appearance information; treating
        // them as "no colour" leaves a light Loom around dark sites.
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

    private static func neutral(isLight: Bool) -> NSColor {
        if isLight {
            NSColor(srgbRed: 0.94, green: 0.94, blue: 0.955, alpha: 1)
        } else {
            NSColor(srgbRed: 0.105, green: 0.105, blue: 0.125, alpha: 1)
        }
    }
}

/// The shared visible affordance for every resize gutter. The surrounding
/// handle owns the larger interaction target; this view only draws the pill.
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

/// Resolves every horizontal shell measurement from the same inputs. The
/// browser, panel, and resize gutters should never each infer these offsets.
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

    /// Additional room reserved by the page canvas. The top bar never reads
    /// this value, so opening the panel cannot change toolbar geometry.
    var canvasTrailingInset: CGFloat {
        guard isPanelVisible, !isPanelExpanded else { return 0 }
        return panelWidth + LoomChrome.canvasInset
    }

    /// Leading edge for a resize hit target centred in the canvas gutter.
    var sidebarResizeLeading: CGFloat {
        sidebarWidth + (LoomChrome.canvasInset - LoomChrome.resizeGrabWidth) / 2
    }

    var panelLeading: CGFloat {
        containerWidth - panelWidth - LoomChrome.canvasInset
    }

    func panelCoversPage(viewMaxX: CGFloat) -> Bool {
        isPanelVisible && viewMaxX > panelLeading
    }

    /// Leading edge for a resize target centred between the page canvas and
    /// the side panel. It is window-owned, so neither surface shifts around it.
    var panelResizeLeading: CGFloat {
        containerWidth
            - panelWidth
            - LoomChrome.canvasInset
            - (LoomChrome.canvasInset + LoomChrome.resizeGrabWidth) / 2
    }
}

struct LoomAmbientBackdrop: View {
    let sampledPageColor: NSColor?
    let settings: BrowserSettings

    var body: some View {
        switch settings.loomStyle {
        case .standard:
            LoomTintedBackdrop(sampledPageColor: websiteTint, isFloating: false)
        case .liquidGlass:
            LoomLiquidGlassBackdrop(
                sampledPageColor: websiteTint,
                opacity: settings.liquidGlassOpacity,
                isFloating: false
            )
        }
    }

    private var websiteTint: NSColor? {
        settings.matchesWebsiteColor ? sampledPageColor : nil
    }
}

struct LoomFloatingFill: View {
    let sampledPageColor: NSColor?
    let settings: BrowserSettings

    var body: some View {
        switch settings.loomStyle {
        case .standard:
            LoomTintedBackdrop(sampledPageColor: websiteTint, isFloating: true)
        case .liquidGlass:
            LoomLiquidGlassBackdrop(
                sampledPageColor: websiteTint,
                opacity: settings.liquidGlassOpacity,
                isFloating: true
            )
        }
    }

    private var websiteTint: NSColor? {
        settings.matchesWebsiteColor ? sampledPageColor : nil
    }
}

private struct LoomTintedBackdrop: View {
    let sampledPageColor: NSColor?
    let isFloating: Bool

    @Environment(\.colorScheme) private var scheme

    private var sampled: NSColor {
        LoomChrome.sampledColor(sampledPageColor, scheme: scheme)
    }

    var body: some View {
        ZStack {
            VisualEffectView(
                material: .sidebar,
                blending: isFloating ? .withinWindow : .behindWindow
            )

            Color(nsColor: sampled).opacity(isFloating ? 0.72 : 0.92)

            if !isFloating {
                LinearGradient(
                    colors: [
                        Color.white.opacity(
                            PageInk.isLight(sampled, scheme: scheme) ? 0.075 : 0.025
                        ),
                        Color.clear,
                        Color.black.opacity(
                            PageInk.isLight(sampled, scheme: scheme) ? 0.018 : 0.075
                        ),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct LoomLiquidGlassBackdrop: View {
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

/// The one panel recipe, shared by the side panel, internal pages and Settings
/// so they cannot drift apart. `NSVisualEffectView` behind the window already
/// tints toward the desktop wallpaper — including when other windows are in the
/// way — so a panel standing on it picks that up for free.
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
    @ViewBuilder let content: Content

    init(
        trailingInset: CGFloat = 0,
        showsPanelFill: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.trailingInset = trailingInset
        self.showsPanelFill = showsPanelFill
        self.content = content()
    }

    var body: some View {
        let shape = LoomChrome.canvasShape

        content
            .background {
                LoomPanelFill(shape: shape, isVisible: showsPanelFill)
            }
            .clipShape(shape)
            .shadow(
                color: .black.opacity(0.18),
                radius: 12,
                y: 4
            )
            .padding(.top, LoomChrome.canvasTop)
            .padding(.leading, LoomChrome.canvasInset)
            .padding(.trailing, LoomChrome.canvasInset + trailingInset)
            .padding(.bottom, LoomChrome.canvasInset)
    }
}
