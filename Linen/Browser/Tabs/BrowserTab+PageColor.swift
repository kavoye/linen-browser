// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI
import WebKit

extension BrowserTab {
    func holdPageColorUntilLoaded() {
        guard isShowingRealPage else {
            clearPageColor()
            return
        }
        holdsPageColor = true
    }

    func releasePageColorHold() {
        holdsPageColor = false
    }

    func refreshPageColor(from webView: WKWebView) {
        guard isShowingRealPage else {
            clearPageColor()
            return
        }
        guard provisionalNavigation == nil, !holdsPageColor else { return }
        guard hasPresentedContent else {
            setPageColor(nil)
            return
        }
        measureBandUnderBar()
    }

    func measureBandUnderBar() {
        guard isShowingRealPage, hasPresentedContent, !holdsPageColor, webView.window != nil,
              webView.bounds.height > 0 else { return }
        guard !isMeasuringBand else {
            // The first presentation can still contain the old/blank frame.
            // Keep the didFinish request instead of dropping it behind that
            // early snapshot.
            needsBandRemeasure = true
            return
        }
        isMeasuringBand = true
        needsBandRemeasure = false
        let requestedURL = urlString
        let bandFraction = Theme.topBarHeight / webView.bounds.height
        let configuration = WKSnapshotConfiguration()
        configuration.snapshotWidth = 48
        configuration.afterScreenUpdates = true
        webView.takeSnapshot(with: configuration) { [weak self] image, _ in
            guard let self else { return }
            isMeasuringBand = false
            let shouldRemeasure = needsBandRemeasure
            needsBandRemeasure = false
            defer {
                if shouldRemeasure {
                    measureBandUnderBar()
                }
            }
            guard urlString == requestedURL, provisionalNavigation == nil,
                  hasPresentedContent, !holdsPageColor,
                  let image,
                  let average = Self.averageOfTopBand(of: image, fraction: bandFraction)
            else { return }
            setPageColor(average)
        }
    }

    func webViewDidBecomeVisible() {
        refreshCanvas(from: webView)
        refreshPageColor(from: webView)
    }

    static func averageOfTopBand(of image: NSImage, fraction: CGFloat) -> NSColor? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              cg.height > 0
        else { return nil }
        let bandHeight = max(1, Int(CGFloat(cg.height) * min(max(fraction, 0), 1)))
        guard let band = cg.cropping(to: CGRect(x: 0, y: 0, width: cg.width, height: bandHeight)),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.interpolationQuality = .medium
        context.draw(band, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let data = context.data else { return nil }
        let pixel = data.bindMemory(to: UInt8.self, capacity: 4)
        return NSColor(
            srgbRed: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1
        )
    }

    fileprivate func clearPageColor() {
        setPageColor(nil)
    }

    private func setPageColor(_ color: NSColor?) {
        guard !Self.perceptuallyEqual(pageColor, color) else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            pageColor = color
        }
    }

    private static func perceptuallyEqual(_ a: NSColor?, _ b: NSColor?) -> Bool {
        guard let a = a?.usingColorSpace(.sRGB), let b = b?.usingColorSpace(.sRGB) else {
            return (a == nil) && (b == nil)
        }
        return abs(a.redComponent - b.redComponent) < 0.02
            && abs(a.greenComponent - b.greenComponent) < 0.02
            && abs(a.blueComponent - b.blueComponent) < 0.02
    }
}
