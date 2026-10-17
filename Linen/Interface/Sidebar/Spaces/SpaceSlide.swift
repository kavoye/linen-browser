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
    var pull: CGFloat = 0
    var loomTravel: Double = 0
    var isStaged = false
    var gliding: SpaceGlideTarget?
    var held: [SidebarItem]?

    var travel: CGFloat {
        guard peer != nil, width > 0 else { return 0 }
        return min(1, abs(offset) / width)
    }
    @ObservationIgnored var width: CGFloat = 260
    @ObservationIgnored var scroll: CGFloat = 0
    @ObservationIgnored var glideTurn = 0
    @ObservationIgnored var glideVelocity: Double = 0

    func reset() {
        isStaged = false
        gliding = nil
        held = nil
        offset = 0
        peer = nil
        pull = 0
        loomTravel = 0
        isSliding = false
    }
}
