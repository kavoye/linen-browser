// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI
import Testing

@testable import Linen

struct PermissionBadgeTests {
    private func resolved(_ color: Color) -> NSColor {
        NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
    }

    private func differ(_ one: Color, _ other: Color) -> Bool {
        let first = resolved(one)
        let second = resolved(other)
        return abs(first.redComponent - second.redComponent)
            + abs(first.greenComponent - second.greenComponent)
            + abs(first.blueComponent - second.blueComponent) > 0.15
    }

    @Test func aLiveCameraIsNotTheSameColorAsALiveMicrophone() {
        #expect(differ(
            WebPermission.camera.liveTint,
            WebPermission.microphone.liveTint
        ))
    }

    @Test func theRecordingPermissionsStandApartFromTheAccent() {
        #expect(differ(WebPermission.camera.liveTint, Theme.accent))
        #expect(differ(WebPermission.microphone.liveTint, Theme.accent))
    }

    @Test func everyPermissionHasALiveTint() {
        for permission in WebPermission.allCases {
            #expect(resolved(permission.liveTint).alphaComponent > 0)
        }
    }

    // MARK: - Symbols

    @Test func eachPermissionIsDrawnWithItsOwnSymbol() {
        let symbols = WebPermission.allCases.map(\.symbol)
        #expect(symbols.count == Set(symbols).count)
    }

    @Test func aRefusedPermissionIsDrawnStruckThrough() {
        for permission in WebPermission.allCases {
            #expect(permission.slashedSymbol != permission.symbol, "\(permission)")
            #expect(permission.slashedSymbol.contains("slash"), "\(permission)")
        }
    }

    @Test func everySymbolExistsInTheSystemLibrary() {
        for permission in WebPermission.allCases {
            #expect(NSImage(systemSymbolName: permission.symbol, accessibilityDescription: nil) != nil, "\(permission.symbol)")
            #expect(
                NSImage(systemSymbolName: permission.slashedSymbol, accessibilityDescription: nil) != nil,
                "\(permission.slashedSymbol)"
            )
        }
    }
}
