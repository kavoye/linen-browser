// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

@MainActor
@Observable
final class ReaderAppearance {
    static let shared = ReaderAppearance()

    nonisolated enum Typeface: String, CaseIterable, Identifiable {
        case athelas
        case charter
        case georgia
        case iowan
        case serif
        case palatino
        case system
        case seravek
        case times

        var id: Self {
            self
        }

        var name: String {
            switch self {
            case .athelas:
                "Athelas"
            case .charter:
                "Charter"
            case .georgia:
                "Georgia"
            case .iowan:
                "Iowan"
            case .serif:
                "New York"
            case .palatino:
                "Palatino"
            case .system:
                "San Francisco"
            case .seravek:
                "Seravek"
            case .times:
                "Times New Roman"
            }
        }

        var family: String? {
            switch self {
            case .athelas:
                "Athelas"
            case .charter:
                "Charter"
            case .georgia:
                "Georgia"
            case .iowan:
                "Iowan Old Style"
            case .palatino:
                "Palatino"
            case .seravek:
                "Seravek"
            case .times:
                "Times New Roman"
            case .serif, .system:
                nil
            }
        }

        var cssFamily: String {
            switch self {
            case .system:
                "-apple-system, system-ui, sans-serif"
            case .serif:
                "ui-serif, \"New York\", Georgia, serif"
            case .seravek:
                "\"Seravek\", -apple-system, sans-serif"
            default:
                "\"\(family ?? name)\", ui-serif, Georgia, serif"
            }
        }

        func font(size: CGFloat) -> Font {
            switch self {
            case .system:
                .system(size: size)
            case .serif:
                .system(size: size, design: .serif)
            default:
                .custom(family ?? name, size: size)
            }
        }
    }

    nonisolated enum Palette: String, CaseIterable, Identifiable {
        case automatic
        case light
        case sepia
        case dark

        var id: Self {
            self
        }

        var title: LocalizedStringResource {
            switch self {
            case .automatic:
                "Automatic"
            case .light:
                "Light"
            case .sepia:
                "Sepia"
            case .dark:
                "Dark"
            }
        }
    }

    nonisolated static let textSizes: [Int] = [15, 17, 19, 21, 24, 28, 32]
    nonisolated static let defaultSizeIndex = 2

    var typeface: Typeface {
        didSet { defaults.set(typeface.rawValue, forKey: Keys.typeface) }
    }

    var palette: Palette {
        didSet { defaults.set(palette.rawValue, forKey: Keys.palette) }
    }

    private(set) var sizeIndex: Int {
        didSet { defaults.set(sizeIndex, forKey: Keys.size) }
    }

    var textSize: Int {
        Self.textSizes[sizeIndex]
    }

    var canGrow: Bool {
        sizeIndex < Self.textSizes.count - 1
    }

    var canShrink: Bool {
        sizeIndex > 0
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let typeface = "readerTypeface"
        static let palette = "readerTheme"
        static let size = "readerTextSize"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        typeface = defaults.string(forKey: Keys.typeface).flatMap(Typeface.init) ?? .system
        palette = defaults.string(forKey: Keys.palette).flatMap(Palette.init) ?? .automatic
        let stored = defaults.object(forKey: Keys.size) as? Int ?? Self.defaultSizeIndex
        sizeIndex = Self.textSizes.indices.contains(stored) ? stored : Self.defaultSizeIndex
    }

    func grow() {
        if canGrow {
            sizeIndex += 1
        }
    }

    func shrink() {
        if canShrink {
            sizeIndex -= 1
        }
    }

    var isDefaultSize: Bool {
        sizeIndex == Self.defaultSizeIndex
    }

    func resetSize() {
        sizeIndex = Self.defaultSizeIndex
    }

    var isDefault: Bool {
        typeface == .system && palette == .automatic && sizeIndex == Self.defaultSizeIndex
    }

    func reset() {
        typeface = .system
        palette = .automatic
        sizeIndex = Self.defaultSizeIndex
    }

    func resolvedPalette(isDark: Bool) -> Palette {
        guard palette == .automatic else { return palette }
        return isDark ? .dark : .light
    }

    nonisolated static func background(for palette: Palette) -> NSColor {
        switch palette {
        case .automatic, .light:
            NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        case .sepia:
            NSColor(srgbRed: 0.973, green: 0.945, blue: 0.890, alpha: 1)
        case .dark:
            NSColor(srgbRed: 0.118, green: 0.118, blue: 0.125, alpha: 1)
        }
    }
}
