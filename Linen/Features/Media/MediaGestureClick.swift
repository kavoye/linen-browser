// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import os
import WebKit

enum MediaGestureClick {
    static func click(_ webView: WKWebView, atPagePoint cssPoint: CGPoint) {
        let bounds = webView.bounds
        let raw = NSPoint(
            x: cssPoint.x,
            y: cssPoint.y + webView.obscuredContentInsets.top
        )
        let point = NSPoint(
            x: min(max(raw.x, bounds.minX + 1), bounds.maxX - 1),
            y: min(max(raw.y, bounds.minY + 1), bounds.maxY - 1)
        )
        deliver(to: webView, at: point)
    }

    static func click(_ webView: WKWebView, viewportRect: CGRect?) {
        let point: NSPoint
        if let rect = viewportRect,
           let crop = MediaCropMath.visibleCrop(
               viewportRect: rect,
               viewBounds: webView.bounds,
               topInset: webView.obscuredContentInsets.top
           ) {
            point = NSPoint(x: crop.midX, y: crop.midY)
        } else {
            point = NSPoint(x: webView.bounds.midX, y: webView.bounds.midY)
        }
        deliver(to: webView, at: point)
    }

    private static func deliver(to webView: WKWebView, at point: NSPoint) {
        guard let window = webView.window else {
            Pipeline.log.notice("media: no hosting window for gesture click")
            return
        }
        let windowPoint = webView.convert(point, to: nil)
        func mouseEvent(_ type: NSEvent.EventType) -> NSEvent? {
            NSEvent.mouseEvent(
                with: type,
                location: windowPoint,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )
        }
        if let down = mouseEvent(.leftMouseDown) {
            webView.mouseDown(with: down)
        }
        if let up = mouseEvent(.leftMouseUp) {
            webView.mouseUp(with: up)
        }
    }
}
