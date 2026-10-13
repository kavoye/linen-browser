// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import CoreGraphics
import Foundation
import Testing

@testable import Linen

@MainActor
struct SidebarDragTargetTests {
    @Test func aListFloatingOverThePageKeepsTheDrag() {
        let model = SidebarDragModel()
        model.contentFrameInWindow = CGRect(x: 0, y: 0, width: 1000, height: 700)
        model.listOriginInWindow = CGPoint(x: 350, y: 200)
        model.listSizeInWindow = CGSize(width: 300, height: 400)

        #expect(!model.pageOwns(CGPoint(x: 400, y: 300)))
        #expect(model.pageOwns(CGPoint(x: 100, y: 300)))
    }

    @Test func aListBesideThePageHandsOverAtItsEdge() {
        let model = SidebarDragModel()
        model.listOriginInWindow = .zero
        model.listSizeInWindow = CGSize(width: 260, height: 700)
        model.contentFrameInWindow = CGRect(x: 266, y: 0, width: 734, height: 700)

        #expect(!model.pageOwns(CGPoint(x: 120, y: 300)))
        #expect(model.pageOwns(CGPoint(x: 500, y: 300)))
    }
}
