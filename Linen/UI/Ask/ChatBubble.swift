// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

nonisolated struct ChatBubble: Shape {
    static let tail: CGFloat = 4
    static let drop: CGFloat = 2.5

    private static let rise: CGFloat = 4
    private static let back: CGFloat = 5

    var radius: CGFloat = 15

    func path(in rect: CGRect) -> Path {
        let body = CGRect(
            x: rect.minX,
            y: rect.minY,
            width: max(rect.width - Self.tail, radius),
            height: max(rect.height - Self.drop, radius)
        )
        let r = min(radius, body.height / 2)

        var path = Path()
        path.move(to: CGPoint(x: body.minX + r, y: body.minY))
        path.addLine(to: CGPoint(x: body.maxX - r, y: body.minY))
        path.addQuadCurve(
            to: CGPoint(x: body.maxX, y: body.minY + r),
            control: CGPoint(x: body.maxX, y: body.minY)
        )
        path.addLine(to: CGPoint(x: body.maxX, y: body.maxY - Self.rise))
        path.addQuadCurve(
            to: CGPoint(x: body.maxX + Self.tail, y: body.maxY + Self.drop),
            control: CGPoint(x: body.maxX + Self.tail * 0.5, y: body.maxY + Self.drop * 0.3)
        )
        path.addQuadCurve(
            to: CGPoint(x: body.maxX - Self.back, y: body.maxY),
            control: CGPoint(x: body.maxX - Self.back * 0.2, y: body.maxY)
        )
        path.addLine(to: CGPoint(x: body.minX + r, y: body.maxY))
        path.addQuadCurve(
            to: CGPoint(x: body.minX, y: body.maxY - r),
            control: CGPoint(x: body.minX, y: body.maxY)
        )
        path.addLine(to: CGPoint(x: body.minX, y: body.minY + r))
        path.addQuadCurve(
            to: CGPoint(x: body.minX + r, y: body.minY),
            control: CGPoint(x: body.minX, y: body.minY)
        )
        path.closeSubpath()
        return path
    }
}
