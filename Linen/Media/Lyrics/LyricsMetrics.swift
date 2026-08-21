// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import SwiftUI

nonisolated enum LyricsTextSize: String, CaseIterable, Sendable {
    case small
    case regular
    case large
    case huge

    var scale: CGFloat {
        switch self {
        case .small:
            0.85
        case .regular:
            1
        case .large:
            1.2
        case .huge:
            1.45
        }
    }

    var label: LocalizedStringResource {
        switch self {
        case .small:
            "Small"
        case .regular:
            "Regular"
        case .large:
            "Large"
        case .huge:
            "Extra Large"
        }
    }
}

nonisolated enum LyricsMetrics {
    static let focus: CGFloat = 0.42
    static let widestColumn: CGFloat = 760
    static let dimmestWord: Double = 0.58
    static let holdAfterScrolling: Double = 4

    static func fontSize(forWidth width: CGFloat, scale: CGFloat = 1) -> CGFloat {
        (min(max((width * 0.042).rounded(), 20), 38) * scale).rounded()
    }

    static func lineGap(forFontSize size: CGFloat) -> CGFloat {
        (size * 0.66).rounded()
    }

    static func columnWidth(forWidth width: CGFloat) -> CGFloat {
        let inset = min(96, width * 0.12)
        return min(max(width - inset, 160), widestColumn)
    }

    static func fade(atDistance distance: Int) -> Double {
        switch abs(distance) {
        case 0:
            1
        case 1:
            0.3
        case 2:
            0.24
        case 3:
            0.19
        default:
            0.15
        }
    }

    static func sungShare(of word: LyricsWord, at time: Double) -> Double {
        guard time < word.end else { return 1 }
        guard time > word.start else { return 0 }
        let span = word.end - word.start
        guard span > 0 else { return 1 }
        return eased((time - word.start) / span)
    }

    static func wordOpacity(_ share: Double) -> Double {
        dimmestWord + (1 - dimmestWord) * share
    }

    static func gapProgress(_ line: LyricsLine, at time: Double) -> Double {
        let span = line.duration
        guard span > 0 else { return 0 }
        return min(max((time - line.start) / span, 0), 1)
    }

    static func dotFill(_ index: Int, progress: Double, of count: Int = 3) -> Double {
        guard count > 0 else { return 0 }
        let share = 1 / Double(count)
        let local = (progress - Double(index) * share) / share
        return min(max(local, 0), 1)
    }

    private static func eased(_ value: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }
}
