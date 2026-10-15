// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import CoreGraphics
import Foundation
import Observation
import SwiftUI

enum SpaceEditorTarget: Hashable {
    case new
    case edit(UUID)
}

struct SpaceGlideTarget: Equatable {
    let from: UUID
    let to: UUID
    let loom: NSColor?
}

struct SpacePeer: Equatable {
    let id: UUID
    let forward: Bool
}

@Observable
final class SpaceSlide {
    var offset: CGFloat = 0
    var isSliding = false
    var peer: SpacePeer?
    var peerLoom: NSColor?
    var mounted: [UUID] = []
    var pull: CGFloat = 0
    var loomBlend: Double = 0
    var loomTravel: Double = 0
    var isGliding = false
    var gliding: SpaceGlideTarget?
    var held: [SidebarItem]?

    var travel: CGFloat {
        guard peer != nil, width > 0 else { return 0 }
        return min(1, abs(offset) / width)
    }
    @ObservationIgnored var width: CGFloat = 260
    @ObservationIgnored var glideTurn = 0
    @ObservationIgnored var glideVelocity: Double = 0

    func reset() {
        isGliding = false
        gliding = nil
        held = nil
        offset = 0
        peer = nil
        pull = 0
        loomBlend = 0
        loomTravel = 0
        isSliding = false
    }
}

struct SpaceSlideOffset: ViewModifier {
    let slide: SpaceSlide

    func body(content: Content) -> some View {
        let offset = slide.offset
        return content.visualEffect { effect, _ in effect.offset(x: offset) }
    }
}

struct SpaceListInk: ViewModifier {
    let browser: BrowserModel
    let coordinator: AppCoordinator

    @Environment(\.chromeWash) private var wash
    @Environment(\.windowColorScheme) private var scheme

    func body(content: Content) -> some View {
        let ink = coordinator.overlays.spaceSlide.loomBlend > 0 && coordinator.settings.matchesWebsiteColor
            ? liveWash
            : wash
        return content
            .environment(\.chromeWash, ink)
            .environment(\.chromeIsLight, ink.isLight)
            .environment(\.colorScheme, ink.isLight ? .light : .dark)
    }

    private var liveWash: ChromeWash {
        let color = LoomChrome.sampledColor(
            ChromeBand.livePageColor(browser: browser, coordinator: coordinator),
            scheme: scheme
        )
        return .of(color, isLight: PageInk.isLight(color, scheme: scheme))
    }
}
