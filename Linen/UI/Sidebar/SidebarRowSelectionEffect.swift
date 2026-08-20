// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

private struct SidebarRowSelectionEffect: ViewModifier {
    let isSelected: Bool
    let isHovering: Bool
    var isDropTarget = false
    var isDropCandidate = false
    var radius = Theme.Radius.hover

    private var fill: AnyShapeStyle {
        if isDropTarget {
            return AnyShapeStyle(Theme.accent.opacity(0.16))
        }
        if isDropCandidate {
            return AnyShapeStyle(Theme.accent.opacity(0.08))
        }
        if isSelected {
            return AnyShapeStyle(Theme.Wash.selection)
        }
        if isHovering {
            return AnyShapeStyle(Theme.Wash.faint)
        }
        return AnyShapeStyle(.clear)
    }

    private var stroke: AnyShapeStyle {
        if isDropTarget {
            return AnyShapeStyle(Theme.accent)
        }
        if isDropCandidate {
            return AnyShapeStyle(Theme.accent.opacity(0.45))
        }
        return AnyShapeStyle(isSelected ? Theme.Wash.hover : Theme.Wash.none)
    }

    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(stroke, lineWidth: isDropTarget ? 2 : 1)
            )
    }
}

extension View {
    func sidebarRowSelectionEffect(
        isSelected: Bool,
        isHovering: Bool,
        isDropTarget: Bool = false,
        isDropCandidate: Bool = false,
        radius: CGFloat = Theme.Radius.hover
    ) -> some View {
        modifier(SidebarRowSelectionEffect(
            isSelected: isSelected,
            isHovering: isHovering,
            isDropTarget: isDropTarget,
            isDropCandidate: isDropCandidate,
            radius: radius
        ))
    }
}
